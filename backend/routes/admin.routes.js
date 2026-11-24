const express = require('express');
const axios = require('axios');
const bcrypt = require('bcryptjs');
const { createClient } = require('@supabase/supabase-js');
const { verifyAdmin } = require('../middlewares/auth');
const { configuredAdminEmails, configuredRootAdminEmails, isRootAdmin, isConfiguredAdminEmail, isConfiguredRootAdminEmail, isReservedAdminEmail, roleForUser } = require('../services/authPolicy');
const { isSupabaseConfigured } = require('../config/supabase');
const { getAdminPeriod } = require('../services/adminPeriod');
const { deleteCloudAccount, validateAdminDeleteTarget } = require('../services/cloudAccountDeletion');
const localStore = require('../config/localStore');
const { recoverPendingCloudAccountCleanup } = require('../services/localDeletionRecovery');

const router = express.Router();
const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8000';
function isSupabaseServiceKey(key) {
    if (!key) return false;
    if (key.startsWith('sb_secret_')) return true;
    try { return JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role === 'service_role'; }
    catch (_) { return false; }
}
const candidateServiceKey = process.env.SUPABASE_ADMIN_KEY || process.env.SUPABASE_KEY;
const serviceKey = isSupabaseServiceKey(candidateServiceKey) ? candidateServiceKey : null;
const serviceClient = isSupabaseConfigured() && serviceKey
    ? createClient(process.env.SUPABASE_URL, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
    : null;

router.use(verifyAdmin);

function failure(res, error, context) {
    console.error(`[admin] ${context}:`, error?.message || error);
    return res.status(503).json({ success: false, code: 'ADMIN_DATA_UNAVAILABLE', message: 'Dữ liệu quản trị chưa khả dụng.' });
}
function requireSupabase(res) {
    if (!isSupabaseConfigured() || !serviceClient) {
        res.status(503).json({ success: false, code: 'ADMIN_MIGRATION_REQUIRED', message: 'Dữ liệu quản trị cần private service-role key và migration quản trị.' });
        return false;
    }
    return true;
}
function rootEmail(email) { return isConfiguredRootAdminEmail(email); }
function mutationClient(res) {
    if (!serviceClient) {
        res.status(503).json({ success: false, code: 'ADMIN_MIGRATION_REQUIRED', message: 'Thao tác quản trị cần Supabase service role và migration quản trị.' });
        return null;
    }
    return serviceClient;
}
function validId(id) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(id || '')); }

router.get('/overview', async (req, res) => {
    if (req.query.period !== undefined && typeof req.query.period !== 'string') return res.status(400).json({ success:false, code:'INVALID_PERIOD', message:'Bộ lọc thời gian không hợp lệ.' });
    if (req.query.date !== undefined && typeof req.query.date !== 'string') return res.status(400).json({ success:false, code:'INVALID_DATE', message:'Ngày lọc không hợp lệ.' });
    const period = getAdminPeriod(req.query.period ?? 'all', req.query.date);
    if (period.error) return res.status(400).json({ success:false, code:period.error, message:'Bộ lọc thời gian không hợp lệ.' });
    if (!requireSupabase(res)) return;
    try {
        const periodRpcArgs = {
            p_admin_emails: Array.from(configuredAdminEmails()), p_root_emails: Array.from(configuredRootAdminEmails())
        };
        const { data: aggregate, error: aggregateError } = period.type === 'all'
            ? await serviceClient.rpc('admin_overview_data', periodRpcArgs)
            : await serviceClient.rpc('admin_overview_data_period', {
                ...periodRpcArgs, p_period_start: period.start_date, p_period_end: period.end_date
            });
        if (aggregateError) throw aggregateError;
        let ai = { status: 'unknown', url: AI_SERVICE_URL, latency_ms: null, device: null, gpu_name: null,
            phobert_loaded: null, lstm_loaded: null, ocr_loaded: null, message: 'Không thể xác định trạng thái dịch vụ AI.' };
        const started = Date.now();
        try {
            const response = await axios.get(`${AI_SERVICE_URL}/health`, { timeout: 2500 });
            ai = { status: 'online', url: AI_SERVICE_URL, latency_ms: Date.now()-started,
                device: response.data.device ?? null, gpu_name: response.data.gpu_name ?? null,
                phobert_loaded: response.data.phobert_loaded ?? null, lstm_loaded: response.data.lstm_loaded ?? null,
                ocr_loaded: response.data.ocr_loaded ?? null, message: 'AI service phản hồi health check.' };
        } catch (_) { ai = { ...ai, status: 'offline', latency_ms: Date.now()-started, message: 'AI service không phản hồi health check.' }; }
        return res.json({ success: true, data_source: 'supabase', data: {
            metrics: aggregate.metrics,
            ai_service: ai, category_distribution: aggregate.category_distribution, period
        }});
    } catch (error) { return failure(res, error, 'overview'); }
});

