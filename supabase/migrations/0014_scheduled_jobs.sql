-- Phase 5: scheduled pickups + reminders, porting wast/tasks.py's
-- trigger_scheduled_pickups and send_schedule_reminders (Celery Beat,
-- every 2min/1min) as pg_cron jobs calling SQL functions. Ghana has no DST
-- (Africa/Accra = UTC year-round), so timestamptz arithmetic needs no
-- timezone conversion beyond what Postgres already does in UTC.

create extension if not exists pg_cron;

-- Ports ScheduledPickup.get_next_pickup_datetime() (models.py:289) exactly,
-- including its biweekly handling (which is a no-op in the original code
-- too — days_ahead from a %7 is always 0-6, so the "0 < days_ahead < 14"
-- branch never actually extends by a week; replicated as-is for parity
-- rather than silently "fixing" behavior nobody asked to change).
create or replace function public.get_next_pickup_datetime(p_day_of_week text, p_frequency text, p_pickup_time time)
returns timestamptz
language plpgsql immutable as $$
declare
  v_day_map jsonb := '{"monday":0,"tuesday":1,"wednesday":2,"thursday":3,"friday":4,"saturday":5,"sunday":6}';
  v_target_weekday int := coalesce((v_day_map->>p_day_of_week)::int, 0);
  v_now timestamptz := now();
  v_now_weekday int := extract(isodow from v_now)::int - 1; -- Mon=0..Sun=6, matches Python's weekday()
  v_days_ahead int := (v_target_weekday - v_now_weekday + 7) % 7;
  v_candidate timestamptz;
begin
  if p_frequency = 'biweekly' and v_days_ahead > 0 and v_days_ahead < 14 then
    v_days_ahead := v_days_ahead; -- see comment above: intentionally a no-op, matches Django
  end if;

  if v_days_ahead = 0 then
    v_candidate := date_trunc('day', v_now) + p_pickup_time;
    if v_candidate <= v_now then
      v_days_ahead := 7;
    end if;
  end if;

  return date_trunc('day', v_now) + (v_days_ahead || ' days')::interval + p_pickup_time;
end;
$$;

create or replace function public.trigger_due_scheduled_pickups()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_sched record;
  v_next timestamptz;
  v_bin_price numeric;
  v_new_status text;
  v_triggered int := 0;
begin
  for v_sched in select * from scheduled_pickups where is_active loop
    v_next := get_next_pickup_datetime(v_sched.day_of_week, v_sched.frequency, v_sched.pickup_time);

    if not (v_next - interval '10 minutes' <= v_now and v_now < v_next) then
      continue;
    end if;
    if v_sched.last_triggered_at is not null and (extract(epoch from (v_now - v_sched.last_triggered_at)) / 60) < 10 then
      continue;
    end if;
    if exists (select 1 from pickup_requests where source_schedule_id = v_sched.id and created_at::date = v_now::date) then
      continue;
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
    );

    update scheduled_pickups set last_triggered_at = v_now where id = v_sched.id;

    insert into notifications (user_id, title, body, notification_type) values (
      v_sched.customer_id, 'Scheduled Pickup Started',
      'Your scheduled waste collection is now active.' ||
        (case when v_sched.assigned_collector_id is not null then ' A collector has been assigned.' else ' We are finding a collector for you.' end),
      'schedule'
    );
    if v_sched.assigned_collector_id is not null then
      insert into notifications (user_id, title, body, notification_type) values (
        v_sched.assigned_collector_id, 'Scheduled Pickup Due',
        'A scheduled pickup is now active. Go to ' || coalesce(v_sched.pickup_address, 'the pickup location') || '.',
        'schedule'
      );
    end if;

    v_triggered := v_triggered + 1;
  end loop;
  return v_triggered;
end;
$$;

create or replace function public.send_due_schedule_reminders()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_minutes int;
  v_sched record;
  v_next timestamptz;
  v_notified int := 0;
begin
  foreach v_minutes in array array[15, 5] loop
    for v_sched in select * from scheduled_pickups where is_active loop
      v_next := get_next_pickup_datetime(v_sched.day_of_week, v_sched.frequency, v_sched.pickup_time);
      if v_next < v_now + (v_minutes || ' minutes')::interval - interval '30 seconds'
         or v_next > v_now + (v_minutes || ' minutes')::interval + interval '30 seconds' then
        continue;
      end if;

      insert into notifications (user_id, title, body, notification_type) values (
        v_sched.customer_id, 'Pickup in ' || v_minutes || ' minutes',
        'Your waste collection is scheduled in ' || v_minutes || ' minutes.', 'schedule'
      );
      if v_sched.assigned_collector_id is not null then
        insert into notifications (user_id, title, body, notification_type) values (
          v_sched.assigned_collector_id, 'Pickup in ' || v_minutes || ' minutes',
          'A scheduled pickup is in ' || v_minutes || ' minutes.', 'schedule'
        );
      end if;
      v_notified := v_notified + 1;
    end loop;
  end loop;
  return v_notified;
end;
$$;

select cron.schedule('trigger-scheduled-pickups', '*/2 * * * *', $$select public.trigger_due_scheduled_pickups()$$);
select cron.schedule('send-schedule-reminders', '* * * * *', $$select public.send_due_schedule_reminders()$$);
