const fs = require('fs');
const path = require('path');
const { deleteUserDataFromFiles, emailHash, readArray, writeArrayAtomic } = require('../services/localAccountCleanup');

const DATA_DIR = path.join(__dirname, '../data');
const USERS_FILE = path.join(DATA_DIR, 'local_users.json');
const WALLETS_FILE = path.join(DATA_DIR, 'local_wallets.json');
const TRANSACTIONS_FILE = path.join(DATA_DIR, 'local_transactions.json');

// Đảm bảo thư mục data tồn tại
if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
}

function ensureFile(filePath, defaultData = []) {
    if (!fs.existsSync(filePath)) {
        fs.writeFileSync(filePath, JSON.stringify(defaultData, null, 2), 'utf-8');
    }
}

ensureFile(USERS_FILE);
ensureFile(WALLETS_FILE);
ensureFile(TRANSACTIONS_FILE);

const RULES_FILE = path.join(DATA_DIR, 'local_category_rules.json');
const PENDING_CLOUD_CLEANUP_FILE = path.join(DATA_DIR, 'pending_cloud_account_cleanup.json');
ensureFile(RULES_FILE);
ensureFile(PENDING_CLOUD_CLEANUP_FILE);
const cloudDeletionGuards = new Map();
const cloudDeletionInFlight = new Set();
const CLOUD_DELETE_GUARD_MS = 10 * 60_000;

function isCloudUserWriteBlocked(userId) {
    const blockedUntil = cloudDeletionGuards.get(userId);
    if (!blockedUntil) return false;
    if (blockedUntil > Date.now() || cloudDeletionInFlight.has(userId)) return true;
    cloudDeletionGuards.delete(userId);
    return false;
}

function setCloudDeletionGuard(id) {
    const now = Date.now();
    for (const [userId, blockedUntil] of cloudDeletionGuards) {
        if (blockedUntil <= now && !cloudDeletionInFlight.has(userId)) cloudDeletionGuards.delete(userId);
    }
    cloudDeletionGuards.set(id, now + CLOUD_DELETE_GUARD_MS);
}

function readData(filePath) {
    try {
        ensureFile(filePath);
        const raw = fs.readFileSync(filePath, 'utf-8');
        return JSON.parse(raw);
    } catch (err) {
        return [];
    }
}

function writeData(filePath, data) {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf-8');
}