router.get('/users', async (req, res) => {
    if (!requireSupabase(res)) return;
    const page = Math.max(1, Math.min(100000, parseInt(req.query.page, 10) || 1));
    const perPage = Math.max(1, Math.min(100, parseInt(req.query.per_page, 10) || 20));
    const query = String(req.query.q || '').trim().slice(0, 100);
    if (req.query.role && !['admin','user'].includes(req.query.role)) return res.status(400).json({ success:false, code:'INVALID_ROLE_FILTER', message:'Bộ lọc vai trò không hợp lệ.' });
    if (req.query.status && !['active','suspended'].includes(req.query.status)) return res.status(400).json({ success:false, code:'INVALID_STATUS_FILTER', message:'Bộ lọc trạng thái không hợp lệ.' });
    const role = req.query.role || null;
    const status = req.query.status || null;
    try {
        const { data: pageData, error } = await serviceClient.rpc('admin_users_page', {
            p_page: page, p_per_page: perPage, p_query: query || null, p_role: role, p_status: status,
            p_admin_emails: Array.from(configuredAdminEmails()), p_root_emails: Array.from(configuredRootAdminEmails())
        });
        if (error) throw error;
        const rows = pageData?.users || [];
        const actorIsRoot = isRootAdmin(req.user);
        return res.json({ success: true, data_source: 'supabase', page, per_page: perPage, total: pageData?.total || 0,
            data: rows.map(u => ({ ...u,
                is_root_admin: rootEmail(u.email), can_suspend: u.id !== req.user.id && !rootEmail(u.email) && (actorIsRoot || roleForUser(u) !== 'admin'),
                can_change_role: actorIsRoot && u.id !== req.user.id && !rootEmail(u.email) && !isConfiguredAdminEmail(u.email),
                can_delete: actorIsRoot && u.id !== req.user.id && !rootEmail(u.email),
                can_edit: u.id !== req.user.id && roleForUser(u) === 'user' && !isReservedAdminEmail(u.email) })) });
    } catch (error) { return failure(res, error, 'users'); }
});

async function mutate(req, res, action, targetId, value) {
    const client = mutationClient(res); if (!client) return;
    if (!validId(targetId)) return res.status(400).json({ success:false, code:'INVALID_USER_ID', message:'Mã tài khoản không hợp lệ.' });
    const actorIsRoot = isRootAdmin(req.user);
    if (action === 'role' && !actorIsRoot) return res.status(403).json({ success:false, code:'ROOT_ADMIN_REQUIRED', message:'Chỉ Root Admin mới được thay đổi vai trò.' });
    if (targetId === req.user.id) return res.status(400).json({ success: false, code: 'SELF_PROTECTION', message: 'Không thể thay đổi tài khoản đang đăng nhập.' });
    try {
        const { data, error } = await client.rpc('admin_mutate_user', {
            p_actor_id: req.user.id, p_target_id: targetId, p_action: action, p_value: value,
            p_root_emails: Array.from(configuredRootAdminEmails()), p_admin_emails: Array.from(configuredAdminEmails()),
            p_actor_session_version: Number(req.user.auth_session_version)
        });
        if (error) {
            const msg = String(error.message || '');
            if (/admin_migration_required|function .* does not exist|schema cache/i.test(msg)) return res.status(503).json({ success:false, code:'ADMIN_MIGRATION_REQUIRED', message:'Thao tác quản trị cần migration quản trị.' });
            if (/stale_actor_session/i.test(msg)) return res.status(401).json({ success:false, code:'SESSION_REVOKED', message:'Phiên quản trị đã hết hiệu lực. Vui lòng đăng nhập lại.' });
            if (/actor_not_admin/i.test(msg)) return res.status(403).json({ success:false, code:'ADMIN_PRIVILEGE_REVOKED', message:'Quyền quản trị hiện không còn hiệu lực.' });
            if (/root_admin_required|configured_admin_protected/i.test(msg)) return res.status(403).json({ success:false, code:'ROOT_ADMIN_REQUIRED', message:'Thao tác cần quyền Root Admin.' });
            if (/target_not_found/i.test(msg)) return res.status(404).json({ success:false, code:'USER_NOT_FOUND', message:'Không tìm thấy tài khoản.' });
            if (/self_protection|root_protection/i.test(msg)) return res.status(400).json({ success:false, code:'PROTECTED_ACCOUNT', message:'Tài khoản này được bảo vệ.' });
            throw error;
        }
        if (!data?.success) return res.status(400).json({ success:false, code:data?.code || 'ADMIN_MUTATION_REJECTED', message:'Thao tác quản trị bị từ chối.' });
        return res.json({ success:true, message:'Đã cập nhật tài khoản.', data:data.user || { id:targetId, [action]:value } });
    } catch (error) { return failure(res, error, `mutation ${action}`); }
}

