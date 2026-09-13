-- Ports collector_views.py's _schedule_payload() (:62) — the collector
-- schedules screen buckets schedules into active/completed by a computed
-- schedule_status (upcoming/ready/active/completed) based on how close
-- next_pickup_datetime is, not by the schedule's own is_active flag alone.
-- SupabaseService.fetchAssignedSchedules() previously returned raw rows
-- with no such field, so every schedule silently defaulted to 'upcoming'
-- on the Flutter side and the active/completed buckets never populated.

create or replace function public.get_collector_assigned_schedules()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_results jsonb;
begin
  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb) into v_results
  from (
    select jsonb_build_object(
      'id', sp.id,
      'waste_type', sp.waste_type,
      'pickup_address', sp.pickup_address,
      'pickup_lat', sp.pickup_lat,
      'pickup_lng', sp.pickup_lng,
      'frequency', sp.frequency,
      'day_of_week', sp.day_of_week,
      'pickup_time', sp.pickup_time,
      'is_active', sp.is_active,
      'collector_confirmed', sp.collector_confirmed,
      'created_at', sp.created_at,
      'customer_id', sp.customer_id,
      'customer_name', coalesce(nullif(trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')), ''), c.username, 'Customer'),
      'customer_phone', c.phone,
      'bin_type_id', sp.bin_type_id,
      'num_bins', sp.num_bins,
      'next_pickup_datetime', nd.next_dt,
      'seconds_until_pickup', su.seconds_until,
      'schedule_status', case
        when not sp.is_active then 'completed'
        when nd.next_dt is null then 'upcoming'
        when su.seconds_until > 15 * 60 then 'upcoming'
        when su.seconds_until > 0 then 'ready'
        when su.seconds_until >= -60 * 60 then (case when sp.collector_confirmed then 'active' else 'ready' end)
        else 'completed'
      end
    ) as row_data,
    sp.created_at
    from scheduled_pickups sp
    join profiles c on c.id = sp.customer_id
    cross join lateral (
      select get_next_pickup_datetime(sp.day_of_week, sp.frequency, sp.pickup_time) as next_dt
    ) nd
    cross join lateral (
      select extract(epoch from (nd.next_dt - now()))::int as seconds_until
    ) su
    where sp.assigned_collector_id = auth.uid()
  ) t;

  return v_results;
end;
$$;
revoke all on function public.get_collector_assigned_schedules() from public;
grant execute on function public.get_collector_assigned_schedules() to authenticated;
