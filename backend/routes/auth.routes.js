const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken, JWT_SECRET } = require('../middlewares/auth');
const localStore = require('../config/localStore');

// Đăng ký tài khoản
router.post('/register', async (req, res) => {
    try {
        const { email, password, full_name } = req.body;

        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Email và mật khẩu là bắt buộc' });
        }

        const normalizedEmail = email.trim().toLowerCase();
        let userCreated = null;

        // Mã hóa mật khẩu
        const salt = await bcrypt.genSalt(10);
        const password_hash = await bcrypt.hash(password, salt);

        // 1. Thử lưu vào Supabase (CSDL Cloud thực tế)
        if (isSupabaseConfigured()) {
            try {
                // Kiểm tra trùng email trên Supabase
                const { data: existingUser } = await supabase
                    .from('users')
                    .select('id')
                    .eq('email', normalizedEmail)
                    .maybeSingle();

                if (existingUser) {
                    return res.status(400).json({ success: false, message: 'Email này đã được đăng ký trên hệ thống' });
                }

                // Lưu vào bảng users
                const { data: newUser, error: userError } = await supabase
                    .from('users')
                    .insert([{ 
                        email: normalizedEmail, 
                        password_hash, 
                        full_name: full_name?.trim() || normalizedEmail.split('@')[0] 
                    }])
                    .select('id, email, full_name, created_at')
                    .single();

                if (!userError && newUser) {
                    userCreated = newUser;
                    // Tạo sẵn 1 Ví mặc định cho người dùng trên Supabase
                    try {
                        await supabase
                            .from('wallets')
                            .insert([{ user_id: newUser.id, name: 'Ví Tiền Mặt', balance: 0, is_default: true }]);
                    } catch (wErr) {
                        console.warn('[!] Cảnh báo tạo ví Supabase:', wErr.message);
                    }
                    console.log(`[+] Đã đăng ký tài khoản thành công trên Supabase Cloud: ${normalizedEmail}`);
                } else if (userError) {
                    console.warn(`[!] Supabase lỗi (${userError.code || userError.message}): Chuyển sang lưu trữ local persistent`);
                }
            } catch (sbErr) {
                console.warn(`[!] Không thể kết nối Supabase: ${sbErr.message}`);
            }
        }

        // 2. Nếu Supabase chưa cấu hình hoặc bị chặn RLS -> Lưu vào Local Store để luôn hoạt động
        if (!userCreated) {
            const existingLocal = localStore.findUserByEmail(normalizedEmail);
            if (existingLocal) {
                return res.status(400).json({ success: false, message: 'Email này đã được đăng ký' });
            }

            const localUser = {
                id: crypto.randomUUID ? crypto.randomUUID() : `user-${Date.now()}`,
                email: normalizedEmail,
                password_hash,
                full_name: full_name?.trim() || normalizedEmail.split('@')[0],
                created_at: new Date().toISOString()
            };

            localStore.addUser(localUser);
            localStore.addWallet({
                id: crypto.randomUUID ? crypto.randomUUID() : `wallet-${Date.now()}`,
                user_id: localUser.id,
                name: 'Ví Tiền Mặt',
                balance: 0,
                currency: 'VND',
                is_default: true,
                created_at: new Date().toISOString()
            });

            userCreated = {
                id: localUser.id,
                email: localUser.email,
                full_name: localUser.full_name,
                created_at: localUser.created_at
            };
            console.log(`[+] Đã đăng ký tài khoản lưu trữ Local DB: ${normalizedEmail}`);
        }

        // Ký token
        const token = jwt.sign({ id: userCreated.id, email: userCreated.email }, JWT_SECRET, { expiresIn: '7d' });

        return res.status(201).json({
            success: true,
            message: 'Đăng ký tài khoản thành công',
            data: { user: userCreated, token }
        });
    } catch (err) {
        console.error('[!] Lỗi đăng ký:', err.message);
        return res.status(500).json({ success: false, message: err.message || 'Lỗi xử lý đăng ký tài khoản' });
    }
});

