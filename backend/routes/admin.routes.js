const express = require('express');
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');
const { verifyAdmin } = require('../middlewares/auth');
const { configuredAdminEmails, configuredRootAdminEmails, isRootAdmin, isConfiguredAdminEmail, isConfiguredRootAdminEmail, roleForUser } = require('../services/authPolicy');
const { isSupabaseConfigured } = require('../config/supabase');

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
    if (!requireSupabase(res)) return;
    try {
        const { data: aggregate, error: aggregateError } = await serviceClient.rpc('admin_overview_data', {
            p_admin_emails: Array.from(configuredAdminEmails()), p_root_emails: Array.from(configuredRootAdminEmails())
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
            ai_service: ai, category_distribution: aggregate.category_distribution
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
                can_delete: actorIsRoot && u.id !== req.user.id && !rootEmail(u.email) })) });
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
    if (!isRootAdmin(req.user)) return res.status(403).json({ success:false, code:'ROOT_ADMIN_REQUIRED', message:'Chỉ Root Admin mới được xóa tài khoản.' });
    if (req.params.id === req.user.id) return res.status(400).json({ success:false, code:'SELF_PROTECTION', message:'Không thể xóa tài khoản đang đăng nhập.' });
    const confirmEmail = String(req.body?.confirm_email || '').trim().toLowerCase();
    if (!confirmEmail) return res.status(400).json({ success:false, code:'CONFIRMATION_REQUIRED', message:'Cần xác nhận email tài khoản để xóa.' });
    try {
        const { data, error } = await client.rpc('admin_delete_user', { p_actor_id:req.user.id,
            p_target_id:req.params.id, p_confirm_email:confirmEmail, p_root_emails:Array.from(configuredRootAdminEmails()),
            p_actor_session_version:Number(req.user.auth_session_version) });
        if (error) {
            if (/admin_migration_required|function .* does not exist|schema cache/i.test(String(error.message))) return res.status(503).json({ success:false, code:'ADMIN_MIGRATION_REQUIRED', message:'Thao tác quản trị cần migration quản trị.' });
            if (/stale_actor_session/i.test(String(error.message))) return res.status(401).json({ success:false, code:'SESSION_REVOKED', message:'Phiên quản trị đã hết hiệu lực. Vui lòng đăng nhập lại.' });
            if (/root_admin_required/i.test(String(error.message))) return res.status(403).json({ success:false, code:'ROOT_ADMIN_REQUIRED', message:'Chỉ Root Admin mới được xóa tài khoản.' });
            if (/target_not_found/i.test(String(error.message))) return res.status(404).json({ success:false, code:'USER_NOT_FOUND', message:'Không tìm thấy tài khoản.' });
            if (/confirmation_mismatch|root_protection|self_protection/i.test(String(error.message))) return res.status(400).json({ success:false, code:'ADMIN_DELETE_REJECTED', message:'Xác nhận không hợp lệ hoặc tài khoản được bảo vệ.' });
            throw error;
        }
        if (!data?.success) return res.status(400).json({ success:false, code:data?.code || 'ADMIN_DELETE_REJECTED', message:'Không thể xóa tài khoản.' });
        return res.json({ success:true, message:'Đã xóa tài khoản và dữ liệu liên quan.' });
    } catch (error) { return failure(res,error,'delete user'); }
});

module.exports = router;
