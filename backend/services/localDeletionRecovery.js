const { supabaseService, isSupabaseConfigured, isServiceRoleKeyConfigured } = require('../config/supabase');
const localStore = require('../config/localStore');

let recoveryInProgress = false;

async function recoverPendingCloudAccountCleanup() {
    if (!isSupabaseConfigured() || !isServiceRoleKeyConfigured() || recoveryInProgress) return;
    recoveryInProgress = true;
    try {
        const pendingIds = localStore.getPendingCloudAccountCleanup();
        for (const pending of pendingIds) {
            const userId = pending.user_id;
            if (localStore.isCloudAccountDeletionInFlight(userId)) continue;
            if (Date.now() < pending.retry_after_ms) continue;
            try {
                const { data, error } = await supabaseService.from('users').select('id').eq('id', userId).maybeSingle();
                if (error) continue;
                if (data) {
                    // The RPC did not commit. Release its process-local write guard
                    // only after the authoritative lookup confirms the account stays.
                    localStore.clearCloudAccountCleanup(userId);
                    continue;
                }
                localStore.blockCloudUserWrites(userId);
                const cleanup = localStore.deleteUserData(userId, {
                    requireUser: false,
                    removeUser: true,
                    expectedEmailHash: pending.email_hash
                });
                if (cleanup.identityMismatch) {
                    localStore.completeCloudAccountCleanup(userId);
                    continue;
                }
                localStore.completeCloudAccountCleanup(userId);
            } catch (_) {
                // Retain the durable ID-only queue entry and retry on the next pass.
            }
        }
    } catch (_) {
        // A malformed/unavailable queue remains untouched for operator repair.
    } finally {
        recoveryInProgress = false;
    }
}

module.exports = { recoverPendingCloudAccountCleanup };
