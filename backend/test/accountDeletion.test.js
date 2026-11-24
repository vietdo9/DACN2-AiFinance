const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../middlewares/auth');
const { issueDeletionChallenge, validateDeletionChallenge, MIN_WAIT_MS } = require('../services/accountDeletionChallenge');
const { deleteUserDataFromFiles } = require('../services/localAccountCleanup');

function request(token = 'current-session-token') {
    return { headers: { authorization: `Bearer ${token}` } };
}

test('deletion challenge has a strict 15 second minimum and binds to bearer and session', () => {
    const start = 1_800_000_000_000;
    const req = request();
    const challenge = issueDeletionChallenge({ userId: 'user-a', sessionVersion: 4, req, now: start });
    const verifyAt = now => validateDeletionChallenge({ challenge, userId: 'user-a', sessionVersion: 4, req, now });

    assert.equal(verifyAt(start + MIN_WAIT_MS - 1), false);
    assert.equal(verifyAt(start + MIN_WAIT_MS), true);
    assert.equal(validateDeletionChallenge({ challenge, userId: 'user-a', sessionVersion: 5, req, now: start + MIN_WAIT_MS }), false);
    assert.equal(validateDeletionChallenge({ challenge, userId: 'user-a', sessionVersion: 4, req: request('another-session'), now: start + MIN_WAIT_MS }), false);
    assert.equal(verifyAt(start + 10 * 60_000), false);

    // An intent is not an API session token, even if sent as a bearer.
    assert.throws(() => jwt.verify(challenge, JWT_SECRET, { algorithms: ['HS256'] }));
});

test('local cleanup fixture removes only the selected user and is safely retryable', t => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'finwise-delete-fixture-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const files = Object.fromEntries(['users', 'transactions', 'wallets', 'rules'].map(name => [name, path.join(directory, `${name}.json`)]));
    const fixture = {
        users: [{ id: 'target', email: 'target@example.test' }, { id: 'other', email: 'other@example.test' }],
        transactions: [{ id: 'tx1', user_id: 'target' }, { id: 'tx2', user_id: 'other' }],
        wallets: [{ id: 'wallet1', user_id: 'target' }, { id: 'wallet2', user_id: 'other' }],
        rules: [{ id: 'rule1', user_id: 'target' }, { id: 'rule2', user_id: 'other' }]
    };
    for (const name of Object.keys(files)) fs.writeFileSync(files[name], JSON.stringify(fixture[name]), 'utf-8');
    const args = { userId: 'target', usersFile: files.users, transactionsFile: files.transactions, walletsFile: files.wallets, rulesFile: files.rules, requireUser: true };

    assert.deepEqual(deleteUserDataFromFiles(args), { found: true });
    assert.deepEqual(deleteUserDataFromFiles(args), { found: false });
    for (const name of Object.keys(files)) {
        const remaining = JSON.parse(fs.readFileSync(files[name], 'utf-8'));
        assert.equal(remaining.length, 1);
        assert.equal(remaining[0].user_id || remaining[0].id, 'other');
    }
});

test('local cleanup leaves files untouched when a JSON fixture is malformed', t => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'finwise-delete-malformed-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const files = Object.fromEntries(['users', 'transactions', 'wallets', 'rules'].map(name => [name, path.join(directory, `${name}.json`)]));
    for (const name of Object.keys(files)) fs.writeFileSync(files[name], name === 'rules' ? '{broken' : '[]', 'utf-8');
    assert.throws(() => deleteUserDataFromFiles({ userId: 'target', usersFile: files.users, transactionsFile: files.transactions, walletsFile: files.wallets, rulesFile: files.rules }));
    assert.equal(fs.readFileSync(files.users, 'utf-8'), '[]');
    assert.equal(fs.readFileSync(files.transactions, 'utf-8'), '[]');
});

test('cloud spillover cleanup preserves a different local identity sharing an ID', t => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'finwise-delete-collision-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const files = Object.fromEntries(['users', 'transactions', 'wallets', 'rules'].map(name => [name, path.join(directory, `${name}.json`)]));
    const fixture = {
        users: [{ id: 'shared-id', email: 'different@example.test' }],
        transactions: [{ id: 'tx', user_id: 'shared-id' }],
        wallets: [{ id: 'wallet', user_id: 'shared-id' }],
        rules: [{ id: 'rule', user_id: 'shared-id' }]
    };
    for (const name of Object.keys(files)) fs.writeFileSync(files[name], JSON.stringify(fixture[name]), 'utf-8');
    const { createHash } = require('node:crypto');
    const expectedEmailHash = createHash('sha256').update('cloud@example.test').digest('hex');
    const result = deleteUserDataFromFiles({ userId: 'shared-id', usersFile: files.users, transactionsFile: files.transactions, walletsFile: files.wallets, rulesFile: files.rules, expectedEmailHash });
    assert.equal(result.identityMismatch, true);
    for (const name of Object.keys(files)) assert.deepEqual(JSON.parse(fs.readFileSync(files[name], 'utf-8')), fixture[name]);
});
