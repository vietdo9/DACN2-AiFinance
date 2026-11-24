const fs = require('fs');
const crypto = require('crypto');

function readArray(filePath) {
    const value = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
    if (!Array.isArray(value)) throw new Error('Local account data is not an array');
    return value;
}

function writeArrayAtomic(filePath, value) {
    const temporaryPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
    try {
        fs.writeFileSync(temporaryPath, JSON.stringify(value, null, 2), { encoding: 'utf-8', flag: 'wx' });
        fs.renameSync(temporaryPath, filePath);
    } catch (error) {
        try { if (fs.existsSync(temporaryPath)) fs.unlinkSync(temporaryPath); } catch (_) {}
        throw error;
    }
}

function emailHash(value) {
    return crypto.createHash('sha256').update(String(value || '').trim().toLowerCase()).digest('hex');
}

function deleteUserDataFromFiles({ userId, usersFile, transactionsFile, walletsFile, rulesFile, requireUser = false, removeUser = true, expectedEmailHash }) {
    const users = readArray(usersFile);
    const user = users.find(row => row.id === userId) || null;
    if (requireUser && !user) return { found: false };
    if (user && expectedEmailHash && emailHash(user.email) !== expectedEmailHash) {
        return { found: Boolean(user), identityMismatch: true };
    }

    const transactions = readArray(transactionsFile).filter(row => row.user_id !== userId);
    const wallets = readArray(walletsFile).filter(row => row.user_id !== userId);
    const rules = readArray(rulesFile).filter(row => row.user_id !== userId);
    writeArrayAtomic(transactionsFile, transactions);
    writeArrayAtomic(walletsFile, wallets);
    writeArrayAtomic(rulesFile, rules);
    if (user && removeUser) writeArrayAtomic(usersFile, users.filter(row => row.id !== userId));
    return { found: Boolean(user) };
}

module.exports = { deleteUserDataFromFiles, emailHash, readArray, writeArrayAtomic };
