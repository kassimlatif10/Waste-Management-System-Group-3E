-- Two gaps found while wiring investor_fleet_tab.dart:
-- 1. investor_fleet_rides_write only allowed admin — investors need to
--    register their own rides (InvestorFleetRideListCreateView lets the
--    investor do this themselves in Django, not just admin).
-- 2. profiles has no policy letting an investor see the name/phone of a
--    collector assigned to their own fleet ride (same class of RLS-blocks-
--    the-embed issue as 0016/0018/0019/0022).

drop policy investor_fleet_rides_write on public.investor_fleet_rides;
create policy investor_fleet_rides_write on public.investor_fleet_rides for all using (
  public.is_admin() or investor_id in (select id from public.investor_profiles where user_id = auth.uid())
) with check (
  public.is_admin() or investor_id in (select id from public.investor_profiles where user_id = auth.uid())
);

create policy profiles_select_related_fleet on public.profiles for select using (
  exists (
    select 1 from public.investor_fleet_rides ifr
    join public.investor_profiles ip on ip.id = ifr.investor_id
    join public.collector_profiles cp on cp.id = ifr.assigned_collector_id
    where ip.user_id = auth.uid() and cp.user_id = profiles.id
  )
);
