-- Adds the remaining investor_profiles columns missed in 0001, and a
-- get_investor_dashboard() RPC porting investor_views.py's
-- InvestorDashboardView (:144) — reuses get_company_stats() and
-- get_investor_earnings_share() from Phase 4.

alter table public.investor_profiles add column if not exists contract_reference text;
alter table public.investor_profiles add column if not exists agreement_date date;
alter table public.investor_profiles add column if not exists notes text;

create or replace function public.get_investor_dashboard()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
  v_company_name text;
  v_location text;
  v_investment_amount numeric;
  v_contract_reference text;
  v_agreement_date date;
  v_roi_percentage numeric;
  v_yearly_profit_margin numeric;
  v_is_active boolean;
  v_created_at timestamptz;
  v_full_name text;
  v_phone text;
  v_email text;
  v_profile_image text;
  v_today numeric;
  v_week numeric;
  v_month numeric;
  v_company jsonb;
  v_year_rev numeric;
  v_estimated_share numeric;
  v_roi_actual numeric;
begin
  select ip.id, ip.company_name, ip.location, ip.investment_amount, ip.contract_reference,
         ip.agreement_date, ip.roi_percentage, ip.yearly_profit_margin, ip.is_active, ip.created_at,
         p.first_name || coalesce(' ' || p.last_name, ''), p.phone, p.email, p.profile_image
    into v_id, v_company_name, v_location, v_investment_amount, v_contract_reference,
         v_agreement_date, v_roi_percentage, v_yearly_profit_margin, v_is_active, v_created_at,
         v_full_name, v_phone, v_email, v_profile_image
    from investor_profiles ip join profiles p on p.id = ip.user_id
    where ip.user_id = v_uid;
  if v_id is null then
    raise exception 'Investor profile not found.' using errcode = 'P0002';
  end if;

  select coalesce(sum(amount), 0) into v_today from investor_earnings where investor_id = v_id and date = current_date;
  select coalesce(sum(amount), 0) into v_week from investor_earnings where investor_id = v_id and date >= date_trunc('week', current_date);
  select coalesce(sum(amount), 0) into v_month from investor_earnings where investor_id = v_id and date >= date_trunc('month', current_date);
  select coalesce(sum(amount), 0) into v_roi_actual from investor_earnings where investor_id = v_id;

  v_company := get_company_stats();
  v_year_rev := (v_company->>'year_revenue')::numeric;
  v_estimated_share := get_investor_earnings_share(v_id);

  return jsonb_build_object(
    'investor', jsonb_build_object(
      'id', v_id,
      'full_name', v_full_name,
      'phone', v_phone,
      'email', v_email,
      'company_name', v_company_name,
      'location', v_location,
      'investment_amount', v_investment_amount,
      'contract_reference', v_contract_reference,
      'agreement_date', v_agreement_date,
      'roi_percentage', v_roi_percentage,
      'yearly_profit_margin', v_yearly_profit_margin,
      'is_active', v_is_active,
      'member_since', to_char(v_created_at, 'FMMonth YYYY'),
      'profile_image', v_profile_image
    ),
    'company_stats', v_company,
    'earnings_summary', jsonb_build_object(
      'today', v_today,
      'this_week', v_week,
      'this_month', v_month,
      'total', v_roi_actual,
      'roi_actual', v_roi_actual,
      'estimated_year_share', v_estimated_share
    )
  );
end;
$$;
revoke all on function public.get_investor_dashboard() from public;
grant execute on function public.get_investor_dashboard() to authenticated;
