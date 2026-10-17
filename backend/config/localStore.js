const fs = require('fs');
const path = require('path');

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

    // WALLETS
    getWallets: (userId) => {
        const wallets = readData(WALLETS_FILE);
        return wallets.filter(w => w.user_id === userId);
    },
    addWallet: (wallet) => {
        const wallets = readData(WALLETS_FILE);
        wallets.push(wallet);
        writeData(WALLETS_FILE, wallets);
        return wallet;
    },
    updateWalletBalance: (walletId, delta) => {
        const wallets = readData(WALLETS_FILE);
        const w = wallets.find(item => item.id === walletId);
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
        // Sắp xếp ngày mới nhất lên đầu
        userTxs.sort((a, b) => new Date(b.transaction_date) - new Date(a.transaction_date));
        return userTxs.slice(0, parseInt(limit));
    },
    addTransaction: (tx) => {
        const txs = readData(TRANSACTIONS_FILE);
        txs.unshift(tx);
        writeData(TRANSACTIONS_FILE, txs);
        return tx;
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
    }
};

module.exports = localStore;
