'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { getAdminPeriod, validDate, vietnamToday } = require('./services/adminPeriod');

function test(name, fn) {
    fn();
    console.log(`PASS ${name}`);
}

test('week bounds are Monday through Sunday across year boundary', () => {
    assert.deepStrictEqual(getAdminPeriod('week', '2021-01-01'), {
        type: 'week', start_date: '2020-12-28', end_date: '2021-01-03'
    });
});

test('month bounds include leap day and month end', () => {
    assert.deepStrictEqual(getAdminPeriod('month', '2024-02-29'), {
        type: 'month', start_date: '2024-02-01', end_date: '2024-02-29'
    });
});

test('all period is unbounded and date with all is rejected', () => {
    assert.deepStrictEqual(getAdminPeriod('all'), { type: 'all', start_date: null, end_date: null });
    assert.strictEqual(getAdminPeriod('all', '2024-01-01').error, 'AMBIGUOUS_PERIOD_DATE');
});

test('rejects invalid period, malformed date, and impossible calendar dates', () => {
    assert.strictEqual(getAdminPeriod('day').error, 'INVALID_PERIOD');
    assert.strictEqual(validDate('2024-2-01'), false);
    assert.strictEqual(validDate('2023-02-29'), false);
    assert.strictEqual(getAdminPeriod('month', '2023-02-29').error, 'INVALID_DATE');
    assert.strictEqual(getAdminPeriod('week', '9999-12-31').error, 'INVALID_DATE');
    assert.strictEqual(validDate('0001-01-01'), true);
});

test('Vietnam today uses the Vietnam calendar date', () => {
    assert.strictEqual(vietnamToday(new Date('2024-12-31T17:30:00.000Z')), '2025-01-01');
});

test('period aggregate RPC filters transaction_date and grants only service_role', () => {
    const sql = fs.readFileSync(path.join(__dirname, 'migrations', '20261125_admin_overview_period.sql'), 'utf8');
    assert.match(sql, /admin_overview_data_period\(text\[\],text\[\],date,date\)/);
    assert.match(sql, /transaction_date >= p_period_start/);
    assert.match(sql, /transaction_date <= p_period_end/);
    assert.match(sql, /REVOKE ALL ON FUNCTION public\.admin_overview_data_period[\s\S]*FROM PUBLIC, anon, authenticated/);
    assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.admin_overview_data_period[\s\S]*TO service_role/);
});
