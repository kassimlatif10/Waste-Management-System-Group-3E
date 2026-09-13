-- Private Realtime Broadcast channel authorization for live collector
-- tracking (replaces wast/consumers.py's TrackingConsumer + its
-- _is_authorized() check). Channel topic convention: "tracking:{request_id}".
-- Only that request's customer or collector may send/receive on it.

alter table realtime.messages enable row level security;

create policy "tracking_channel_access" on realtime.messages
for select to authenticated
using (
  exists (
    select 1 from public.pickup_requests
    where 'tracking:' || id::text = realtime.topic()
      and (customer_id = auth.uid() or collector_id = auth.uid())
  )
);

create policy "tracking_channel_send" on realtime.messages
for insert to authenticated
with check (
  exists (
    select 1 from public.pickup_requests
    where 'tracking:' || id::text = realtime.topic()
      and (customer_id = auth.uid() or collector_id = auth.uid())
  )
);
