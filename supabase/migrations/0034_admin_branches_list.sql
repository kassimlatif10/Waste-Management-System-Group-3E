-- Ports BranchSerializer (serializers.py:8) for admin_home.dart's Branches
-- page — each branch needs admin_count and a nested assigned_admin object
-- (the first role='admin' profile on that branch), which isn't a plain
-- PostgREST select+embed since only one match should be picked.

create or replace function public.get_admin_branches_list()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_results jsonb;
begin
  if not is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(row_data order by name), '[]'::jsonb) into v_results
  from (
    select jsonb_build_object(
      'id', b.id,
      'name', b.name,
      'region', b.region,
      'country', b.country,
      'address', b.address,
      'lat', b.lat,
      'lng', b.lng,
      'service_radius_km', b.service_radius_km,
      'is_active', b.is_active,
      'created_at', b.created_at,
      'admin_count', (select count(*) from profiles p where p.branch_id = b.id and p.role = 'admin'),
      'assigned_admin', (
        select jsonb_build_object(
          'id', p.id,
          'name', coalesce(nullif(trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,'')), ''), p.username, 'Admin'),
          'phone', p.phone,
          'email', p.email
        )
        from profiles p where p.branch_id = b.id and p.role = 'admin'
        order by p.created_at limit 1
      )
    ) as row_data,
    b.name
    from branches b
  ) t;

  return v_results;
end;
$$;
revoke all on function public.get_admin_branches_list() from public;
grant execute on function public.get_admin_branches_list() to authenticated;
