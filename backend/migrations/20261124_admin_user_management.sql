-- Additive account creation and ordinary-user profile editing for Admin.
-- Apply after 20261124_admin_operations.sql using the Supabase SQL Editor.
BEGIN;

ALTER TABLE public.admin_audit_events DROP CONSTRAINT IF EXISTS admin_audit_events_action_check;
ALTER TABLE public.admin_audit_events ADD CONSTRAINT admin_audit_events_action_check
  CHECK (action IN ('status','role','delete','create','edit'));

CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_actor_id uuid, p_email text, p_full_name text, p_password_hash text,
  p_admin_emails text[], p_root_emails text[], p_actor_session_version integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE actor public.users%ROWTYPE; created public.users%ROWTYPE;
BEGIN
  SELECT * INTO actor FROM public.users WHERE id=p_actor_id FOR SHARE;
  IF NOT FOUND OR actor.status <> 'active' OR
     (actor.role <> 'admin' AND NOT lower(actor.email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))
      AND NOT lower(actor.email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[]))) THEN
    RAISE EXCEPTION 'actor_not_admin';
  END IF;
  IF actor.auth_session_version IS DISTINCT FROM p_actor_session_version THEN RAISE EXCEPTION 'stale_actor_session'; END IF;
  IF p_email IS NULL OR p_email <> lower(btrim(p_email)) OR length(p_email)>255 OR
     p_full_name IS NULL OR length(btrim(p_full_name))=0 OR length(p_full_name)>150 OR
     p_password_hash IS NULL OR p_password_hash !~ '^\$2[aby]\$[0-9]{2}\$' THEN RAISE EXCEPTION 'invalid_profile'; END IF;
  IF lower(p_email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[])) OR
     lower(p_email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[])) OR
     lower(p_email) IN ('admin@finwise.com','admin@finwise.vn','demo@finwise.vn') THEN RAISE EXCEPTION 'reserved_email'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(lower(p_email), 0));
  IF EXISTS(SELECT 1 FROM public.users WHERE lower(email)=lower(p_email)) THEN RAISE EXCEPTION 'email_already_exists'; END IF;
  INSERT INTO public.users(email,full_name,password_hash,role,status,auth_session_version)
    VALUES(lower(p_email),btrim(p_full_name),p_password_hash,'user','active',0) RETURNING * INTO created;
  INSERT INTO public.wallets(user_id,name,balance,currency,is_default)
    VALUES(created.id,'Ví Tiền Mặt',0,'VND',true);
  INSERT INTO public.admin_audit_events(actor_id,target_user_id,action,old_value,new_value)
    VALUES(p_actor_id,created.id,'create',NULL,'user');
  RETURN jsonb_build_object('success',true,'user',jsonb_build_object(
    'id',created.id,'email',created.email,'full_name',created.full_name,'role','user','status','active','created_at',created.created_at));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_user_profile(
  p_actor_id uuid, p_target_id uuid, p_email text, p_full_name text,
  p_admin_emails text[], p_root_emails text[], p_actor_session_version integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE actor public.users%ROWTYPE; target public.users%ROWTYPE; email_changed boolean;
BEGIN
  SELECT * INTO actor FROM public.users WHERE id=p_actor_id FOR SHARE;
  IF NOT FOUND OR actor.status <> 'active' OR
     (actor.role <> 'admin' AND NOT lower(actor.email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))
      AND NOT lower(actor.email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[]))) THEN RAISE EXCEPTION 'actor_not_admin'; END IF;
  IF actor.auth_session_version IS DISTINCT FROM p_actor_session_version THEN RAISE EXCEPTION 'stale_actor_session'; END IF;
  IF p_target_id=p_actor_id THEN RAISE EXCEPTION 'self_protection'; END IF;
  SELECT * INTO target FROM public.users WHERE id=p_target_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'target_not_found'; END IF;
  IF target.role='admin' OR lower(target.email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[])) OR
     lower(target.email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[])) OR
     lower(target.email) IN ('admin@finwise.com','admin@finwise.vn','demo@finwise.vn') THEN RAISE EXCEPTION 'protected_account'; END IF;
  IF p_email IS NULL OR p_email <> lower(btrim(p_email)) OR length(p_email)>255 OR
     p_full_name IS NULL OR length(btrim(p_full_name))=0 OR length(p_full_name)>150 THEN RAISE EXCEPTION 'invalid_profile'; END IF;
  IF lower(p_email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[])) OR
     lower(p_email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[])) OR
     lower(p_email) IN ('admin@finwise.com','admin@finwise.vn','demo@finwise.vn') THEN RAISE EXCEPTION 'reserved_email'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(lower(p_email), 0));
  IF EXISTS(SELECT 1 FROM public.users WHERE lower(email)=lower(p_email) AND id<>p_target_id) THEN RAISE EXCEPTION 'email_already_exists'; END IF;
  email_changed := target.email IS DISTINCT FROM lower(p_email);
  UPDATE public.users SET email=lower(p_email), full_name=btrim(p_full_name),
    auth_session_version=auth_session_version+CASE WHEN email_changed THEN 1 ELSE 0 END
    WHERE id=p_target_id;
  INSERT INTO public.admin_audit_events(actor_id,target_user_id,action,old_value,new_value)
    VALUES(p_actor_id,p_target_id,'edit','profile','profile');
  RETURN jsonb_build_object('success',true,'user',jsonb_build_object(
    'id',p_target_id,'email',lower(p_email),'full_name',btrim(p_full_name),'role','user','status',target.status));
END; $$;

REVOKE ALL ON FUNCTION public.admin_create_user(uuid,text,text,text,text[],text[],integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_update_user_profile(uuid,uuid,text,text,text[],text[],integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_user(uuid,text,text,text,text[],text[],integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile(uuid,uuid,text,text,text[],text[],integer) TO service_role;
COMMIT;
