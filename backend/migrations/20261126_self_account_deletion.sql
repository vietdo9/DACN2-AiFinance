-- Apply manually in the Supabase SQL Editor after a database backup.
-- The backend calls this only after verifying the current bearer session and
-- the signed, delayed self-deletion challenge.
BEGIN;

CREATE OR REPLACE FUNCTION public.self_delete_account(
    p_user_id uuid,
    p_session_version integer,
    p_admin_emails text[],
    p_root_emails text[]
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE target public.users%ROWTYPE;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'service_role_required';
    END IF;

    SELECT * INTO target FROM public.users WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'account_not_found'; END IF;
    IF target.auth_session_version IS DISTINCT FROM p_session_version THEN
        RAISE EXCEPTION 'stale_session';
    END IF;
    IF target.status IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'account_not_active'; END IF;
    IF target.role = 'admin'
       OR lower(target.email) = ANY(COALESCE(p_admin_emails, ARRAY[]::text[]))
       OR lower(target.email) = ANY(COALESCE(p_root_emails, ARRAY[]::text[]))
       OR lower(target.email) IN ('admin@finwise.com', 'admin@finwise.vn', 'demo@finwise.vn')
       OR target.id = '00000000-0000-0000-0000-000000000001'::uuid THEN
        RAISE EXCEPTION 'protected_account';
    END IF;

    -- The current schema cascades wallets, transactions, and budgets from users.
    -- Preserve admin audit evidence; it contains no transaction or wallet data.
    DELETE FROM public.users WHERE id = p_user_id;
    RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.self_delete_account(uuid,integer,text[],text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.self_delete_account(uuid,integer,text[],text[]) TO service_role;
COMMIT;
