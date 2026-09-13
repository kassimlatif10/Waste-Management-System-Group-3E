-- Phase 4: investor dashboard, porting investor_views.py's _company_stats
-- (:40), _investor_share_amount (:94), InvestorDashboardView/EarningsView.

alter table public.investor_profiles add column if not exists is_active boolean not null default true;

create or replace function public.get_company_stats()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_commission_rate numeric;
  v_total_sales numeric;
  v_total_revenue numeric;
  v_month_revenue numeric;
  v_year_revenue numeric;
  v_net_profit numeric;
  v_year_net_profit numeric;
  v_completed_count int;
  v_branches jsonb;
begin
  select commission_rate into v_commission_rate from system_config where id = 1;

  select coalesce(sum(price), 0), count(*) into v_total_sales, v_completed_count
    from pickup_requests where status = 'completed';
  v_total_revenue := round(v_total_sales * v_commission_rate / 100, 2);

  select coalesce(round(sum(price) * v_commission_rate / 100, 2), 0) into v_month_revenue
    from pickup_requests where status = 'completed' and completed_at >= date_trunc('month', now());

  select coalesce(round(sum(price) * v_commission_rate / 100, 2), 0) into v_year_revenue
    from pickup_requests where status = 'completed' and completed_at >= date_trunc('year', now());

  v_net_profit := round(v_total_revenue * 0.60, 2);
  v_year_net_profit := round(v_year_revenue * 0.60, 2);

  select coalesce(jsonb_agg(jsonb_build_object(
    'branch_id', b.id, 'branch_name', b.name, 'region', b.region,
    'total_revenue', round(coalesce(br.rev, 0) * v_commission_rate / 100, 2),
    'collections', coalesce(br.cnt, 0)
  )), '[]'::jsonb) into v_branches
  from branches b
  left join lateral (
    select sum(pr.price) as rev, count(*) as cnt
    from pickup_requests pr join profiles p on p.id = pr.collector_id
    where pr.status = 'completed' and p.branch_id = b.id
  ) br on true
  where b.is_active;

  return jsonb_build_object(
    'total_company_revenue', v_total_revenue,
    'total_sales', v_total_sales,
    'month_revenue', v_month_revenue,
    'year_revenue', v_year_revenue,
    'net_profit', v_net_profit,
    'year_net_profit', v_year_net_profit,
    'profit_margin_pct', case when v_total_revenue > 0 then round(v_net_profit / v_total_revenue * 100, 1) else 0 end,
    'operating_cost_rate', '40%',
    'completed_collections', v_completed_count,
    'branch_breakdown', v_branches
  );
end;
$$;
revoke all on function public.get_company_stats() from public;
grant execute on function public.get_company_stats() to authenticated;

create or replace function public.get_investor_earnings_share(p_investor_id bigint)
returns numeric
language plpgsql security definer set search_path = public as $$
declare
  v_investment numeric;
  v_roi numeric;
  v_total_invested numeric;
  v_year_revenue numeric;
begin
  select investment_amount, roi_percentage into v_investment, v_roi
    from investor_profiles where id = p_investor_id;
  if v_investment is null or v_investment <= 0 then return 0; end if;

  select coalesce(sum(investment_amount), 0) into v_total_invested
    from investor_profiles where is_active;
  if v_total_invested <= 0 then return 0; end if;

  v_year_revenue := (get_company_stats()->>'year_revenue')::numeric;
  return round((v_year_revenue * (v_investment / v_total_invested)) * (v_roi / 100), 2);
end;
$$;
revoke all on function public.get_investor_earnings_share(bigint) from public;
grant execute on function public.get_investor_earnings_share(bigint) to authenticated;
