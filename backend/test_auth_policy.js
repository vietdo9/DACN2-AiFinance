const assert = require('assert');
const {
    isAdminPrincipal,
    isLegacyDefaultAdminPassword,
    isReservedAdminEmail,
    roleForUser,
    SYNTHETIC_ADMIN_ID
} = require('./services/authPolicy');

function test(name, callback) {
    try {
        callback();
        console.log(`PASS ${name}`);
    } catch (error) {
        console.error(`FAIL ${name}`);
        throw error;
    }
}

test('admin-like user aliases do not grant admin role', () => {
    assert.strictEqual(roleForUser({ email: 'admin-user@example.com' }), 'user');
    assert.strictEqual(roleForUser({ email: 'admin@finwise.com' }), 'user');
});

test('reserved admin addresses cannot be registered', () => {
    assert.strictEqual(isReservedAdminEmail(' Admin@FinWise.com '), true);
    assert.strictEqual(isReservedAdminEmail('new-user@example.com'), false);
});

test('known legacy default admin password is rejected', () => {
    assert.strictEqual(isLegacyDefaultAdminPassword('admin123456'), true);
    assert.strictEqual(isLegacyDefaultAdminPassword('a-custom-password'), false);
});

test('only newly authenticated real admin principals pass the guard', () => {
    assert.strictEqual(isAdminPrincipal({ id: 'real-user-id', role: 'admin', admin_auth_version: 2 }), true);
    assert.strictEqual(isAdminPrincipal({ id: 'real-user-id', role: 'admin' }), false);
    assert.strictEqual(isAdminPrincipal({ id: SYNTHETIC_ADMIN_ID, role: 'admin', admin_auth_version: 2 }), false);
    assert.strictEqual(isAdminPrincipal({ id: 'real-user-id', role: 'user', admin_auth_version: 2 }), false);
});

test('explicit administrator configuration grants role without alias inference', () => {
    const previous = process.env.FINWISE_ADMIN_EMAILS;
    process.env.FINWISE_ADMIN_EMAILS = 'finance-owner@example.com';
    try {
        assert.strictEqual(isReservedAdminEmail('finance-owner@example.com'), true);
        assert.strictEqual(roleForUser({ email: 'finance-owner@example.com' }), 'admin');
        assert.strictEqual(roleForUser({ email: 'admin@finwise.com' }), 'user');
    } finally {
        if (previous === undefined) delete process.env.FINWISE_ADMIN_EMAILS;
        else process.env.FINWISE_ADMIN_EMAILS = previous;
    }
});
