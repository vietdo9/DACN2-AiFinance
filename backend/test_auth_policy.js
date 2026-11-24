const assert = require('assert');
const {
    isAdminPrincipal,
    isCurrentSession,
    isLegacyDefaultAdminPassword,
    isRootAdmin,
    hasAdminAuthSchema,
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

test('admin-like user aliases and legacy reserved addresses do not grant admin role', () => {
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
    assert.strictEqual(isAdminPrincipal({ id: 'real-user-id', role: 'admin', admin_auth_version: 3 }), true);
    assert.strictEqual(isAdminPrincipal({ id: 'real-user-id', role: 'admin' }), false);
    assert.strictEqual(isAdminPrincipal({ id: 'real-user-id', role: 'user', admin_auth_version: 3 }), false);
    assert.strictEqual(isAdminPrincipal({ id: SYNTHETIC_ADMIN_ID, role: 'admin', admin_auth_version: 3 }), false);
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

test('root designation requires exact configured real identity', () => {
    const previous = process.env.FINWISE_ROOT_ADMIN_EMAILS;
    process.env.FINWISE_ROOT_ADMIN_EMAILS = 'root@example.com';
    try {
        assert.strictEqual(isRootAdmin({ id: 'account-1', email: ' ROOT@example.com ' }), true);
        assert.strictEqual(isRootAdmin({ id: SYNTHETIC_ADMIN_ID, email: 'root@example.com' }), false);
        assert.strictEqual(isRootAdmin({ id: 'account-2', email: 'alias+root@example.com' }), false);
        assert.strictEqual(roleForUser({ id: 'account-1', email: 'root@example.com' }), 'admin');
    } finally {
        if (previous === undefined) delete process.env.FINWISE_ROOT_ADMIN_EMAILS;
        else process.env.FINWISE_ROOT_ADMIN_EMAILS = previous;
    }
});

test('admin privilege stays disabled until role and revocation columns are available', () => {
    assert.strictEqual(hasAdminAuthSchema({ id: 'u1', email: 'admin@example.com' }), false);
    assert.strictEqual(hasAdminAuthSchema({ id: 'u1', email: 'admin@example.com', role: 'admin' }), false);
    assert.strictEqual(hasAdminAuthSchema({ id: 'u1', email: 'admin@example.com', role: 'admin', status: 'active', auth_session_version: 0 }), true);
});

test('simulated configured root needs a fresh admin credential and current session version', () => {
    const current = { id: 'fixture-root-1', email: 'root-admin@example.test', role: 'admin', status: 'active', auth_session_version: 7 };
    const previous = process.env.FINWISE_ROOT_ADMIN_EMAILS;
    process.env.FINWISE_ROOT_ADMIN_EMAILS = 'root-admin@example.test';
    try {
        assert.strictEqual(isRootAdmin(current), true);
        assert.strictEqual(isCurrentSession(undefined, 0), true); // legacy normal user token remains a normal session
        assert.strictEqual(isCurrentSession(7, current.auth_session_version), true);
        assert.strictEqual(isCurrentSession(6, current.auth_session_version), false); // revoked, even after status returns active
        assert.strictEqual(isAdminPrincipal({ ...current, admin_auth_version: undefined }), false); // old user JWT cannot gain newly granted admin access
        assert.strictEqual(isAdminPrincipal({ ...current, admin_auth_version: 3 }), true); // password-verified login marker
        assert.strictEqual(isAdminPrincipal({ ...current, role: 'user', admin_auth_version: 3 }), false); // demoted now
    } finally {
        if (previous === undefined) delete process.env.FINWISE_ROOT_ADMIN_EMAILS;
        else process.env.FINWISE_ROOT_ADMIN_EMAILS = previous;
    }
});

async function testMockedAuthIntegration() {
    const path = require('path');
    const Module = require('module');
    const bcrypt = require('bcryptjs');
    const jwt = require('jsonwebtoken');
    const previous = {
        jwtSecret: process.env.JWT_SECRET,
        rootEmails: process.env.FINWISE_ROOT_ADMIN_EMAILS
    };
    process.env.JWT_SECRET = 'test-only-fixed-secret-for-auth-integration';
    process.env.FINWISE_ROOT_ADMIN_EMAILS = 'root-admin@example.test';

    const users = new Map();
    const byEmail = new Map();
    const supabase = {
        from() {
            return {
                select() {
                    return {
                        eq(column, value) {
                            return {
                                async maybeSingle() {
                                    const user = column === 'id' ? users.get(value) : byEmail.get(value);
                                    return { data: user || null, error: null };
                                }
                            };
                        }
                    };
                }
            };
        }
    };
    const store = {
        findUserById: (id) => null,
        findUserByEmail: (email) => null
    };
    const stub = (file, exports) => {
        const resolved = path.resolve(file);
        const module = new Module(resolved);
        module.filename = resolved;
        module.loaded = true;
        module.exports = exports;
        require.cache[resolved] = module;
        return resolved;
    };

    const stubs = [
        stub(require.resolve('dotenv'), { config: () => ({ parsed: {} }) }),
        stub(path.join(__dirname, 'config', 'supabase.js'), { supabase, isSupabaseConfigured: () => true }),
        stub(path.join(__dirname, 'config', 'localStore.js'), store)
    ];
    const middlewarePath = path.join(__dirname, 'middlewares', 'auth.js');
    const routesPath = path.join(__dirname, 'routes', 'auth.routes.js');
    delete require.cache[middlewarePath];
    delete require.cache[routesPath];

    const callRoute = async (handler, req) => new Promise((resolve) => {
        const res = {
            statusCode: 200,
            status(code) { this.statusCode = code; return this; },
            json(body) { resolve({ status: this.statusCode, body }); return this; }
        };
        handler(req, res);
    });
    const callAdmin = async (verifyAdmin, token) => new Promise((resolve) => {
        const res = {
            statusCode: 200,
            status(code) { this.statusCode = code; return this; },
            json(body) { resolve({ status: this.statusCode, body }); return this; }
        };
        verifyAdmin({ headers: { authorization: `Bearer ${token}` } }, res, () => resolve({ status: 200 }));
    });

    try {
        const ordinary = {
            id: 'fixture-user-1', email: 'user@example.test', full_name: 'Test User',
            password_hash: await bcrypt.hash('OrdinaryFixturePass!23', 4), role: 'user',
            status: 'active', auth_session_version: 0
        };
        const root = {
            id: 'fixture-root-1', email: 'root-admin@example.test', full_name: 'Fixture Root',
            password_hash: await bcrypt.hash('RootFixturePass!23', 4), role: 'admin',
            status: 'active', auth_session_version: 7
        };
        for (const user of [ordinary, root]) {
            users.set(user.id, user);
            byEmail.set(user.email, user);
        }

        const router = require(routesPath);
        const login = router.stack.find((layer) => layer.route?.path === '/login' && layer.route.methods.post).route.stack[0].handle;
        const rootLogin = await callRoute(login, { body: { email: root.email, password: 'RootFixturePass!23' } });
        assert.strictEqual(rootLogin.status, 200, 'fixture root logs in through bcrypt-backed route');
        const rootToken = rootLogin.body.data.token;
        const { verifyAdmin } = require(middlewarePath);
        assert.strictEqual((await callAdmin(verifyAdmin, rootToken)).status, 200, 'password-verified root reaches guarded endpoint');

        const ordinaryLogin = await callRoute(login, { body: { email: ordinary.email, password: 'OrdinaryFixturePass!23' } });
        assert.strictEqual(ordinaryLogin.status, 200);
        const oldUserToken = ordinaryLogin.body.data.token;
        ordinary.role = 'admin'; // simulate later role grant without a fresh password login
        assert.strictEqual((await callAdmin(verifyAdmin, oldUserToken)).status, 403, 'pre-elevation user token cannot access admin endpoint');

        const demoToken = jwt.sign({ id: '00000000-0000-0000-0000-000000000001', email: 'demo@finwise.vn', role: 'user' }, 'test-only-fixed-secret-for-auth-integration');
        assert.strictEqual((await callAdmin(verifyAdmin, demoToken)).status, 403, 'ordinary demo identity is denied admin endpoint');

        root.status = 'suspended';
        assert.strictEqual((await callAdmin(verifyAdmin, rootToken)).status, 403, 'current suspended state blocks existing root session');
        root.status = 'active';
        root.auth_session_version += 1;
        assert.strictEqual((await callAdmin(verifyAdmin, rootToken)).status, 401, 'old root session stays revoked after reactivation');
    } finally {
        delete require.cache[middlewarePath];
        delete require.cache[routesPath];
        for (const file of stubs) delete require.cache[file];
        if (previous.jwtSecret === undefined) delete process.env.JWT_SECRET;
        else process.env.JWT_SECRET = previous.jwtSecret;
        if (previous.rootEmails === undefined) delete process.env.FINWISE_ROOT_ADMIN_EMAILS;
        else process.env.FINWISE_ROOT_ADMIN_EMAILS = previous.rootEmails;
    }
}

testMockedAuthIntegration().then(() => {
    console.log('PASS mocked auth integration: bcrypt login, guarded admin, elevation, demo, suspension, revocation');
}).catch((error) => {
    console.error('FAIL mocked auth integration');
    console.error(error);
    process.exitCode = 1;
});
