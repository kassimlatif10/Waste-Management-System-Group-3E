-- Extends profiles_select_related_pickup: an approved collector also needs
-- to see a customer's name/phone for 'finding' (not-yet-assigned) requests
-- in their incoming queue, matching Django's collector_views.py incoming-
-- requests payload (customer_name/customer_phone shown before acceptance).

drop policy profiles_select_related_pickup on public.profiles;

create policy profiles_select_related_pickup on public.profiles for select using (
  exists (
    select 1 from public.pickup_requests pr
    where (pr.customer_id = auth.uid() and pr.collector_id = profiles.id)
       or (pr.collector_id = auth.uid() and pr.customer_id = profiles.id)
       or (pr.status = 'finding' and pr.customer_id = profiles.id and public.is_approved_collector())
  )
);
