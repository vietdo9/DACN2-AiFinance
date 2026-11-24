const { emailHash } = require('./localAccountCleanup');

function validateAdminDeleteTarget({ requestedId, foundId, email, confirmEmail, isRootEmail }) {
    const normalizedId = typeof requestedId === 'string' ? requestedId.toLowerCase() : '';
    const normalizedTargetId = typeof foundId === 'string' ? foundId.toLowerCase() : '';
    const normalizedEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
    const normalizedConfirmation = typeof confirmEmail === 'string' ? confirmEmail.trim().toLowerCase() : '';
    if (!normalizedId || normalizedId !== normalizedTargetId) return 'target_mismatch';
    if (!normalizedEmail) return 'invalid_email';
    if (isRootEmail(normalizedEmail)) return 'protected_target';
    if (!normalizedConfirmation || normalizedConfirmation !== normalizedEmail) return 'confirmation_mismatch';
    return null;
}

/**
 * Runs the common local spillover cleanup around a caller-specific cloud delete
 * RPC. The route owns authorization and RPC arguments; this service owns the
 * durable local retry marker and ID/email collision defense.
 */
async function deleteCloudAccount({ userId, email, rpc, localStore, recoverPending }) {
    const normalizedEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
    if (!userId || typeof email !== 'string') {
        return { ok: false, reason: 'invalid_target' };
    }
    if (localStore.isCloudAccountDeletionInFlight(userId)) {
        return { ok: false, reason: 'in_flight' };
    }

    localStore.queueCloudAccountCleanup(userId, normalizedEmail);
    localStore.beginCloudAccountDeletion(userId);

    let rpcResult;
    let rpcFailed = false;
    let rpcError = null;
    try {
        rpcResult = await rpc();
    } catch (error) {
        rpcFailed = true;
        rpcError = error;
    } finally {
        localStore.endCloudAccountDeletion(userId);
    }
    if (rpcFailed) {
        if (recoverPending) await recoverPending();
        return { ok: false, reason: 'rpc_failed', error: rpcError };
    }

    if (rpcResult?.error || rpcResult?.data?.success !== true) {
        if (recoverPending) await recoverPending();
        return { ok: false, reason: 'rpc_failed', error: rpcResult?.error || null, data: rpcResult?.data };
    }

    try {
        localStore.deleteUserData(userId, {
            requireUser: false,
            removeUser: true,
            expectedEmailHash: emailHash(normalizedEmail)
        });
        // A legacy local identity may share the cloud UUID. The local cleanup
        // helper keeps it and its rows intact when its email hash differs.
        localStore.completeCloudAccountCleanup(userId);
        return { ok: true, cleanupPending: false };
    } catch (_) {
        // The cloud delete is committed. Retain the durable marker so recovery
        // can retry local cleanup on the next pass.
        return { ok: true, cleanupPending: true };
    }
}

module.exports = { deleteCloudAccount, validateAdminDeleteTarget };
