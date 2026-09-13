-- Ports AdminScheduleListView.get() (admin_views.py:913) + ScheduledPickupSerializer
-- (serializers.py:218) for admin_home.dart's Schedules page — paginated,
-- searchable, filterable by is_active/period, with computed status,
-- active_request_id and next_pickup_datetime (reusing get_next_pickup_datetime
-- from 0014_scheduled_jobs.sql).

create or replace function public.get_admin_schedules_paged(
  p_search text default '', p_is_active text default 'true', p_period text default 'all',
  p_page int default 1, p_page_size int default 20
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_total int;
  v_results jsonb;
  v_offset int := greatest(p_page - 1, 0) * p_page_size;
  v_since timestamptz;
begin
  if not is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  v_since := case p_period
    when 'today' then date_trunc('day', now())
    when 'yesterday' then date_trunc('day', now()) - interval '1 day'
    when 'week' then date_trunc('day', now()) - ((extract(isodow from now())::int - 1) || ' days')::interval
    else '1970-01-01'::timestamptz
  end;

  select count(*) into v_total
  from scheduled_pickups sp
  join profiles c on c.id = sp.customer_id
  where sp.created_at >= v_since
    and (p_is_active = 'all' or sp.is_active = (p_is_active = 'true'))
    and (p_search = '' or
         c.first_name ilike '%'||p_search||'%' or
         c.last_name ilike '%'||p_search||'%' or
         sp.pickup_address ilike '%'||p_search||'%');

  select coalesce(jsonb_agg(row_data), '[]'::jsonb) into v_results
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
      'assigned_collector_id', sp.assigned_collector_id,
      'assigned_collector_name', case when col.id is not null then
        coalesce(nullif(trim(coalesce(col.first_name,'') || ' ' || coalesce(col.last_name,'')), ''), col.username, 'Collector')
        else null end,
      'next_pickup_datetime', get_next_pickup_datetime(sp.day_of_week, sp.frequency, sp.pickup_time),
      'bin_type_id', sp.bin_type_id,
      'bin_type_name', bt.display_name,
      'bin_type_price', bt.price,
      'num_bins', sp.num_bins,
      'status', coalesce(active_pr.status, 'pending'),
      'active_request_id', active_pr.id,
      'source', case when sp.created_by_id is not null then 'admin' else 'customer' end,
      'branch_name', br.name
    ) as row_data,
    sp.created_at
    from scheduled_pickups sp
    join profiles c on c.id = sp.customer_id
    left join profiles col on col.id = sp.assigned_collector_id
    left join bin_types bt on bt.id = sp.bin_type_id
    left join branches br on br.id = sp.branch_id
    left join lateral (
      select pr.id, pr.status from pickup_requests pr
      where pr.source_schedule_id = sp.id and pr.status not in ('completed','cancelled')
      order by pr.created_at desc limit 1
    ) active_pr on true
    where sp.created_at >= v_since
      and (p_is_active = 'all' or sp.is_active = (p_is_active = 'true'))
      and (p_search = '' or
           c.first_name ilike '%'||p_search||'%' or
           c.last_name ilike '%'||p_search||'%' or
           sp.pickup_address ilike '%'||p_search||'%')
    order by sp.created_at desc
    limit p_page_size offset v_offset
  ) t;

  return jsonb_build_object('total', v_total, 'page', p_page, 'page_size', p_page_size, 'results', v_results);
end;
$$;
revoke all on function public.get_admin_schedules_paged(text, text, text, int, int) from public;
grant execute on function public.get_admin_schedules_paged(text, text, text, int, int) to authenticated;
