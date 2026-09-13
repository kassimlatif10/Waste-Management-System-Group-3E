-- get_admin_dashboard_stats (0011) was missing total_commission_collected
-- (sum of collection_commissions.commission_amount where status='paid',
-- period-filtered on the commission's own created_at) — admin_home.dart's
-- dashboard card at line ~777 has always expected this field alongside
-- total_commission_owed; found while auditing the dashboard's overview
-- fields against the UI.

create or replace function public.get_admin_dashboard_stats(p_period text default 'all', p_branch_id bigint default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_since timestamptz;
  v_commission_rate numeric;
  v_total_sales numeric;
  v_company_sales numeric;
  v_indep_sales numeric;
  v_revenue_company numeric;
  v_revenue_indep numeric;
  v_total_revenue numeric;
  v_total_paid_out numeric;
  v_commission_owed numeric;
  v_commission_collected numeric;
  v_pending_payout numeric;
  v_total_customers int;
  v_total_collectors int;
  v_active_collectors int;
  v_counts jsonb;
  v_trend jsonb;
begin
  if not is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  v_since := case p_period
    when 'today' then date_trunc('day', now())
    when 'week' then now() - interval '7 days'
    when 'month' then now() - interval '30 days'
    when 'year' then now() - interval '365 days'
    else '1970-01-01'::timestamptz
  end;

  select commission_rate into v_commission_rate from system_config where id = 1;

  select coalesce(sum(pr.price), 0) into v_total_sales
    from pickup_requests pr
    where pr.status = 'completed' and pr.created_at >= v_since
      and (p_branch_id is null or exists (
        select 1 from profiles p where p.id = pr.collector_id and p.branch_id = p_branch_id
      ));

  select coalesce(sum(pr.price), 0) into v_company_sales
    from pickup_requests pr join collector_profiles cp on cp.user_id = pr.collector_id
    where pr.status = 'completed' and pr.created_at >= v_since and cp.is_company_collector
      and (p_branch_id is null or exists (
        select 1 from profiles p where p.id = pr.collector_id and p.branch_id = p_branch_id
      ));

  v_indep_sales := v_total_sales - v_company_sales;
  v_revenue_company := v_company_sales;
  v_revenue_indep := round(v_indep_sales * v_commission_rate / 100, 2);
  v_total_revenue := v_revenue_company + v_revenue_indep;

  select coalesce(sum(cp.total_earnings), 0), coalesce(sum(cp.unpaid_commission), 0)
    into v_total_paid_out, v_commission_owed
    from collector_profiles cp join profiles p on p.id = cp.user_id
    where p_branch_id is null or p.branch_id = p_branch_id;

  select coalesce(sum(cc.commission_amount), 0) into v_commission_collected
    from collection_commissions cc
    where cc.status = 'paid' and cc.created_at >= v_since
      and (p_branch_id is null or exists (
        select 1 from pickup_requests pr
        join profiles p on p.id = pr.collector_id
        where pr.id = cc.pickup_request_id and p.branch_id = p_branch_id
      ));

  select coalesce(sum(wr.amount), 0) into v_pending_payout
    from withdrawal_requests wr join profiles p on p.id = wr.collector_id
    where wr.status = 'pending' and (p_branch_id is null or p.branch_id = p_branch_id);

  select count(*) filter (where role = 'customer'),
         count(*) filter (where role = 'collector' and (p_branch_id is null or branch_id = p_branch_id))
    into v_total_customers, v_total_collectors
    from profiles;

  select count(*) into v_active_collectors
    from collector_profiles cp join profiles p on p.id = cp.user_id
    where cp.is_online and cp.is_approved and (p_branch_id is null or p.branch_id = p_branch_id);

  select jsonb_build_object(
    'total', count(*),
    'completed', count(*) filter (where status = 'completed'),
    'pending', count(*) filter (where status in ('finding','proposed','assigned')),
    'active', count(*) filter (where status in ('on_way','arrived')),
    'cancelled', count(*) filter (where status = 'cancelled')
  ) into v_counts
  from pickup_requests where created_at >= v_since;

  select coalesce(jsonb_agg(jsonb_build_object('day', day, 'revenue', revenue, 'count', cnt) order by day), '[]'::jsonb)
    into v_trend
  from (
    select date_trunc('day', completed_at)::date as day, sum(price) as revenue, count(*) as cnt
    from pickup_requests
    where status = 'completed' and completed_at >= now() - interval '30 days'
    group by 1
  ) t;

  return jsonb_build_object(
    'period', p_period,
    'overview', jsonb_build_object(
      'total_sales', v_total_sales,
      'total_revenue', v_total_revenue,
      'company_collectors_revenue', v_revenue_company,
      'commission_from_independent', v_revenue_indep,
      'total_paid_out', v_total_paid_out,
      'pending_payout', v_pending_payout,
      'total_commission_collected', v_commission_collected,
      'total_commission_owed', v_commission_owed,
      'total_customers', v_total_customers,
      'total_collectors', v_total_collectors,
      'active_collectors', v_active_collectors,
      'commission_rate', v_commission_rate
    ),
    'collections', v_counts,
    'daily_trend', v_trend
  );
end;
$$;
revoke all on function public.get_admin_dashboard_stats(text, bigint) from public;
grant execute on function public.get_admin_dashboard_stats(text, bigint) to authenticated;
