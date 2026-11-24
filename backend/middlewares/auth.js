const jwt = require('jsonwebtoken');
const crypto = require('crypto');
require('dotenv').config();
const { hasAdminAuthSchema, isAdminPrincipal, isCurrentSession, roleForUser, SYNTHETIC_ADMIN_ID } = require('../services/authPolicy');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const localStore = require('../config/localStore');

const configuredJwtSecret = process.env.JWT_SECRET;
const LEGACY_DEFAULT_JWT_SECRET_SHA256 = '590c8bdbeefd0cac94ca8e1fc9fe003d55200360d58dd23a28bb82745f9e4945';
const configuredSecretHash = configuredJwtSecret
    ? crypto.createHash('sha256').update(configuredJwtSecret).digest()
    : null;
const legacySecretHash = Buffer.from(LEGACY_DEFAULT_JWT_SECRET_SHA256, 'hex');
const hasDeprecatedSecret = configuredSecretHash && crypto.timingSafeEqual(configuredSecretHash, legacySecretHash);
const usesEphemeralSecret = !configuredJwtSecret || hasDeprecatedSecret;
const JWT_SECRET = usesEphemeralSecret ? crypto.randomBytes(32).toString('hex') : configuredJwtSecret;

if (usesEphemeralSecret) {
    console.warn('[!] JWT_SECRET is unset or uses a deprecated default. A temporary process secret is active; set a unique JWT_SECRET. Existing sessions may need to sign in again.');
}

async function loadCurrentUser(decoded) {
    if (isSupabaseConfigured()) {
        const result = await supabase
            .from('users')
            .select('id, email, full_name, role, status, auth_session_version')
            .eq('id', decoded.id)
            .maybeSingle();
        if (!result.error) {
            if (result.data) return result.data;
            if (decoded.auth_source === 'local') {
                const localUser = localStore.findUserById(decoded.id);
                if (localUser && localUser.email === decoded.email) return { ...localUser, _localAuthority: true };
            }
            return null;
        }
        // Older deployments may not have completed the admin migration. Preserve
        // normal identities only for a known missing-column error; no admin state
        // is inferred from this fallback row.
        if (result.error.code === '42703' || result.error.code === 'PGRST204') {
            const base = await supabase.from('users').select('id, email, full_name').eq('id', decoded.id).maybeSingle();
            if (base.error) throw base.error;
            if (base.data) return { ...base.data, _adminSchemaUnavailable: true };
            if (decoded.auth_source === 'local') {
                const localUser = localStore.findUserById(decoded.id);
                if (localUser && localUser.email === decoded.email) return { ...localUser, _localAuthority: true };
            }
            return null;
        }
        throw result.error;
    }
    return localStore.findUserById(decoded.id) || null;
}

const verifyToken = async (req, res, next) => {
    const authHeader = req.headers['authorization'];
    if (!authHeader) {
        return res.status(401).json({
            success: false,
            message: 'Thiếu Token xác thực (Authorization header)'
        });
    }

    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        const currentUser = await loadCurrentUser(decoded);

        // The built-in demo identity is intentionally synthetic and has no persisted row.
        if (!currentUser && decoded.id === SYNTHETIC_ADMIN_ID) {
            return res.status(401).json({ success: false, message: 'Phiên đăng nhập không còn hợp lệ' });
        }
        if (!currentUser && decoded.id === '00000000-0000-0000-0000-000000000001' && decoded.email === 'demo@finwise.vn') {
            req.user = { id: decoded.id, email: decoded.email, role: 'user', status: 'active', auth_session_version: 0, _authSource: 'synthetic-demo' };
            return next();
        }
        if (!currentUser) {
            return res.status(401).json({ success: false, message: 'Tài khoản không còn tồn tại' });
        }

        const currentVersion = Number.isInteger(currentUser.auth_session_version) ? currentUser.auth_session_version : 0;
        if (!isCurrentSession(decoded.sv, currentVersion)) {
            return res.status(401).json({ success: false, message: 'Phiên đăng nhập đã bị thu hồi. Vui lòng đăng nhập lại.' });
        }
        if (currentUser.status && currentUser.status !== 'active') {
            return res.status(403).json({ success: false, message: 'Tài khoản của bạn đã bị khóa bởi Quản trị viên. Vui lòng liên hệ hỗ trợ.' });
        }

        const adminSchemaReady = !currentUser._adminSchemaUnavailable &&
            !(isSupabaseConfigured() && currentUser._localAuthority) && hasAdminAuthSchema(currentUser);
        req.user = {
            id: currentUser.id,
            email: currentUser.email,
            full_name: currentUser.full_name,
            role: adminSchemaReady ? roleForUser(currentUser) : 'user',
            status: currentUser.status || 'active',
            auth_session_version: currentVersion,
            admin_auth_version: decoded.admin_auth_version,
            // This is derived from the authoritative lookup above. Never infer
            // storage authority from a client-controlled request field.
            _authSource: currentUser._localAuthority ? 'local' : (isSupabaseConfigured() ? 'cloud' : 'local')
        };
        return next();
    } catch (err) {
        if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError' || err.name === 'NotBeforeError') {
            return res.status(403).json({ success: false, message: 'Token không hợp lệ hoặc đã hết hạn' });
        }
        console.error('[!] Không thể xác thực trạng thái tài khoản:', err.message);
        return res.status(503).json({ success: false, message: 'Không thể xác minh tài khoản hiện tại' });
    }
};

const verifyAdmin = (req, res, next) => {
    verifyToken(req, res, () => {
        if (isAdminPrincipal(req.user)) {
            return next();
        }
        return res.status(403).json({
            success: false,
            message: 'Quyền truy cập bị từ chối: Yêu cầu quyền Quản trị viên (Admin)'
        });
    });
};

module.exports = {
    verifyToken,
    verifyAdmin,
    JWT_SECRET
};

