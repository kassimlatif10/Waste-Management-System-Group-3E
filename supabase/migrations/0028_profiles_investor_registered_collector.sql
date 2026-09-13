-- profiles_select_related_fleet (0026) only covered a collector already
-- assigned to one of the investor's rides. An investor also needs to see
-- the profile of any collector they registered but haven't assigned to a
-- ride yet (collector_profiles.investor_id, a separate relationship from
-- ride assignment).

create policy profiles_select_related_registered_collector on public.profiles for select using (
  exists (
    select 1 from public.collector_profiles cp
    join public.investor_profiles ip on ip.id = cp.investor_id
    where ip.user_id = auth.uid() and cp.user_id = profiles.id
  )
);
