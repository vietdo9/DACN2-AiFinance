-- Admin operations capability and audit trail.
-- Apply manually in Supabase SQL Editor after taking a database backup.
BEGIN;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'user';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS auth_session_version integer NOT NULL DEFAULT 0;
-- This backend uses a private service-role key. Do not run this migration while
-- the deployed backend still uses a publishable/anon key for its writes.
REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLE public.users FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.users TO service_role;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_check CHECK (role IN ('user','admin'));
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_status_check;
ALTER TABLE public.users ADD CONSTRAINT users_status_check CHECK (status IN ('active','suspended'));

CREATE TABLE IF NOT EXISTS public.admin_audit_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id uuid NOT NULL,
    target_user_id uuid NOT NULL,
    action text NOT NULL CHECK (action IN ('status','role','delete')),
    old_value text,
    new_value text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS admin_audit_events_created_at_idx ON public.admin_audit_events(created_at DESC);
ALTER TABLE public.admin_audit_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_audit_events FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.admin_audit_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.admin_audit_events_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.admin_overview_data(p_admin_emails text[], p_root_emails text[]) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
    WITH user_stats AS (
        SELECT count(*)::bigint total_users,
               count(*) FILTER (WHERE status <> 'suspended')::bigint active_users,
               count(*) FILTER (WHERE status = 'suspended')::bigint suspended_users,
               count(*) FILTER (WHERE role = 'admin' OR lower(email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))
                 OR lower(email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[])))::bigint admin_users FROM public.users
    ), tx_stats AS (
        SELECT count(*)::bigint total_transactions,
               COALESCE(sum(amount) FILTER (WHERE type='income'),0) total_income,
               COALESCE(sum(amount) FILTER (WHERE type='expense'),0) total_expense FROM public.transactions
    ), category_stats AS (
        SELECT category_code, count(*)::bigint count, sum(amount) amount
        FROM public.transactions WHERE type='expense' GROUP BY category_code
    )
    SELECT jsonb_build_object(
        'metrics', jsonb_build_object('total_users',u.total_users,'active_users',u.active_users,
          'suspended_users',u.suspended_users,'admin_users',u.admin_users,'total_transactions',t.total_transactions,
          'total_volume',t.total_income+t.total_expense,'total_income',t.total_income,'total_expense',t.total_expense,
          'total_wallets',(SELECT count(*)::bigint FROM public.wallets)),
        'category_distribution', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'code',c.category_code,'name',COALESCE(cat.name,c.category_code),'color',COALESCE(cat.color,'#64748B'),
          'count',c.count,'amount',c.amount,'percent',CASE WHEN t.total_expense=0 THEN 0
            ELSE round(c.amount/t.total_expense*100,1) END) ORDER BY c.amount DESC)
          FROM category_stats c LEFT JOIN public.categories cat ON cat.code=c.category_code),'[]'::jsonb))
    FROM user_stats u CROSS JOIN tx_stats t;
$$;

CREATE OR REPLACE FUNCTION public.admin_users_page(p_page integer, p_per_page integer, p_query text,
    p_role text, p_status text, p_admin_emails text[], p_root_emails text[])
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
    WITH filtered AS (
        SELECT id,email,full_name,
          CASE WHEN role='admin' OR lower(email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))
            OR lower(email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[])) THEN 'admin' ELSE 'user' END role,
          status,created_at FROM public.users
        WHERE (p_query IS NULL OR email ILIKE '%'||p_query||'%' OR COALESCE(full_name,'') ILIKE '%'||p_query||'%')
          AND (p_role IS NULL OR (CASE WHEN role='admin' OR lower(email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))
            OR lower(email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[])) THEN 'admin' ELSE 'user' END)=p_role)
          AND (p_status IS NULL OR status=p_status)
    ), page_rows AS (
        SELECT u.*, (SELECT count(*)::bigint FROM public.transactions t WHERE t.user_id=u.id) transaction_count,
               (SELECT count(*)::bigint FROM public.wallets w WHERE w.user_id=u.id) wallet_count
        FROM filtered u ORDER BY created_at DESC, id LIMIT GREATEST(1,LEAST(p_per_page,100))
        OFFSET (GREATEST(p_page,1)-1)*GREATEST(1,LEAST(p_per_page,100))
    )
    SELECT jsonb_build_object('total',(SELECT count(*)::bigint FROM filtered),
      'users',COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at DESC,p.id) FROM page_rows p),'[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.admin_mutate_user(
    p_actor_id uuid, p_target_id uuid, p_action text, p_value text,
    p_root_emails text[], p_admin_emails text[], p_actor_session_version integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE actor public.users%ROWTYPE; target public.users%ROWTYPE; old_value text; actor_is_root boolean;
