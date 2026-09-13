-- Same class of fix as 0016/0018/0019 but for support tickets: a ticket
-- owner needs to see the name of whoever replied (e.g. an admin), and an
-- assigned admin needs to see the ticket owner's name.

create policy profiles_select_related_ticket on public.profiles for select using (
  exists (
    select 1 from public.support_messages sm join public.support_tickets st on st.id = sm.ticket_id
    where sm.sender_id = profiles.id
      and (st.user_id = auth.uid() or st.assigned_admin_id = auth.uid())
  )
  or exists (
    select 1 from public.support_tickets st
    where st.user_id = profiles.id and st.assigned_admin_id = auth.uid()
  )
);