function mapUserRpcError(error, res) {
    const msg = String(error?.message || '');
    if (/admin_migration_required|function .* does not exist|schema cache/i.test(msg)) return res.status(503).json({ success:false, code:'ADMIN_MIGRATION_REQUIRED', message:'Thao tác quản trị cần migration quản trị.' });
    if (/stale_actor_session/i.test(msg)) return res.status(401).json({ success:false, code:'SESSION_REVOKED', message:'Phiên quản trị đã hết hiệu lực. Vui lòng đăng nhập lại.' });
    if (/actor_not_admin/i.test(msg)) return res.status(403).json({ success:false, code:'ADMIN_PRIVILEGE_REVOKED', message:'Quyền quản trị hiện không còn hiệu lực.' });
    if (/target_not_found/i.test(msg)) return res.status(404).json({ success:false, code:'USER_NOT_FOUND', message:'Không tìm thấy tài khoản.' });
    if (/self_protection|protected_account/i.test(msg)) return res.status(400).json({ success:false, code:'PROTECTED_ACCOUNT', message:'Tài khoản này được bảo vệ.' });
    if (error?.code === '23505' || /email_already_exists|unique_violation/i.test(msg)) return res.status(409).json({ success:false, code:'EMAIL_ALREADY_EXISTS', message:'Email này đã được đăng ký.' });
    if (/reserved_email/i.test(msg)) return res.status(400).json({ success:false, code:'RESERVED_EMAIL', message:'Email này được dành riêng cho tài khoản quản trị.' });
    if (/invalid_profile/i.test(msg)) return res.status(400).json({ success:false, code:'INVALID_PROFILE', message:'Thông tin tài khoản không hợp lệ.' });
    return null;
}

function validProfile(fullName, email) {
    const name = typeof fullName === 'string' ? fullName.trim() : '';
    const normalizedEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
    return name.length > 0 && name.length <= 150 && !/[\r\n\0]/.test(name) &&
        normalizedEmail.length <= 255 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)
        ? { full_name: name, email: normalizedEmail } : null;
}
function validNewPassword(password) {
    return typeof password === 'string' && [...password].length >= 10 && Buffer.byteLength(password, 'utf8') <= 72;
}

