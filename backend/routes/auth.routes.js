const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { supabase, supabaseService, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken, JWT_SECRET } = require('../middlewares/auth');
const localStore = require('../config/localStore');
const { hasAdminAuthSchema, isLegacyDefaultAdminPassword, isReservedAdminEmail, roleForUser, configuredAdminEmails, configuredRootAdminEmails } = require('../services/authPolicy');
const { issueDeletionChallenge, validateDeletionChallenge, MIN_WAIT_MS } = require('../services/accountDeletionChallenge');
const { recoverPendingCloudAccountCleanup } = require('../services/localDeletionRecovery');
const { emailHash } = require('../services/localAccountCleanup');

// Đăng ký tài khoản
router.post('/register', async (req, res) => {
    try {
        const { email, password, full_name } = req.body;

        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Email và mật khẩu là bắt buộc' });
        }

        const normalizedEmail = email.trim().toLowerCase();
        if (isReservedAdminEmail(normalizedEmail)) {
            return res.status(400).json({ success: false, message: 'Email này được dành riêng cho tài khoản quản trị' });
        }
        let userCreated = null;
        let createdInLocalStore = false;

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
            createdInLocalStore = true;
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
        const token = jwt.sign({
            id: userCreated.id,
            email: userCreated.email,
            sv: 0,
            ...(createdInLocalStore ? { auth_source: 'local' } : {})
        }, JWT_SECRET, { expiresIn: '7d' });

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
        if (isReservedAdminEmail(normalizedEmail) && isLegacyDefaultAdminPassword(password)) {
            return res.status(401).json({ success: false, message: 'Email hoặc mật khẩu không chính xác' });
        }
        let foundUser = null;
        let authoritativeCloudUserFound = false;

        // 1. Tìm trong Supabase
        if (isSupabaseConfigured()) {
            try {
                const { data: user, error } = await supabase
                    .from('users')
                    .select('*')
                    .eq('email', normalizedEmail)
                    .maybeSingle();

                if (error) {
                    console.error('[!] Không thể xác minh tài khoản trên Supabase:', error.message);
                    return res.status(503).json({ success: false, message: 'Không thể xác minh tài khoản hiện tại' });
                }
                if (user) {
                    authoritativeCloudUserFound = true;
                    const isMatch = await bcrypt.compare(password, user.password_hash);
                    const effectiveRole = hasAdminAuthSchema(user) ? roleForUser(user) : 'user';
                    if (isMatch && !(effectiveRole === 'admin' && isLegacyDefaultAdminPassword(password))) {
                        foundUser = {
                            id: user.id,
                            email: user.email,
                            full_name: user.full_name,
                            role: effectiveRole,
                            status: user.status || 'active',
                            auth_session_version: Number.isInteger(user.auth_session_version) ? user.auth_session_version : 0
                        };
                    }
                }
            } catch (sbErr) {
                console.error('[!] Không thể xác minh tài khoản trên Supabase:', sbErr.message);
                return res.status(503).json({ success: false, message: 'Không thể xác minh tài khoản hiện tại' });
            }
        }

        // Local-only rows remain usable when cloud lookup completes successfully but
        // has no matching row; a cloud error above remains fail-closed. Such users
        // are always regular users whenever cloud storage is configured.
        if (!foundUser && !authoritativeCloudUserFound) {
            const localUser = localStore.findUserByEmail(normalizedEmail);
            if (localUser) {
                const isMatch = await bcrypt.compare(password, localUser.password_hash);
                const effectiveRole = isSupabaseConfigured()
                    ? 'user'
                    : (hasAdminAuthSchema(localUser) ? roleForUser(localUser) : 'user');
                if (isMatch && !(effectiveRole === 'admin' && isLegacyDefaultAdminPassword(password))) {
                    foundUser = {
                        id: localUser.id,
                        email: localUser.email,
                        full_name: localUser.full_name,
                        role: effectiveRole,
                        status: localUser.status || 'active',
                        auth_session_version: Number.isInteger(localUser.auth_session_version) ? localUser.auth_session_version : 0,
                        auth_source: 'local'
                    };
                }
            }
        }

        // Hỗ trợ tài khoản Demo mặc định
        if (!foundUser && normalizedEmail === 'demo@finwise.vn' && password === '123456') {
            foundUser = {
                id: '00000000-0000-0000-0000-000000000001',
                email: 'demo@finwise.vn',
                full_name: 'Người Dùng Demo',
                role: 'user',
                status: 'active',
                auth_session_version: 0
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
            {
                id: foundUser.id,
                email: foundUser.email,
                role: foundUser.role,
                sv: foundUser.auth_session_version,
                ...(foundUser.auth_source === 'local' ? { auth_source: 'local' } : {}),
                ...(foundUser.role === 'admin' ? { admin_auth_version: 3 } : {})
            },
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
                    .select('*')
                    .eq('id', req.user.id)
                    .maybeSingle();

                if (!error && user) {
                    return res.json({ 
                        success: true, 
                        data: { 
                            user: {
                                id: user.id,
                                email: user.email,
                                full_name: user.full_name,
                                avatar_url: user.avatar_url,
                                role: roleForUser(user),
                                status: user.status || 'active',
                                created_at: user.created_at
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
                        role: roleForUser(localUser),
                        status: localUser.status || 'active',
                        created_at: localUser.created_at
                    } 
                } 
            });
        }

        const { _authSource, ...publicUser } = req.user;
        return res.json({ 
            success: true, 
            data: { 
                user: {
                    ...publicUser,
                    role: roleForUser(req.user),
                    status: 'active'
                } 
            } 
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// Begin the delayed, session-bound account deletion flow.
router.post('/me/delete-intent', verifyToken, (req, res) => {
    if (req.user._authSource === 'synthetic-demo' || req.user.id === '00000000-0000-0000-0000-000000000001' ||
        String(req.user.email).toLowerCase() === 'demo@finwise.vn' || req.user.role !== 'user' || isReservedAdminEmail(req.user.email)) {
        return res.status(403).json({ success: false, message: 'Tài khoản này không thể tự xóa.' });
    }
    const challenge = issueDeletionChallenge({
        userId: req.user.id,
        sessionVersion: req.user.auth_session_version,
        req
    });
    return res.status(200).json({ success: true, data: { challenge, wait_seconds: MIN_WAIT_MS / 1000 } });
});

// Delete only the identity resolved by verifyToken. The client cannot supply a
// target ID; cloud deletion and its protected-account checks run in one RPC.
router.delete('/me', verifyToken, async (req, res) => {
    const challenge = req.body?.challenge;
    if (!validateDeletionChallenge({
        challenge,
        userId: req.user.id,
        sessionVersion: req.user.auth_session_version,
        req
    })) {
        return res.status(400).json({ success: false, message: 'Yêu cầu xác nhận xóa không hợp lệ, đã hết hạn hoặc chưa đủ thời gian.' });
    }
    if (req.user._authSource === 'synthetic-demo' || req.user.id === '00000000-0000-0000-0000-000000000001' ||
        String(req.user.email).toLowerCase() === 'demo@finwise.vn' || req.user.role !== 'user' || isReservedAdminEmail(req.user.email)) {
        return res.status(403).json({ success: false, message: 'Tài khoản này không thể tự xóa.' });
    }

    try {
        if (req.user._authSource === 'local') {
            localStore.blockCloudUserWrites(req.user.id);
            let result;
            try {
                result = localStore.deleteUserData(req.user.id, { requireUser: true });
            } catch (error) {
                localStore.clearCloudUserWriteGuard(req.user.id);
                throw error;
            }
            if (!result.found) localStore.clearCloudUserWriteGuard(req.user.id);
            if (!result.found) return res.status(404).json({ success: false, message: 'Tài khoản không còn tồn tại.' });
        } else if (req.user._authSource === 'cloud' && isSupabaseConfigured() && supabaseService) {
            // Persist a recovery marker before the destructive RPC. If the
            // process exits after the cloud commit, startup/periodic recovery
            // verifies that the cloud user is gone before cleaning local spillover.
            if (localStore.isCloudAccountDeletionInFlight(req.user.id)) {
                return res.status(409).json({ success: false, message: 'Đang xử lý yêu cầu xóa tài khoản này.' });
            }
            localStore.queueCloudAccountCleanup(req.user.id, req.user.email);
            localStore.beginCloudAccountDeletion(req.user.id);
            let rpcResult;
            try {
                rpcResult = await supabaseService.rpc('self_delete_account', {
                    p_user_id: req.user.id,
                    p_session_version: req.user.auth_session_version,
                    p_admin_emails: Array.from(configuredAdminEmails()),
                    p_root_emails: Array.from(configuredRootAdminEmails())
                });
            } catch (_) {
                localStore.endCloudAccountDeletion(req.user.id);
                await recoverPendingCloudAccountCleanup();
                console.error('[!] Account deletion RPC failed: database_error');
                return res.status(503).json({ success: false, message: 'Không thể hoàn tất xóa tài khoản. Vui lòng thử lại sau.' });
            }
            const { data, error } = rpcResult;
            localStore.endCloudAccountDeletion(req.user.id);
            if (error || data?.success !== true) {
                // Keep the durable marker until a privileged lookup confirms
                // whether the cloud commit happened despite a transport error.
                await recoverPendingCloudAccountCleanup();
                // Do not emit challenge, bearer, or personal record data to logs.
                console.error('[!] Account deletion RPC failed:', error?.code || 'database_error');
                return res.status(503).json({ success: false, message: 'Không thể hoàn tất xóa tài khoản. Vui lòng thử lại sau.' });
            }

            // Cloud identity may have local spillover from legacy offline writes
            // and personalized category learning. Clean only rows with this ID.
            try {
                localStore.deleteUserData(req.user.id, {
                    requireUser: false,
                    removeUser: true,
                    expectedEmailHash: emailHash(req.user.email)
                });
                // On an ID collision with a different local email, the cleanup
                // helper intentionally leaves that other identity untouched.
                localStore.completeCloudAccountCleanup(req.user.id);
            } catch (_) {
                // Cloud deletion is committed; the durable queue retries locally.
                return res.status(200).json({ success: true, data: { local_cleanup_pending: true } });
            }
        } else {
            return res.status(503).json({ success: false, message: 'Không thể truy cập kho dữ liệu tài khoản.' });
        }
        return res.status(200).json({ success: true });
    } catch (_) {
        // Local file parse/write failures fail closed; the account record remains
        // until dependent data cleanup has completed.
        return res.status(503).json({ success: false, message: 'Không thể hoàn tất xóa tài khoản. Vui lòng thử lại sau.' });
    }
});

module.exports = router;
