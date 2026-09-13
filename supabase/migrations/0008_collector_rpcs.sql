-- Phase 2: collector accept/decline/complete RPCs. These port
-- wast/collector_views.py's AcceptRequestView (:406), DeclineRequestView
-- (:545), MarkOnWayView/MarkArrivedView (:591/:622), and CompletePickupView
-- (:653) as SECURITY DEFINER Postgres functions — atomic, single-transaction,
-- exactly mirroring Django's transaction.atomic() blocks.

-- ── Helpers (ported from wast/models.py + wast/services.py) ────────────────

create or replace function public.haversine_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371.0 * 2 * asin(sqrt(
    sin(radians(lat2 - lat1) / 2) ^ 2
    + cos(radians(lat1)) * cos(radians(lat2)) * sin(radians(lng2 - lng1) / 2) ^ 2
  ))
$$;

create or replace function public.calculate_trip_price(base_price numeric, distance_km double precision)
returns numeric language sql immutable as $$
  select greatest(20, least(120, ceil((base_price + distance_km * 3.0) / 5.0) * 5))::numeric
$$;

create or replace function public.collector_daily_limit(credit_score int)
returns int language sql immutable as $$
  select case
    when credit_score >= 100 then null
    when credit_score >= 70 then 20
    when credit_score >= 50 then 5
    when credit_score >= 35 then 2
    else 1
  end
$$;

create or replace function public.collector_requests_received_today(p_collector_id uuid)
returns int language sql stable as $$
  select count(*)::int from public.pickup_requests
  where collector_id = p_collector_id
    and status in ('proposed','assigned','on_way','arrived','completed')
    and created_at >= date_trunc('day', now())
$$;

-- ── accept_pickup_request ───────────────────────────────────────────────────

create or replace function public.accept_pickup_request(p_request_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_cp public.collector_profiles;
  v_req public.pickup_requests;
  v_daily_limit int;
  v_base numeric;
  v_dist_km double precision;
  v_total numeric;
begin
  select * into v_cp from collector_profiles where user_id = v_uid;
  if v_cp is null or not v_cp.is_approved then
    raise exception 'Your account is pending admin approval.' using errcode = 'P0001';
  end if;
  if not v_cp.is_online then
    raise exception 'You must be online to accept requests.' using errcode = 'P0001';
  end if;
  if v_cp.unpaid_commission >= 150 then
    raise exception 'You owe GHS % to Bɔla Aba. Settle your commission balance to receive new pickups.', v_cp.unpaid_commission using errcode = 'P0001';
  end if;

  v_daily_limit := collector_daily_limit(v_cp.credit_score);
  if v_daily_limit is not null and collector_requests_received_today(v_uid) >= v_daily_limit then
    raise exception 'Daily pickup limit reached (%) based on your credit score (%).', v_daily_limit, v_cp.credit_score using errcode = 'P0001';
  end if;

  select * into v_req from pickup_requests where id = p_request_id for update;
  if v_req is null then
    raise exception 'Request not found.' using errcode = 'P0002';
  end if;

  -- Case 1: confirming a proposed assignment already addressed to this collector
  if v_req.status = 'proposed' and v_req.collector_id = v_uid then
    update pickup_requests set
      status = 'assigned',
      collector_start_lat = v_cp.current_lat,
      collector_start_lng = v_cp.current_lng
    where id = p_request_id
    returning * into v_req;
    return v_req;
  end if;

  -- Case 2: manual claim from the finding queue
  if v_req.status != 'finding' then
    raise exception 'Request is no longer available.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from pickup_requests
    where collector_id = v_uid and status in ('proposed','assigned','on_way','arrived')
  ) then
    raise exception 'You already have an active pickup.' using errcode = 'P0001';
  end if;

  select price into v_base from bin_types where id = v_req.bin_type_id;
  if v_base is null then v_base := coalesce(v_req.base_price, 20); end if;

  if v_cp.current_lat is not null and v_cp.current_lng is not null and v_req.pickup_lat is not null and v_req.pickup_lng is not null then
    v_dist_km := haversine_km(v_cp.current_lat, v_cp.current_lng, v_req.pickup_lat, v_req.pickup_lng);
    v_total := calculate_trip_price(v_base, v_dist_km);
  else
    v_dist_km := 0;
    v_total := v_base;
  end if;

  update pickup_requests set
    collector_id = v_uid,
    status = 'proposed',
    base_price = v_base,
    distance_km = v_dist_km,
    distance_fee = greatest(0, v_total - v_base),
    price = v_total,
    collector_start_lat = v_cp.current_lat,
    collector_start_lng = v_cp.current_lng
  where id = p_request_id
  returning * into v_req;

  return v_req;
end;
$$;
revoke all on function public.accept_pickup_request(bigint) from public;
grant execute on function public.accept_pickup_request(bigint) to authenticated;

-- ── decline_pickup_request ──────────────────────────────────────────────────

