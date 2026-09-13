-- Ports admin_views.py's AdminAssignCollectionView (:346).
create or replace function public.admin_assign_collector(p_request_id bigint, p_collector_user_id uuid)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare v_req public.pickup_requests;
begin
  if not is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from profiles where id = p_collector_user_id and role = 'collector') then
    raise exception 'Collector not found.' using errcode = 'P0002';
  end if;

  update pickup_requests set collector_id = p_collector_user_id, status = 'proposed'
  where id = p_request_id
  returning * into v_req;

  if v_req is null then
    raise exception 'Request not found.' using errcode = 'P0002';
  end if;
  return v_req;
end;
$$;
revoke all on function public.admin_assign_collector(bigint, uuid) from public;
grant execute on function public.admin_assign_collector(bigint, uuid) to authenticated;
