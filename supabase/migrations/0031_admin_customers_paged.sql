-- Ports CustomerListView (admin_views.py:383) for admin_home.dart's
-- Customers page — paginated, searchable, with per-customer completed-trip
-- count and total-spent, which needs an aggregate over pickup_requests per
-- row (not cleanly expressible as a plain PostgREST select+embed).
-- Branch-scoping is left out to match the dashboard RPC (0011), which the
-- Flutter admin UI already calls without a branch_id — not a new gap.

create or replace function public.get_admin_customers_paged(p_search text default '', p_page int default 1, p_page_size int default 20)
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
  from profiles p
  where p.role = 'customer'
    and (p_search = '' or
         p.first_name ilike '%'||p_search||'%' or
         p.last_name ilike '%'||p_search||'%' or
         p.phone ilike '%'||p_search||'%' or
         p.username ilike '%'||p_search||'%');

  select coalesce(jsonb_agg(row_data), '[]'::jsonb) into v_results
  from (
    select jsonb_build_object(
      'id', p.id,
      'role', p.role,
      'name', coalesce(nullif(trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,'')), ''), p.username, 'Customer'),
      'username', p.username,
      'phone', p.phone,
      'email', p.email,
      'profile_image', p.profile_image,
      'date_joined', p.created_at,
      'is_active', p.is_active,
      'total_requests', (select count(*) from pickup_requests pr where pr.customer_id = p.id),
      'completed_requests', (select count(*) from pickup_requests pr where pr.customer_id = p.id and pr.status = 'completed'),
      'total_spent', (select coalesce(sum(pr.price), 0) from pickup_requests pr where pr.customer_id = p.id and pr.status = 'completed')
    ) as row_data
    from profiles p
    where p.role = 'customer'
      and (p_search = '' or
           p.first_name ilike '%'||p_search||'%' or
           p.last_name ilike '%'||p_search||'%' or
           p.phone ilike '%'||p_search||'%' or
           p.username ilike '%'||p_search||'%')
    order by p.created_at desc
    limit p_page_size offset v_offset
  ) t;

  return jsonb_build_object('total', v_total, 'page', p_page, 'page_size', p_page_size, 'results', v_results);
end;
$$;
revoke all on function public.get_admin_customers_paged(text, int, int) from public;
grant execute on function public.get_admin_customers_paged(text, int, int) to authenticated;