BEGIN
    SELECT * INTO actor FROM public.users WHERE id = p_actor_id FOR SHARE;
    actor_is_root := lower(actor.email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[]));
    IF NOT FOUND THEN RAISE EXCEPTION 'actor_not_admin'; END IF;
    IF actor.auth_session_version IS DISTINCT FROM p_actor_session_version THEN RAISE EXCEPTION 'stale_actor_session'; END IF;
    IF actor.status <> 'active' OR (actor.role <> 'admin' AND NOT actor_is_root
       AND NOT lower(actor.email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))) THEN
        RAISE EXCEPTION 'actor_not_admin';
    END IF;
    IF p_target_id = p_actor_id THEN RAISE EXCEPTION 'self_protection'; END IF;
    SELECT * INTO target FROM public.users WHERE id = p_target_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'target_not_found'; END IF;
    IF lower(target.email) = ANY(COALESCE(p_root_emails, ARRAY[]::text[])) THEN RAISE EXCEPTION 'root_protection'; END IF;
    IF p_action = 'status' AND (target.role = 'admin' OR lower(target.email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))) AND NOT actor_is_root THEN RAISE EXCEPTION 'root_admin_required'; END IF;
    IF p_action NOT IN ('status','role') THEN RAISE EXCEPTION 'invalid_action'; END IF;
    IF p_action = 'status' AND p_value NOT IN ('active','suspended') THEN RAISE EXCEPTION 'invalid_status'; END IF;
    IF p_action = 'role' AND p_value NOT IN ('user','admin') THEN RAISE EXCEPTION 'invalid_role'; END IF;
    IF p_action = 'role' AND NOT actor_is_root THEN RAISE EXCEPTION 'root_admin_required'; END IF;
    IF p_action = 'role' AND lower(target.email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[])) THEN RAISE EXCEPTION 'configured_admin_protected'; END IF;
    IF p_action = 'status' THEN
        old_value := target.status;
        IF old_value = p_value THEN RETURN jsonb_build_object('success',true,'user',jsonb_build_object('id',p_target_id,'status',p_value)); END IF;
        UPDATE public.users SET status=p_value, auth_session_version=auth_session_version+1 WHERE id=p_target_id;
    ELSE
        old_value := target.role;
        IF old_value = p_value THEN RETURN jsonb_build_object('success',true,'user',jsonb_build_object('id',p_target_id,'role',p_value)); END IF;
        UPDATE public.users SET role=p_value, auth_session_version=auth_session_version+1 WHERE id=p_target_id;
    END IF;
    INSERT INTO public.admin_audit_events(actor_id,target_user_id,action,old_value,new_value)
    VALUES(p_actor_id,p_target_id,p_action,old_value,p_value);
    RETURN jsonb_build_object('success',true,'user',jsonb_build_object('id',p_target_id,p_action,p_value));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_delete_user(
    p_actor_id uuid, p_target_id uuid, p_confirm_email text, p_root_emails text[], p_actor_session_version integer
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
    DELETE FROM public.users WHERE id=p_target_id;
    RETURN jsonb_build_object('success',true);
END; $$;

REVOKE ALL ON FUNCTION public.admin_overview_data(text[],text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_users_page(integer,integer,text,text,text,text[],text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_mutate_user(uuid,uuid,text,text,text[],text[],integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_delete_user(uuid,uuid,text,text[],integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_overview_data(text[],text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_users_page(integer,integer,text,text,text,text[],text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_mutate_user(uuid,uuid,text,text,text[],text[],integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid,uuid,text,text[],integer) TO service_role;
COMMIT;
