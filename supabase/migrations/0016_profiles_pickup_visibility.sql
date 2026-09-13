-- profiles_select_own only allows seeing your own row, which silently
-- nulled out the collector-join embed a customer needs to see their
-- assigned collector's name/phone (and vice versa) on a shared pickup
-- request — PostgREST returns null for an RLS-blocked embed rather than
-- erroring, which is why this wasn't obvious from the query itself.

create policy profiles_select_related_pickup on public.profiles for select using (
  exists (
    select 1 from public.pickup_requests pr
    where (pr.customer_id = auth.uid() and pr.collector_id = profiles.id)
       or (pr.collector_id = auth.uid() and pr.customer_id = profiles.id)
  )
);
