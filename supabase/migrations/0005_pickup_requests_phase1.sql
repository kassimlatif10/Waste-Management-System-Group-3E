-- Phase 1: duplicate-active-request guard (mirrors the check in Django's
-- PickupRequestListCreateView.post) + enabling Realtime on pickup_requests
-- so the customer's 3s poll can be replaced by a live subscription.

create or replace function public.check_no_duplicate_active_request()
returns trigger language plpgsql as $$
begin
  if exists (
    select 1 from public.pickup_requests
    where customer_id = new.customer_id
      and status not in ('completed', 'cancelled')
  ) then
    raise exception 'You already have an active pickup request' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger no_duplicate_active_request
  before insert on public.pickup_requests
  for each row execute function public.check_no_duplicate_active_request();

alter publication supabase_realtime add table public.pickup_requests;