router.post('/users', async (req, res) => {
    const client = mutationClient(res); if (!client) return;
    const profile = validProfile(req.body?.full_name, req.body?.email);
    const password = req.body?.password;
    if (!profile || !validNewPassword(password)) {
        return res.status(400).json({ success:false, code:'INVALID_USER_INPUT', message:'Họ tên, email hoặc mật khẩu không hợp lệ.' });
    }
    if (isReservedAdminEmail(profile.email) || profile.email === 'demo@finwise.vn') return res.status(400).json({ success:false, code:'RESERVED_EMAIL', message:'Email này được dành riêng cho tài khoản quản trị.' });
    try {
        const passwordHash = await bcrypt.hash(password, 10);
        const { data, error } = await client.rpc('admin_create_user', {
            p_actor_id:req.user.id, p_email:profile.email, p_full_name:profile.full_name, p_password_hash:passwordHash,
            p_admin_emails:Array.from(configuredAdminEmails()), p_root_emails:Array.from(configuredRootAdminEmails()),
            p_actor_session_version:Number(req.user.auth_session_version)
        });
        if (error) { const mapped = mapUserRpcError(error,res); if (mapped) return mapped; throw error; }
        if (!data?.success) return res.status(400).json({ success:false, code:data?.code || 'ADMIN_MUTATION_REJECTED', message:'Không thể tạo tài khoản.' });
        return res.status(201).json({ success:true, data:data.user });
    } catch (error) { return failure(res,error,'create user'); }
});

router.put('/users/:id/profile', async (req, res) => {
    const client = mutationClient(res); if (!client) return;
    if (!validId(req.params.id)) return res.status(400).json({ success:false, code:'INVALID_USER_ID', message:'Mã tài khoản không hợp lệ.' });
    const profile = validProfile(req.body?.full_name, req.body?.email);
    if (!profile) return res.status(400).json({ success:false, code:'INVALID_USER_INPUT', message:'Họ tên hoặc email không hợp lệ.' });
    if (req.params.id === req.user.id) return res.status(400).json({ success:false, code:'SELF_PROTECTION', message:'Không thể thay đổi tài khoản đang đăng nhập.' });
    if (isReservedAdminEmail(profile.email) || profile.email === 'demo@finwise.vn') return res.status(400).json({ success:false, code:'RESERVED_EMAIL', message:'Email này được dành riêng cho tài khoản quản trị.' });
    try {
        const { data, error } = await client.rpc('admin_update_user_profile', {
            p_actor_id:req.user.id, p_target_id:req.params.id, p_email:profile.email, p_full_name:profile.full_name,
            p_admin_emails:Array.from(configuredAdminEmails()), p_root_emails:Array.from(configuredRootAdminEmails()),
            p_actor_session_version:Number(req.user.auth_session_version)
        });
        if (error) { const mapped = mapUserRpcError(error,res); if (mapped) return mapped; throw error; }
        if (!data?.success) return res.status(400).json({ success:false, code:data?.code || 'ADMIN_MUTATION_REJECTED', message:'Không thể cập nhật tài khoản.' });
        return res.json({ success:true, data:data.user });
    } catch (error) { return failure(res,error,'update user profile'); }
});

