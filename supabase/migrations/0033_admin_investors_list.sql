-- Ports AdminInvestorListCreateView.get() (investor_views.py:310) for
-- admin_home.dart's Investors List page. total_earnings/roi_actual are
-- Django @property computed from summed investor_earnings, not stored
-- columns, so this needs an RPC rather than a plain PostgREST select.

create or replace function public.get_admin_investors_list()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_results jsonb;
begin
  if not is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb) into v_results
  from (
    select jsonb_build_object(
      'id', ip.id,
      'user_id', ip.user_id,
      'full_name', coalesce(nullif(trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,'')), ''), p.username, 'Investor'),
      'phone', p.phone,
      'email', coalesce(p.email, ''),
      'company_name', ip.company_name,
      'location', ip.location,
      'investment_amount', ip.investment_amount,
      'contract_reference', ip.contract_reference,
      'agreement_date', ip.agreement_date,
      'roi_percentage', ip.roi_percentage,
      'total_earnings', earnings.total,
      'roi_actual', case when ip.investment_amount > 0 then round(earnings.total / ip.investment_amount * 100, 2) else 0 end,
      'is_active', ip.is_active,
      'created_at', ip.created_at
    ) as row_data,
    ip.created_at
    from investor_profiles ip
    join profiles p on p.id = ip.user_id
    cross join lateral (
      select coalesce(sum(ie.amount), 0) as total from investor_earnings ie where ie.investor_id = ip.id
    ) earnings
  ) t;

  return v_results;
end;
$$;
revoke all on function public.get_admin_investors_list() from public;
grant execute on function public.get_admin_investors_list() to authenticated;
