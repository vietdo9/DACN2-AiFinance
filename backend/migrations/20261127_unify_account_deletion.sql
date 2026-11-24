-- Route both authorized account deletion flows through one private SQL core.
-- Apply manually in the Supabase SQL Editor after the 20261126 migrations.
BEGIN;

CREATE SCHEMA IF NOT EXISTS finwise_account_internal;
REVOKE ALL ON SCHEMA finwise_account_internal FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION finwise_account_internal.delete_authorized_user(p_authorized_user_id uuid)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    DELETE FROM public.users WHERE id = p_authorized_user_id;
$$;

-- This core is callable only from the security-definer wrapper owners below.
REVOKE ALL ON FUNCTION finwise_account_internal.delete_authorized_user(uuid)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_delete_user(
    p_actor_id uuid, p_target_id uuid, p_confirm_email text,
    p_root_emails text[], p_actor_session_version integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE actor public.users%ROWTYPE; target public.users%ROWTYPE;
BEGIN
    SELECT * INTO actor FROM public.users WHERE id=p_actor_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'root_admin_required'; END IF;
    IF actor.auth_session_version IS DISTINCT FROM p_actor_session_version THEN RAISE EXCEPTION 'stale_actor_session'; END IF;
    IF actor.status <> 'active' OR NOT (lower(actor.email)=ANY(COALESCE(p_root_emails, ARRAY[]::text[]))) THEN
        RAISE EXCEPTION 'root_admin_required';
    END IF;
    IF p_target_id=p_actor_id THEN RAISE EXCEPTION 'self_protection'; END IF;
    SELECT * INTO target FROM public.users WHERE id=p_target_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'target_not_found'; END IF;
    IF lower(target.email)=ANY(COALESCE(p_root_emails, ARRAY[]::text[])) THEN RAISE EXCEPTION 'root_protection'; END IF;
    IF lower(target.email) <> lower(COALESCE(p_confirm_email,'')) THEN RAISE EXCEPTION 'confirmation_mismatch'; END IF;
    INSERT INTO public.admin_audit_events(actor_id,target_user_id,action,old_value,new_value)
    VALUES(p_actor_id,p_target_id,'delete',target.role || ':' || target.status,'deleted');
    PERFORM finwise_account_internal.delete_authorized_user(p_target_id);
    RETURN jsonb_build_object('success',true);
END; $$;

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

    PERFORM finwise_account_internal.delete_authorized_user(p_user_id);
    RETURN jsonb_build_object('success', true);
END;
$$;

-- CREATE OR REPLACE preserves each wrapper's owner. Fail closed unless that
-- owner is the migration role, which owns the dedicated schema and core.
DO $$
DECLARE
    schema_owner name;
    admin_owner name;
    self_owner name;
BEGIN
    SELECT owner_role.rolname INTO STRICT schema_owner
      FROM pg_namespace ns
      JOIN pg_roles owner_role ON owner_role.oid = ns.nspowner
     WHERE ns.nspname = 'finwise_account_internal';
    SELECT owner_role.rolname INTO STRICT admin_owner
      FROM pg_proc proc
      JOIN pg_namespace ns ON ns.oid = proc.pronamespace
      JOIN pg_roles owner_role ON owner_role.oid = proc.proowner
     WHERE proc.oid = 'public.admin_delete_user(uuid,uuid,text,text[],integer)'::regprocedure;
    SELECT owner_role.rolname INTO STRICT self_owner
      FROM pg_proc proc
      JOIN pg_namespace ns ON ns.oid = proc.pronamespace
      JOIN pg_roles owner_role ON owner_role.oid = proc.proowner
     WHERE proc.oid = 'public.self_delete_account(uuid,integer,text[],text[])'::regprocedure;
    IF schema_owner <> current_user OR admin_owner <> current_user OR self_owner <> current_user
       OR current_user IN ('service_role', 'anon', 'authenticated') THEN
        RAISE EXCEPTION 'unexpected_account_delete_wrapper_owner';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_user(uuid,uuid,text,text[],integer)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.self_delete_account(uuid,integer,text[],text[])
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid,uuid,text,text[],integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.self_delete_account(uuid,integer,text[],text[]) TO service_role;

COMMIT;
