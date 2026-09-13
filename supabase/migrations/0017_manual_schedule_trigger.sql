-- Ports customer_views.py's ScheduleTriggerView (:480) — manual on-demand
-- trigger for one specific schedule, distinct from trigger_due_scheduled_pickups
-- (which only fires schedules that are actually due).

create or replace function public.manually_trigger_schedule(p_schedule_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare
  v_sched public.scheduled_pickups;
  v_bin_price numeric;
  v_new_status text;
  v_req public.pickup_requests;
begin
  select * into v_sched from scheduled_pickups
    where id = p_schedule_id and customer_id = auth.uid() and is_active;
  if v_sched is null then
    raise exception 'Schedule not found.' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from pickup_requests
    where source_schedule_id = p_schedule_id and created_at >= now() - interval '10 minutes'
  ) then
    raise exception 'A pickup for this schedule was already triggered recently.' using errcode = 'P0001';
  end if;

  select price into v_bin_price from bin_types where id = v_sched.bin_type_id;
  v_bin_price := coalesce(v_bin_price, 20.00);
  v_new_status := case when v_sched.assigned_collector_id is not null then 'assigned' else 'finding' end;

  insert into pickup_requests (
    customer_id, collector_id, waste_type, bin_type_id, pickup_address, pickup_lat, pickup_lng,
    price, base_price, status, source_schedule_id
  ) values (
    v_sched.customer_id, v_sched.assigned_collector_id, v_sched.waste_type, v_sched.bin_type_id,
    v_sched.pickup_address, v_sched.pickup_lat, v_sched.pickup_lng,
    v_bin_price * v_sched.num_bins, v_bin_price, v_new_status, v_sched.id
  ) returning * into v_req;

  update scheduled_pickups set last_triggered_at = now() where id = p_schedule_id;
  return v_req;
end;
$$;
revoke all on function public.manually_trigger_schedule(bigint) from public;
grant execute on function public.manually_trigger_schedule(bigint) to authenticated;
