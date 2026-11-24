const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const PURPOSE = 'finwise:self-account-deletion:v1';
const MIN_WAIT_MS = 15_000;
const MAX_AGE_MS = 10 * 60_000;
const CHALLENGE_SECRET = crypto.createHash('sha256')
    .update('finwise-account-deletion\0')
    .update(require('../middlewares/auth').JWT_SECRET)
    .digest();

function bearerToken(req) {
    const header = req.headers.authorization || '';
    return header.startsWith('Bearer ') ? header.slice(7) : header;
}

function tokenFingerprint(req) {
    return crypto.createHash('sha256').update(bearerToken(req)).digest('hex');
}

function issueDeletionChallenge({ userId, sessionVersion, req, now = Date.now() }) {
    const payload = {
        purpose: PURPOSE,
        uid: userId,
        sv: sessionVersion,
        token_hash: tokenFingerprint(req),
        issued_at_ms: now,
        expires_at_ms: now + MAX_AGE_MS,
        nonce: crypto.randomBytes(16).toString('hex')
    };
    return jwt.sign({ ...payload, iat: Math.floor(now / 1000) }, CHALLENGE_SECRET, { algorithm: 'HS256', expiresIn: '10m' });
}

function validateDeletionChallenge({ challenge, userId, sessionVersion, req, now = Date.now() }) {
    if (typeof challenge !== 'string' || challenge.length < 20 || challenge.length > 2048) return false;
    try {
        const payload = jwt.verify(challenge, CHALLENGE_SECRET, {
            algorithms: ['HS256'],
            clockTimestamp: Math.floor(now / 1000)
        });
        const issuedAt = payload.issued_at_ms;
        const expiresAt = payload.expires_at_ms;
        return payload.purpose === PURPOSE &&
            payload.uid === userId &&
            payload.sv === sessionVersion &&
            typeof payload.nonce === 'string' &&
            Number.isSafeInteger(issuedAt) &&
            Number.isSafeInteger(expiresAt) &&
            expiresAt - issuedAt === MAX_AGE_MS &&
            now >= issuedAt + MIN_WAIT_MS &&
            now < expiresAt &&
            payload.token_hash === tokenFingerprint(req);
    } catch (_) {
        return false;
    }
}

module.exports = {
    MIN_WAIT_MS,
    MAX_AGE_MS,
    issueDeletionChallenge,
    validateDeletionChallenge
};
