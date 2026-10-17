const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');
const localStore = require('../config/localStore');

// Lấy danh sách ví của người dùng
router.get('/', verifyToken, async (req, res) => {
    try {
        if (isSupabaseConfigured()) {
            try {
                const { data: wallets, error } = await supabase
                    .from('wallets')
                    .select('*')
                    .eq('user_id', req.user.id)
                    .order('created_at', { ascending: true });

                if (!error && wallets && wallets.length > 0) {
                    return res.json({ success: true, data: wallets });
                }
            } catch (_) {}
        }

        // Lấy ví từ Local Store theo đúng user_id
        let wallets = localStore.getWallets(req.user.id);
        if (!wallets || wallets.length === 0) {
            // Tự động tạo 1 ví mặc định cho người dùng này với số dư 0
            const defaultWallet = {
                id: crypto.randomUUID ? crypto.randomUUID() : `wallet-${Date.now()}`,
                user_id: req.user.id,
                name: 'Ví Tiền Mặt',
                balance: 0,
                currency: 'VND',
                color: '#4F46E5',
                is_default: true,
                created_at: new Date().toISOString()
            };
            localStore.addWallet(defaultWallet);
            wallets = [defaultWallet];
        }

        return res.json({ success: true, data: wallets });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// Tạo ví mới
router.post('/', verifyToken, async (req, res) => {
    try {
        const { name, balance, currency, color } = req.body;

        if (!name) {
            return res.status(400).json({ success: false, message: 'Tên ví là bắt buộc' });
        }

        let newWallet = null;

        if (isSupabaseConfigured()) {
            try {
                const { data: wallet, error } = await supabase
                    .from('wallets')
                    .insert([{
                        user_id: req.user.id,
                        name: name.trim(),
                        balance: parseFloat(balance) || 0,
                        currency: currency || 'VND',
                        color: color || '#4F46E5',
                        is_default: false
                    }])
                    .select()
                    .single();

                if (!error && wallet) {
                    newWallet = wallet;
                }
            } catch (_) {}
        }

        if (!newWallet) {
            newWallet = {
                id: crypto.randomUUID ? crypto.randomUUID() : `wallet-${Date.now()}`,
                user_id: req.user.id,
                name: name.trim(),
                balance: parseFloat(balance) || 0,
                currency: currency || 'VND',
                color: color || '#4F46E5',
                is_default: false,
                created_at: new Date().toISOString()
            };
            localStore.addWallet(newWallet);
        }

        return res.status(201).json({ success: true, message: 'Tạo ví mới thành công', data: newWallet });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
