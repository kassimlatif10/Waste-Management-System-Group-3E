-- Realtime Broadcast private-channel authorization needs ownership of
-- realtime.messages that isn't grantable on this project (confirmed via
-- direct connection, the Management API, AND the Dashboard SQL Editor —
-- all three hit "must be owner of table messages"). Pivoting live collector
-- location to ride the same mechanism already proven working for status
-- updates: Postgres Changes on pickup_requests, which already has correct
-- RLS (customer_id = auth.uid() or collector_id = auth.uid()) from Phase 1.
-- One subscription now covers both status AND location — simpler than the
-- original two-mechanism design, not just a workaround.

alter table public.pickup_requests add column if not exists collector_current_lat double precision;
alter table public.pickup_requests add column if not exists collector_current_lng double precision;