const localStore = {
    // USERS
    getUsers: () => readData(USERS_FILE),
    findUserByEmail: (email) => {
        const users = readData(USERS_FILE);
        return users.find(u => u.email.toLowerCase() === email.toLowerCase());
    },
    findUserById: (id) => {
        const users = readData(USERS_FILE);
        return users.find(u => u.id === id);
    },
    addUser: (user) => {
        const users = readData(USERS_FILE);
        users.push(user);
        writeData(USERS_FILE, users);
        return user;
    },
    updateUser: (id, updatedFields) => {
        let users = readData(USERS_FILE);
        const idx = users.findIndex(u => u.id === id);
        if (idx !== -1) {
            users[idx] = { ...users[idx], ...updatedFields, updated_at: new Date().toISOString() };
            writeData(USERS_FILE, users);
            return users[idx];
        }
        return null;
    },
    deleteUser: (id) => {
        let users = readData(USERS_FILE);
        const target = users.find(u => u.id === id);
        if (target) {
            users = users.filter(u => u.id !== id);
            writeData(USERS_FILE, users);
            // Đồng thời dọn dẹp ví và giao dịch của user này
            let txs = readData(TRANSACTIONS_FILE).filter(t => t.user_id !== id);
            writeData(TRANSACTIONS_FILE, txs);
            let wts = readData(WALLETS_FILE).filter(w => w.user_id !== id);
            writeData(WALLETS_FILE, wts);
            return target;
        }
        return null;
    },

    // Removes only rows tagged with this exact ID. Each JSON file replacement is
    // atomic and the operation is idempotent so an interrupted cleanup can retry.
    // Related rows are written before the account row, which remains the local
    // authority marker until all personal data has been cleaned successfully.
    deleteUserData: (id, { requireUser = false, removeUser = true, expectedEmailHash } = {}) => {
        return deleteUserDataFromFiles({
            userId: id,
            usersFile: USERS_FILE,
            transactionsFile: TRANSACTIONS_FILE,
            walletsFile: WALLETS_FILE,
            rulesFile: RULES_FILE,
            requireUser,
            removeUser,
            expectedEmailHash
        });
    },
    blockCloudUserWrites: (id) => setCloudDeletionGuard(id),
    clearCloudUserWriteGuard: (id) => cloudDeletionGuards.delete(id),
    beginCloudAccountDeletion: (id) => { setCloudDeletionGuard(id); cloudDeletionInFlight.add(id); },
    endCloudAccountDeletion: (id) => cloudDeletionInFlight.delete(id),
    isCloudAccountDeletionInFlight: (id) => cloudDeletionInFlight.has(id),
    queueCloudAccountCleanup: (id, expectedEmail) => {
        const pending = readArray(PENDING_CLOUD_CLEANUP_FILE).filter(item => item.user_id !== id);
        pending.push({ user_id: id, email_hash: emailHash(expectedEmail), retry_after_ms: Date.now() + 30_000 });
        writeArrayAtomic(PENDING_CLOUD_CLEANUP_FILE, pending);
        setCloudDeletionGuard(id);
    },
    clearCloudAccountCleanup: (id) => {
        cloudDeletionGuards.delete(id);
        const pending = readArray(PENDING_CLOUD_CLEANUP_FILE).filter(value => value.user_id !== id);
        writeArrayAtomic(PENDING_CLOUD_CLEANUP_FILE, pending);
    },
    completeCloudAccountCleanup: (id) => {
        const pending = readArray(PENDING_CLOUD_CLEANUP_FILE).filter(value => value.user_id !== id);
        writeArrayAtomic(PENDING_CLOUD_CLEANUP_FILE, pending);
    },
    getPendingCloudAccountCleanup: () => readArray(PENDING_CLOUD_CLEANUP_FILE),


    // WALLETS
    getWallets: (userId) => {
        const wallets = readData(WALLETS_FILE);
        return wallets.filter(w => w.user_id === userId);
    },
    addWallet: (wallet) => {
        if (isCloudUserWriteBlocked(wallet.user_id)) return null;
        const wallets = readData(WALLETS_FILE);
        wallets.push(wallet);
        writeData(WALLETS_FILE, wallets);
        return wallet;
    },
    updateWalletBalance: (walletId, delta) => {
        const wallets = readData(WALLETS_FILE);
        const w = wallets.find(item => item.id === walletId);
        if (w && isCloudUserWriteBlocked(w.user_id)) return null;
        if (w) {
            w.balance = (parseFloat(w.balance || 0) + parseFloat(delta)).toFixed(2);
            writeData(WALLETS_FILE, wallets);
            return w;
        }
        return null;
    },

    // TRANSACTIONS (Hoàn toàn độc lập theo user_id)
    getTransactions: (userId, { type, category, limit = 50 } = {}) => {
        const txs = readData(TRANSACTIONS_FILE);
        let userTxs = txs.filter(t => t.user_id === userId);
        if (type) userTxs = userTxs.filter(t => t.type === type);
        if (category) userTxs = userTxs.filter(t => t.category_code === category);
        // Sắp xếp ngày & thời gian mới nhất lên đầu
        userTxs.sort((a, b) => {
            const dateA = new Date(a.transaction_date).getTime();
            const dateB = new Date(b.transaction_date).getTime();
            if (dateB !== dateA) return dateB - dateA;
            const timeA = new Date(a.created_at || a.created_date || 0).getTime();
            const timeB = new Date(b.created_at || b.created_date || 0).getTime();
            if (timeB !== timeA) return timeB - timeA;
            return (b.id || '').localeCompare(a.id || '');
        });
        return userTxs.slice(0, parseInt(limit));
    },
    findTransactionById: (id, userId) => {
        const txs = readData(TRANSACTIONS_FILE);
        return txs.find(t => t.id === id && t.user_id === userId);
    },
    addTransaction: (tx) => {
        if (isCloudUserWriteBlocked(tx.user_id)) return null;
        const txs = readData(TRANSACTIONS_FILE);
        if (!tx.created_at) {
            tx.created_at = new Date().toISOString();
        }
        txs.unshift(tx);
        writeData(TRANSACTIONS_FILE, txs);
        return tx;
    },
    updateTransaction: (id, userId, updatedFields) => {
        if (isCloudUserWriteBlocked(userId)) return null;
        let txs = readData(TRANSACTIONS_FILE);
        const idx = txs.findIndex(t => t.id === id && t.user_id === userId);
        if (idx !== -1) {
            txs[idx] = {
                ...txs[idx],
                ...updatedFields,
                updated_at: new Date().toISOString()
            };
            writeData(TRANSACTIONS_FILE, txs);
            return txs[idx];
        }
        return null;
    },
    deleteTransaction: (id, userId) => {
        let txs = readData(TRANSACTIONS_FILE);
        const target = txs.find(t => t.id === id && t.user_id === userId);
        if (target) {
            txs = txs.filter(t => t.id !== id);
            writeData(TRANSACTIONS_FILE, txs);
            return target;
        }
        return null;
    },

    // USER CATEGORY MEMORY RULES (Bộ nhớ cá nhân hóa học từ thao tác của người dùng)
    saveUserCategoryRule: (userId, keyword, categoryCode) => {
        if (isCloudUserWriteBlocked(userId)) return;
        if (!keyword || keyword.trim().length < 2 || !categoryCode) return;
        const normKey = keyword.trim().toLowerCase();
        let rules = readData(RULES_FILE);
        const existingIdx = rules.findIndex(r => r.user_id === userId && r.keyword === normKey);
        if (existingIdx !== -1) {
            rules[existingIdx].category_code = categoryCode;
            rules[existingIdx].updated_at = new Date().toISOString();
        } else {
            rules.push({
                id: `rule-${Date.now()}`,
                user_id: userId,
                keyword: normKey,
                category_code: categoryCode,
                created_at: new Date().toISOString()
            });
        }
        writeData(RULES_FILE, rules);
    },
    findUserCategoryRule: (userId, text) => {
        if (!text || !text.trim()) return null;
        const normText = text.trim().toLowerCase();
        const rules = readData(RULES_FILE).filter(r => r.user_id === userId);
        // Sắp xếp các keyword dài nhất trước để so khớp chính xác nhất
        rules.sort((a, b) => b.keyword.length - a.keyword.length);
        for (const rule of rules) {
            if (normText.includes(rule.keyword)) {
                return rule;
            }
        }
        return null;
    },

    // ADMIN HELPERS
    getAllTransactions: () => readData(TRANSACTIONS_FILE),
    getAllWallets: () => readData(WALLETS_FILE)
};

module.exports = localStore;

