-- Ports CollectorListView's GET (admin_views.py:486) for admin_home.dart's
-- Collectors tab — paginated, searchable, filterable by kyc_status.

create or replace function public.get_admin_collectors_paged(
  p_search text default '', p_kyc_status text default '', p_page int default 1, p_page_size int default 20
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_total int;
  v_results jsonb;
  v_offset int := greatest(p_page - 1, 0) * p_page_size;
begin
  if not is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  select count(*) into v_total
  from collector_profiles cp
  join profiles p on p.id = cp.user_id
  left join collector_kyc ck on ck.user_id = cp.user_id
  where (p_search = '' or
         p.first_name ilike '%'||p_search||'%' or
         p.last_name ilike '%'||p_search||'%' or
         p.phone ilike '%'||p_search||'%')
    and (p_kyc_status = '' or ck.kyc_status = p_kyc_status);

  select coalesce(jsonb_agg(row_data), '[]'::jsonb) into v_results
  from (
    select jsonb_build_object(
      'id', cp.id,
      'user_id', cp.user_id,
      'name', coalesce(nullif(trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,'')), ''), p.username, 'Collector'),
      'phone', p.phone,
      'profile_image', p.profile_image,
      'vehicle_type', cp.vehicle_type,
      'is_approved', cp.is_approved,
      'is_online', cp.is_online,
      'rating', round(cp.rating, 2),
      'rating_count', cp.rating_count,
      'credit_score', cp.credit_score,
      'total_collections', cp.total_collections,
      'total_earnings', cp.total_earnings,
      'unpaid_commission', cp.unpaid_commission,
      'is_company_collector', cp.is_company_collector,
      'kyc_status', ck.kyc_status,
      'applied_at', cp.created_at
    ) as row_data
    from collector_profiles cp
    join profiles p on p.id = cp.user_id
    left join collector_kyc ck on ck.user_id = cp.user_id
    where (p_search = '' or
           p.first_name ilike '%'||p_search||'%' or
           p.last_name ilike '%'||p_search||'%' or
           p.phone ilike '%'||p_search||'%')
      and (p_kyc_status = '' or ck.kyc_status = p_kyc_status)
    order by cp.created_at desc
    limit p_page_size offset v_offset
  ) t;

  return jsonb_build_object('total', v_total, 'page', p_page, 'page_size', p_page_size, 'results', v_results);
end;
$$;
revoke all on function public.get_admin_collectors_paged(text, text, int, int) from public;
grant execute on function public.get_admin_collectors_paged(text, text, int, int) to authenticated;