router.put('/users/:id/status', async (req,res) => {
    const status = req.body?.status;
    if (!['active','suspended'].includes(status)) return res.status(400).json({ success:false, code:'INVALID_STATUS', message:'Trạng thái không hợp lệ.' });
    return mutate(req,res,'status',req.params.id,status);
});
router.put('/users/:id/role', async (req,res) => {
    const role = req.body?.role;
    if (!['user','admin'].includes(role)) return res.status(400).json({ success:false, code:'INVALID_ROLE', message:'Vai trò không hợp lệ.' });
    return mutate(req,res,'role',req.params.id,role);
});
router.delete('/users/:id', async (req,res) => {
    const client = mutationClient(res); if (!client) return;
    if (!validId(req.params.id)) return res.status(400).json({ success:false, code:'INVALID_USER_ID', message:'Mã tài khoản không hợp lệ.' });
    const targetId = req.params.id.toLowerCase();
    if (!isRootAdmin(req.user)) return res.status(403).json({ success:false, code:'ROOT_ADMIN_REQUIRED', message:'Chỉ Root Admin mới được xóa tài khoản.' });
    if (targetId === String(req.user.id).toLowerCase()) return res.status(400).json({ success:false, code:'SELF_PROTECTION', message:'Không thể xóa tài khoản đang đăng nhập.' });
    const confirmEmail = typeof req.body?.confirm_email === 'string' ? req.body.confirm_email.trim().toLowerCase() : '';
    if (!confirmEmail) return res.status(400).json({ success:false, code:'CONFIRMATION_REQUIRED', message:'Cần xác nhận email tài khoản để xóa.' });
    try {
        // Resolve the cloud identity authoritatively before writing a local
        // retry marker. A local-only/fake ID or malformed legacy identity must
        // never schedule cleanup of matching local spillover.
        const { data: target, error: lookupError } = await client.from('users')
            .select('id,email').eq('id', targetId).maybeSingle();
        if (lookupError) return failure(res, lookupError, 'lookup delete target');
        if (!target || String(target.id || '').toLowerCase() !== targetId) {
            return res.status(404).json({ success:false, code:'USER_NOT_FOUND', message:'Không tìm thấy tài khoản.' });
        }
        const targetEmail = typeof target.email === 'string' ? target.email.trim().toLowerCase() : '';
        const validation = validateAdminDeleteTarget({ requestedId: targetId, foundId: target.id, email: target.email,
            confirmEmail, isRootEmail: isConfiguredRootAdminEmail });
        if (validation === 'invalid_email') return res.status(400).json({ success:false, code:'ADMIN_DELETE_REJECTED', message:'Email tài khoản không hợp lệ.' });
        if (validation) {
            return res.status(400).json({ success:false, code:'ADMIN_DELETE_REJECTED', message:'Xác nhận không hợp lệ hoặc tài khoản được bảo vệ.' });
        }

        const deletion = await deleteCloudAccount({
            userId: targetId,
            email: targetEmail,
            localStore,
            recoverPending: recoverPendingCloudAccountCleanup,
            rpc: () => client.rpc('admin_delete_user', { p_actor_id:req.user.id,
                p_target_id:targetId, p_confirm_email:confirmEmail, p_root_emails:Array.from(configuredRootAdminEmails()),
                p_actor_session_version:Number(req.user.auth_session_version) })
        });
        if (deletion.reason === 'in_flight') {
            return res.status(409).json({ success:false, code:'ADMIN_DELETE_IN_PROGRESS', message:'Đang xử lý yêu cầu xóa tài khoản này.' });
        }
        if (!deletion.ok) {
            if (deletion.reason === 'invalid_target') return res.status(400).json({ success:false, code:'ADMIN_DELETE_REJECTED', message:'Email tài khoản không hợp lệ.' });
            const { error, data } = deletion;
            const errorMessage = String(error?.message || '');
            if (/admin_migration_required|function .* does not exist|schema cache/i.test(errorMessage)) return res.status(503).json({ success:false, code:'ADMIN_MIGRATION_REQUIRED', message:'Thao tác quản trị cần migration quản trị.' });
            if (/stale_actor_session/i.test(errorMessage)) return res.status(401).json({ success:false, code:'SESSION_REVOKED', message:'Phiên quản trị đã hết hiệu lực. Vui lòng đăng nhập lại.' });
            if (/root_admin_required/i.test(errorMessage)) return res.status(403).json({ success:false, code:'ROOT_ADMIN_REQUIRED', message:'Chỉ Root Admin mới được xóa tài khoản.' });
            if (/target_not_found/i.test(errorMessage)) return res.status(404).json({ success:false, code:'USER_NOT_FOUND', message:'Không tìm thấy tài khoản.' });
            if (/confirmation_mismatch|root_protection|self_protection/i.test(errorMessage)) return res.status(400).json({ success:false, code:'ADMIN_DELETE_REJECTED', message:'Xác nhận không hợp lệ hoặc tài khoản được bảo vệ.' });
            if (data && data.success !== true) return res.status(400).json({ success:false, code:data.code || 'ADMIN_DELETE_REJECTED', message:'Không thể xóa tài khoản.' });
            if (!error) return res.status(503).json({ success:false, code:'ADMIN_DATA_UNAVAILABLE', message:'Dữ liệu quản trị chưa khả dụng.' });
            throw error;
        }
        if (deletion.cleanupPending) return res.status(200).json({ success:true, data:{ local_cleanup_pending:true }, message:'Đã xóa tài khoản trên đám mây; dữ liệu cục bộ đang chờ dọn dẹp.' });
        return res.json({ success:true, message:'Đã xóa tài khoản và dữ liệu liên quan.' });
    } catch (error) { return failure(res,error,'delete user'); }
});

module.exports = router;
module.exports.validProfile = validProfile;
module.exports.validNewPassword = validNewPassword;
module.exports.mapUserRpcError = mapUserRpcError;
