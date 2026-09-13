-- Same class of fix as 0016/0018 but for scheduled_pickups: a collector
-- assigned to a schedule needs to see that customer's name/phone.

create policy profiles_select_related_schedule on public.profiles for select using (
  exists (
    select 1 from public.scheduled_pickups sp
    where (sp.assigned_collector_id = auth.uid() and sp.customer_id = profiles.id)
       or (sp.customer_id = auth.uid() and sp.assigned_collector_id = profiles.id)
  )
);
