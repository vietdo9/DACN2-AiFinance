const assert = require('assert');
const fs = require('fs');
const path = require('path');
const router = require('./routes/admin.routes');

const test = (name, fn) => { fn(); console.log(`PASS ${name}`); };

test('profile accepts trimmed ordinary identity data and normalizes email', () => {
    assert.deepStrictEqual(router.validProfile('  Ada Lovelace  ', ' ADA@example.test '), {
        full_name: 'Ada Lovelace', email: 'ada@example.test'
    });
});

test('profile rejects empty, oversized, multiline names and malformed emails', () => {
    for (const input of [[' ', 'user@example.test'], ['A'.repeat(151), 'user@example.test'], ['A\nB', 'user@example.test'], ['Name', 'not-an-email']]) {
        assert.strictEqual(router.validProfile(...input), null);
    }
});

test('new password enforces ten characters and bcrypt byte limit', () => {
    assert.strictEqual(router.validNewPassword('123456789'), false);
    assert.strictEqual(router.validNewPassword('1234567890'), true);
    assert.strictEqual(router.validNewPassword('é'.repeat(37)), false);
});

test('unique database violations map to the duplicate email response', () => {
    const response = {
        statusCode: 200,
        status(code) { this.statusCode = code; return this; },
        json(body) { this.body = body; return this; }
    };
    router.mapUserRpcError({ code:'23505', message:'duplicate key value violates unique constraint' }, response);
    assert.strictEqual(response.statusCode, 409);
    assert.strictEqual(response.body.code, 'EMAIL_ALREADY_EXISTS');
});

test('additive SQL migration binds user management RPCs to service role only', () => {
    const sql = fs.readFileSync(path.join(__dirname, 'migrations', '20261124_admin_user_management.sql'), 'utf8');
    assert.match(sql, /admin_create_user\(/);
    assert.match(sql, /admin_update_user_profile\(/);
    assert.match(sql, /REVOKE ALL ON FUNCTION public\.admin_create_user[\s\S]*FROM PUBLIC, anon, authenticated/);
    assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.admin_create_user[\s\S]*TO service_role/);
    assert.match(sql, /'demo@finwise\.vn'/);
    assert.match(sql, /auth_session_version=auth_session_version\+CASE WHEN email_changed THEN 1 ELSE 0 END/);
});

async function verifyUnicodeBcryptRoundTrips() {
    const bcrypt = require('bcryptjs');
    for (const password of ['MậtKhẩu-đủDài-01', '🙂-unicode-password-2026']) {
        assert.strictEqual(router.validNewPassword(password), true);
        const hash = await bcrypt.hash(password, 4);
        assert.strictEqual(await bcrypt.compare(password, hash), true);
        assert.strictEqual(await bcrypt.compare(`${password}x`, hash), false);
    }
    console.log('PASS bcryptjs round trips accepted Unicode passwords without truncation');
}

verifyUnicodeBcryptRoundTrips().catch(error => { console.error(error); process.exitCode = 1; });