// Đăng nhập
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Vui lòng nhập email và mật khẩu' });
        }

        const normalizedEmail = email.trim().toLowerCase();
        let foundUser = null;

        // 1. Tìm trong Supabase
        if (isSupabaseConfigured()) {
            try {
                const { data: user, error } = await supabase
                    .from('users')
                    .select('*')
                    .eq('email', normalizedEmail)
                    .maybeSingle();

                if (!error && user) {
                    const isMatch = await bcrypt.compare(password, user.password_hash);
                    if (isMatch) {
                        foundUser = {
                            id: user.id,
                            email: user.email,
                            full_name: user.full_name,
                            role: user.role || (normalizedEmail === 'admin@finwise.com' || normalizedEmail === 'admin@finwise.vn' ? 'admin' : 'user'),
                            status: user.status || 'active'
                        };
                    }
                }
            } catch (sbErr) {
                console.warn('[!] Lỗi tìm user trên Supabase:', sbErr.message);
            }
        }

        // 2. Tìm trong Local Store nếu chưa tìm thấy
        if (!foundUser) {
            const localUser = localStore.findUserByEmail(normalizedEmail);
            if (localUser) {
                const isMatch = await bcrypt.compare(password, localUser.password_hash);
                if (isMatch) {
                    foundUser = {
                        id: localUser.id,
                        email: localUser.email,
                        full_name: localUser.full_name,
                        role: localUser.role || (normalizedEmail === 'admin@finwise.com' || normalizedEmail === 'admin@finwise.vn' ? 'admin' : 'user'),
                        status: localUser.status || 'active'
                    };
                }
            }
        }

        // 3. Hỗ trợ tài khoản Quản trị viên (Admin) mặc định
        if (!foundUser && (normalizedEmail === 'admin@finwise.com' || normalizedEmail === 'admin@finwise.vn') && password === 'admin123456') {
            foundUser = {
                id: 'admin-00000000-0000-0000-0000-000000000001',
                email: normalizedEmail,
                full_name: 'Quản Trị Viên Hệ Thống',
                role: 'admin',
                status: 'active'
            };
        }

        // 4. Hỗ trợ tài khoản Demo mặc định
        if (!foundUser && normalizedEmail === 'demo@finwise.vn' && password === '123456') {
            foundUser = {
                id: '00000000-0000-0000-0000-000000000001',
                email: 'demo@finwise.vn',
                full_name: 'Người Dùng Demo',
                role: 'user',
                status: 'active'
            };
        }

        if (!foundUser) {
            return res.status(401).json({ success: false, message: 'Email hoặc mật khẩu không chính xác' });
        }

        // Kiểm tra xem tài khoản có bị khóa không
        if (foundUser.status === 'suspended') {
            return res.status(403).json({
                success: false,
                message: 'Tài khoản của bạn đã bị khóa bởi Quản trị viên. Vui lòng liên hệ hỗ trợ.'
            });
        }

        const token = jwt.sign(
            { id: foundUser.id, email: foundUser.email, role: foundUser.role },
            JWT_SECRET,
            { expiresIn: '7d' }
        );

        return res.json({
            success: true,
            message: 'Đăng nhập thành công' + (foundUser.role === 'admin' ? ' (Quyền Quản Trị Viên Admin)' : ''),
            data: {
                user: foundUser,
                token
            }
        });
    } catch (err) {
        console.error('[!] Lỗi đăng nhập:', err.message);
        return res.status(500).json({ success: false, message: err.message || 'Lỗi máy chủ nội bộ' });
    }
});

// Lấy thông tin cá nhân hiện tại
router.get('/me', verifyToken, async (req, res) => {
    try {
        if (isSupabaseConfigured()) {
            try {
                const { data: user, error } = await supabase
                    .from('users')
                    .select('id, email, full_name, avatar_url, role, status, created_at')
                    .eq('id', req.user.id)
                    .maybeSingle();

                if (!error && user) {
                    return res.json({ 
                        success: true, 
                        data: { 
                            user: {
                                ...user,
                                role: user.role || (user.email === 'admin@finwise.com' || user.email === 'admin@finwise.vn' ? 'admin' : 'user'),
                                status: user.status || 'active'
                            } 
                        } 
                    });
                }
            } catch (_) {}
        }

        // Fallback local
        const localUser = localStore.findUserById(req.user.id);
        if (localUser) {
            return res.json({ 
                success: true, 
                data: { 
                    user: {
                        id: localUser.id,
                        email: localUser.email,
                        full_name: localUser.full_name,
                        role: localUser.role || (localUser.email === 'admin@finwise.com' || localUser.email === 'admin@finwise.vn' ? 'admin' : 'user'),
                        status: localUser.status || 'active',
                        created_at: localUser.created_at
                    } 
                } 
            });
        }

        return res.json({ 
            success: true, 
            data: { 
                user: {
                    ...req.user,
                    role: req.user.role || (req.user.email === 'admin@finwise.com' ? 'admin' : 'user'),
                    status: 'active'
                } 
            } 
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
