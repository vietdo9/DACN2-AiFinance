const assert = require('node:assert/strict');
const test = require('node:test');
const { getPeriod, buildForecast } = require('./services/spendingForecast');

const period = getPeriod(new Date('2026-12-30T17:15:00Z'));
const rows = Array.from({ length: 30 }, (_, i) => ({
    transaction_date: new Date(period.historyStart.getTime() + i * 86400000).toISOString().slice(0, 10),
    amount: 70000
}));

test('insufficient history does not invoke the model or produce a projection', async () => {
    const result = await buildForecast(rows.slice(-1), period, () => assert.fail('model called'));
    assert.equal(result.has_enough_data, false);
    assert.equal(result.data, null);
});

test('established accounts with only a few expense days receive a limited estimate', async () => {
    const { data } = await buildForecast([rows[0], rows[26]], period,
        () => assert.fail('sparse history should skip the model'));
    assert.equal(data.history_days, 30);
    assert.equal(data.active_days, 2);
    assert.equal(data.predicted_next_7_days[0], 4667);
    assert.match(data.message, /Lịch sử còn ít/);
});

test('a shorter history uses its actual observation window', async () => {
    const { data } = await buildForecast([rows[20], rows[27]], period,
        () => assert.fail('short history should skip the model'));
    assert.equal(data.history_days, 10);
    assert.deepEqual(data.predicted_next_7_days, Array(7).fill(14000));
});

test('LSTM starts at 20 observed days and still receives a 30-day input', async () => {
    const short = await buildForecast(rows.slice(-19), period,
        () => assert.fail('19 days should use the recorded average'));
    assert.equal(short.data.engine, 'Trung bình chi tiêu 19 ngày');

    const ready = await buildForecast(rows.slice(-20), period, async history => {
        assert.deepEqual(history, [...Array(10).fill(0), ...Array(20).fill(70000)]);
        return { predicted_next_7_days: Array(7).fill(70000) };
    });
    assert.equal(ready.data.history_days, 20);
    assert.match(ready.data.engine, /^LSTM/);
});

test('many expenses on one day or only a few days of history remain insufficient', async () => {
    for (const history of [Array(10).fill(rows[0]), rows.slice(-2)]) {
        const result = await buildForecast(history, period, () => assert.fail('model called'));
        assert.equal(result.has_enough_data, false);
    }
});

test('matches the model horizon to Vietnam dates and excludes future actuals', async () => {
    const result = await buildForecast([
        ...rows,
        { transaction_date: '2026-12-31', amount: 10000 },
        { transaction_date: '2027-01-01', amount: 9000000 }
    ], period, async history => {
        assert.deepEqual(history, Array(30).fill(70000));
        return { predicted_next_7_days: [40000, 50000, 60000, 70000, 80000, 90000, 100000] };
    });
    const { data } = result;
    assert.equal(data.as_of, '2026-12-31');
    assert.equal(data.next_days_detail[0].date, '2027-01-01');
    assert.equal(data.next_days_detail.at(-1).date, '2027-01-07');
    assert.deepEqual(data.predicted_next_7_days, [50000, 60000, 70000, 80000, 90000, 100000, 70000]);
    assert.equal(data.week_days_detail[3].amount, 10000);
    assert.equal(data.week_days_detail[3].is_predicted, false);
    assert.equal(data.week_days_detail[4].amount, 50000);
    assert.equal(data.this_month_projected, data.this_month_spent);
    assert.equal(data.this_month_spent, 2110000);
    assert.equal(data.month_diff_percent, null);
});

test('uses recorded average when the model fails or returns invalid data', async () => {
    for (const predict of [
        async () => { throw new Error('Unavailable'); },
        async () => ({ predicted_next_7_days: [NaN, 0, 0, 0, 0, 0, 0] })
    ]) {
        const { data } = await buildForecast(rows, period, predict);
        assert.deepEqual(data.predicted_next_7_days, Array(7).fill(70000));
        assert.equal(data.engine, 'Trung bình chi tiêu 30 ngày');
    }
});

test('demo results are distinct from the user history', async () => {
    const result = await buildForecast([], period, () => assert.fail('model called'), true);
    assert.equal(result.is_demo_data, true);
    assert.equal(result.data.next_days_detail.length, 7);
});
