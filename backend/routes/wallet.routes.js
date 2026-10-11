const express = require('express');
const router = express.Router();
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');

// Lấy danh sách ví của người dùng
router.get('/', verifyToken, async (req, res) => {
    try {
        if (!isSupabaseConfigured()) {
            return res.json({
                success: true,
                data: [
                    { id: 'wallet-01', name: 'Ví Tiền Mặt Demo', balance: 5000000, currency: 'VND', is_default: true }
                ]
            });
        }

        const { data: wallets, error } = await supabase
            .from('wallets')
            .select('*')
            .eq('user_id', req.user.id)
            .order('created_at', { ascending: true });

        if (error) throw error;

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

        if (!isSupabaseConfigured()) {
            return res.json({
                success: true,
                message: 'Tạo ví mô phỏng thành công',
                data: { id: 'wallet-new', name, balance: balance || 0, currency: currency || 'VND' }
            });
        }

        const { data: wallet, error } = await supabase
            .from('wallets')
            .insert([{
                user_id: req.user.id,
                name,
                balance: balance || 0,
                currency: currency || 'VND',
                color: color || '#4F46E5',
                is_default: false
            }])
            .select()
            .single();

        if (error) throw error;

        return res.status(201).json({ success: true, message: 'Tạo ví mới thành công', data: wallet });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