create or replace function public.decline_pickup_request(p_request_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_req public.pickup_requests;
  v_cp public.collector_profiles;
  v_new_score int;
begin
  select * into v_req from pickup_requests where id = p_request_id and collector_id = v_uid for update;
  if v_req is null then
    raise exception 'Request not found.' using errcode = 'P0002';
  end if;
  if v_req.status != 'proposed' then
    raise exception 'Can only decline a proposed request.' using errcode = 'P0001';
  end if;

  update pickup_requests set
    declined_collector_ids = case
      when declined_collector_ids @> to_jsonb(v_uid::text) then declined_collector_ids
      else declined_collector_ids || to_jsonb(v_uid::text)
    end,
    collector_id = null,
    status = 'finding'
  where id = p_request_id
  returning * into v_req;

  select * into v_cp from collector_profiles where user_id = v_uid;
  if v_cp is not null then
    v_new_score := greatest(0, v_cp.credit_score - 5);
    update collector_profiles set credit_score = v_new_score where id = v_cp.id;
    insert into collector_score_events (collector_id, pickup_request_id, event_type, points_change, score_after, note)
    values (v_cp.id, p_request_id, 'rejection', -5, v_new_score, 'Declined a customer request');
  end if;

  return v_req;
end;
$$;
revoke all on function public.decline_pickup_request(bigint) from public;
grant execute on function public.decline_pickup_request(bigint) to authenticated;

-- ── mark_on_way / mark_arrived (simple guarded transitions) ─────────────────

create or replace function public.mark_pickup_on_way(p_request_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare v_req public.pickup_requests;
begin
  update pickup_requests set status = 'on_way'
  where id = p_request_id and collector_id = auth.uid() and status = 'assigned'
  returning * into v_req;
  if v_req is null then
    raise exception 'Cannot mark on_way from the current status.' using errcode = 'P0001';
  end if;
  return v_req;
end;
$$;
revoke all on function public.mark_pickup_on_way(bigint) from public;
grant execute on function public.mark_pickup_on_way(bigint) to authenticated;

create or replace function public.mark_pickup_arrived(p_request_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare v_req public.pickup_requests;
begin
  update pickup_requests set status = 'arrived'
  where id = p_request_id and collector_id = auth.uid() and status in ('on_way','assigned')
  returning * into v_req;
  if v_req is null then
    raise exception 'Cannot mark arrived from the current status.' using errcode = 'P0001';
  end if;
  return v_req;
end;
$$;
revoke all on function public.mark_pickup_arrived(bigint) from public;
grant execute on function public.mark_pickup_arrived(bigint) to authenticated;

-- ── complete_pickup (the atomic commission + investor-accrual block) ───────

create or replace function public.complete_pickup(p_request_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_req public.pickup_requests;
  v_cp public.collector_profiles;
  v_price numeric;
  v_commission numeric;
  v_rule_id bigint;
  v_comm_status text;
  v_credited numeric;
  v_fleet_ride public.investor_fleet_rides;
  v_investor_share numeric;
begin
  select * into v_req from pickup_requests where id = p_request_id and collector_id = v_uid for update;
  if v_req is null then
    raise exception 'Request not found.' using errcode = 'P0002';
  end if;
  if v_req.status != 'arrived' then
    raise exception 'Cannot complete from the current status.' using errcode = 'P0001';
  end if;

  update pickup_requests set status = 'completed', completed_at = now()
  where id = p_request_id returning * into v_req;

  select * into v_cp from collector_profiles where user_id = v_uid for update;
  v_price := coalesce(v_req.price, 0);

  if v_cp.is_company_collector then
    v_commission := 0;
    v_rule_id := null;
    v_comm_status := 'paid';
    v_credited := v_price;
  else
    select id into v_rule_id from commission_rules
      where is_active and v_price >= min_amount and (max_amount is null or v_price <= max_amount)
      order by min_amount limit 1;
    if v_rule_id is not null then
      select case when commission_type = 'percentage'
        then round(v_price * value / 100, 2)
        else least(value, v_price) end
      into v_commission from commission_rules where id = v_rule_id;
    else
      select round(v_price * commission_rate / 100, 2) into v_commission from system_config where id = 1;
    end if;
    v_comm_status := 'owed';
    v_credited := v_price;
    update collector_profiles set unpaid_commission = unpaid_commission + v_commission where id = v_cp.id;
  end if;

  insert into collection_commissions (pickup_request_id, rule_id, collection_amount, commission_amount, payment_method, status)
  values (p_request_id, v_rule_id, v_price, v_commission, 'cash', v_comm_status)
  on conflict (pickup_request_id) do nothing;

  update collector_profiles set
    account_balance = account_balance + v_credited,
    today_earnings = today_earnings + v_credited,
    weekly_earnings = weekly_earnings + v_credited,
    total_earnings = total_earnings + v_credited,
    total_collections = total_collections + 1
  where id = v_cp.id;

  -- Investor fleet-ride auto-accrual
  select * into v_fleet_ride from investor_fleet_rides
    where assigned_collector_id = v_cp.id and is_active limit 1;
  if v_fleet_ride is not null then
    v_investor_share := round(v_price * v_fleet_ride.service_fee_percent / 100, 2);
    if v_investor_share > 0 then
      insert into investor_earnings (investor_id, amount, description, earning_type, date)
      values (v_fleet_ride.investor_id, v_investor_share, 'Collection #' || p_request_id || ' — ' || v_fleet_ride.vehicle_type, 'daily', current_date);
      update investor_fleet_rides set
        total_collections = total_collections + 1,
        total_revenue = total_revenue + v_price
      where id = v_fleet_ride.id;
    end if;
  end if;

  return v_req;
end;
$$;
revoke all on function public.complete_pickup(bigint) from public;
grant execute on function public.complete_pickup(bigint) to authenticated;

-- Collector's "finding" queue and their own assignments, live — replaces the 5s poll.
alter publication supabase_realtime add table public.collector_profiles;
