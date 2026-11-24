const crypto = require('crypto');

const RESERVED_ADMIN_EMAILS = new Set([
    'admin@finwise.com',
    'admin@finwise.vn'
]);
const SYNTHETIC_ADMIN_ID = 'admin-00000000-0000-0000-0000-000000000001';
const LEGACY_DEFAULT_ADMIN_PASSWORD_SHA256 = 'ac0e7d037817094e9e0b4441f9bae3209d67b02fa484917065f71b16109a1a78';

function normalizeEmail(email) {
    return String(email || '').trim().toLowerCase();
}

function configuredAdminEmails() {
    return new Set(
        (process.env.FINWISE_ADMIN_EMAILS || '')
            .split(',')
            .map(normalizeEmail)
            .filter(Boolean)
    );
}

function configuredRootAdminEmails() {
    return new Set(
        (process.env.FINWISE_ROOT_ADMIN_EMAILS || '')
            .split(',')
            .map(normalizeEmail)
            .filter(Boolean)
    );
}

function isConfiguredAdminEmail(email) {
    return configuredAdminEmails().has(normalizeEmail(email));
}

function isConfiguredRootAdminEmail(email) {
    return configuredRootAdminEmails().has(normalizeEmail(email));
}

function isRootAdmin(user) {
    return Boolean(user && user.id !== SYNTHETIC_ADMIN_ID && isConfiguredRootAdminEmail(user.email));
}

function isReservedAdminEmail(email) {
    const normalized = normalizeEmail(email);
    return RESERVED_ADMIN_EMAILS.has(normalized) || isConfiguredAdminEmail(normalized) || isConfiguredRootAdminEmail(normalized);
}

function isLegacyDefaultAdminPassword(password) {
    const actualHash = crypto.createHash('sha256').update(String(password || '')).digest();
    const expectedHash = Buffer.from(LEGACY_DEFAULT_ADMIN_PASSWORD_SHA256, 'hex');
    return crypto.timingSafeEqual(actualHash, expectedHash);
}

function roleForUser(user) {
    if (!user) return 'user';
    return user.role === 'admin' || isConfiguredAdminEmail(user.email) || isConfiguredRootAdminEmail(user.email) ? 'admin' : 'user';
}

function hasAdminAuthSchema(user) {
    return Boolean(user &&
        Object.prototype.hasOwnProperty.call(user, 'role') &&
        Object.prototype.hasOwnProperty.call(user, 'status') &&
        Object.prototype.hasOwnProperty.call(user, 'auth_session_version'));
}

function isCurrentSession(tokenVersion, userVersion) {
    const expected = Number.isInteger(userVersion) ? userVersion : 0;
    const supplied = Number.isInteger(tokenVersion) ? tokenVersion : 0;
    return supplied === expected;
}

function isAdminPrincipal(user) {
    return user?.role === 'admin' && user?.id !== SYNTHETIC_ADMIN_ID &&
        (user?.admin_auth_version === 2 || user?.admin_auth_version === 3);
}

module.exports = {
    SYNTHETIC_ADMIN_ID,
    configuredAdminEmails,
    configuredRootAdminEmails,
    hasAdminAuthSchema,
    isCurrentSession,
    isAdminPrincipal,
    isConfiguredAdminEmail,
    isConfiguredRootAdminEmail,
    isRootAdmin,
    isLegacyDefaultAdminPassword,
    isReservedAdminEmail,
    normalizeEmail,
    roleForUser
};
