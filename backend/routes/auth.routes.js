const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken, JWT_SECRET } = require('../middlewares/auth');

// Đăng ký tài khoản
router.post('/register', async (req, res) => {
    try {
        const { email, password, full_name } = req.body;

        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Email và mật khẩu là bắt buộc' });
        }

        if (!isSupabaseConfigured()) {
            return res.status(503).json({
                success: false,
                message: 'Chưa cấu hình Supabase URL & Key trong file .env. Vui lòng cập nhật .env để lưu tài khoản thật.'
            });
        }

        // Kiểm tra trùng email
        const { data: existingUser } = await supabase
            .from('users')
            .select('id')
            .eq('email', email)
            .single();

        if (existingUser) {
            return res.status(400).json({ success: false, message: 'Email này đã được đăng ký' });
        }

        // Mã hóa mật khẩu
        const salt = await bcrypt.genSalt(10);
        const password_hash = await bcrypt.hash(password, salt);

        // Lưu vào bảng users
        const { data: newUser, error: userError } = await supabase
            .from('users')
            .insert([{ email, password_hash, full_name: full_name || email.split('@')[0] }])
            .select('id, email, full_name, created_at')
            .single();

        if (userError) throw userError;

        // Tạo sẵn 1 Ví mặc định cho người dùng
        await supabase
            .from('wallets')
            .insert([{ user_id: newUser.id, name: 'Ví Tiền Mặt', balance: 0, is_default: true }]);

        // Ký token
        const token = jwt.sign({ id: newUser.id, email: newUser.email }, JWT_SECRET, { expiresIn: '7d' });

        return res.status(201).json({
            success: true,
            message: 'Đăng ký tài khoản thành công',
            data: { user: newUser, token }
        });
    } catch (err) {
        console.error('[!] Lỗi đăng ký:', err.message);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// Đăng nhập
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Vui lòng nhập email và mật khẩu' });
        }

        // Nếu chưa cấu hình Supabase -> hỗ trợ Demo Login để test ngay
        if (!isSupabaseConfigured()) {
            if (email === 'demo@finwise.vn' && password === '123456') {
                const demoUser = { id: '00000000-0000-0000-0000-000000000001', email: 'demo@finwise.vn', full_name: 'Người Dùng Demo' };
                const token = jwt.sign(demoUser, JWT_SECRET, { expiresIn: '7d' });
                return res.json({
                    success: true,
                    message: 'Đăng nhập chế độ Demo thành công',
                    data: { user: demoUser, token }
                });
            }
            return res.status(503).json({
                success: false,
                message: 'Chưa cấu hình Supabase trong .env. Bạn có thể thử tài khoản demo: demo@finwise.vn / 123456'
            });
        }

        // Tìm người dùng trong Supabase
        const { data: user, error } = await supabase
            .from('users')
            .select('*')
            .eq('email', email)
            .single();

        if (error || !user) {
            return res.status(401).json({ success: false, message: 'Email hoặc mật khẩu không chính xác' });
        }

        const isMatch = await bcrypt.compare(password, user.password_hash);
        if (!isMatch) {
            return res.status(401).json({ success: false, message: 'Email hoặc mật khẩu không chính xác' });
        }

        const token = jwt.sign({ id: user.id, email: user.email }, JWT_SECRET, { expiresIn: '7d' });

        return res.json({
            success: true,
            message: 'Đăng nhập thành công',
            data: {
                user: { id: user.id, email: user.email, full_name: user.full_name },
                token
            }
        });
    } catch (err) {
        console.error('[!] Lỗi đăng nhập:', err.message);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// Lấy thông tin cá nhân hiện tại
router.get('/me', verifyToken, async (req, res) => {
    try {
        if (!isSupabaseConfigured()) {
            return res.json({ success: true, data: { user: req.user } });
        }

        const { data: user, error } = await supabase
            .from('users')
            .select('id, email, full_name, avatar_url, created_at')
            .eq('id', req.user.id)
            .single();

        if (error) throw error;

        return res.json({ success: true, data: { user } });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
