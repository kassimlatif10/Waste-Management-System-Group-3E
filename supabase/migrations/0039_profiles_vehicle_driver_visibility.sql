-- profiles_select_own only allows seeing your own row, which silently
-- nulled out the driver name/phone a vehicle owner needs on
-- VehicleDetailPage's "Assigned Collector" card (PostgREST returns null
-- for an RLS-blocked embed rather than erroring, same class of issue as
-- 0016_profiles_pickup_visibility.sql).

create policy profiles_select_related_vehicle_driver on public.profiles for select using (
  exists (
    select 1 from public.collector_vehicles cv
    where cv.driver_id = profiles.id
      and cv.collector_id in (select id from public.collector_profiles where user_id = auth.uid())
  )
);
