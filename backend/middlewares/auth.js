const jwt = require('jsonwebtoken');
const crypto = require('crypto');
require('dotenv').config();
const { isAdminPrincipal } = require('../services/authPolicy');

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

const verifyToken = (req, res, next) => {
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
        req.user = decoded; // { id, email, role }
        next();
    } catch (err) {
        return res.status(403).json({
            success: false,
            message: 'Token không hợp lệ hoặc đã hết hạn'
        });
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

