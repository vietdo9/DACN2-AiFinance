-- Add date-filtered aggregate support while keeping the legacy two-argument RPC intact.
-- Apply after the 20261124 admin migrations; backend rollout follows this migration.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_overview_data_period(
    p_admin_emails text[], p_root_emails text[], p_period_start date, p_period_end date
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
    WITH user_stats AS (
        SELECT count(*)::bigint total_users,
               count(*) FILTER (WHERE status <> 'suspended')::bigint active_users,
               count(*) FILTER (WHERE status = 'suspended')::bigint suspended_users,
               count(*) FILTER (WHERE role = 'admin' OR lower(email)=ANY(COALESCE(p_admin_emails,ARRAY[]::text[]))
                 OR lower(email)=ANY(COALESCE(p_root_emails,ARRAY[]::text[])))::bigint admin_users FROM public.users
    ), period_transactions AS (
        SELECT type, amount, category_code FROM public.transactions
        WHERE (p_period_start IS NULL OR transaction_date >= p_period_start)
          AND (p_period_end IS NULL OR transaction_date <= p_period_end)
    ), tx_stats AS (
        SELECT count(*)::bigint total_transactions,
               COALESCE(sum(amount) FILTER (WHERE type='income'),0) total_income,
               COALESCE(sum(amount) FILTER (WHERE type='expense'),0) total_expense FROM period_transactions
    ), category_stats AS (
        SELECT category_code, count(*)::bigint count, sum(amount) amount
        FROM period_transactions WHERE type='expense' GROUP BY category_code
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

REVOKE ALL ON FUNCTION public.admin_overview_data_period(text[],text[],date,date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_overview_data_period(text[],text[],date,date) TO service_role;
COMMIT;
