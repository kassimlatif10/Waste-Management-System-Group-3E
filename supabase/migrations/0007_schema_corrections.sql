-- Corrections found while re-reading the exact Django model definitions
-- for Phase 2 (fields present on the Django models but missed in 0001).

alter table public.pickup_requests add column if not exists waste_type text;
alter table public.pickup_requests add column if not exists completed_at timestamptz;

alter table public.scheduled_pickups add column if not exists waste_type text;
alter table public.scheduled_pickups add column if not exists pickup_address text;
alter table public.scheduled_pickups add column if not exists pickup_lat double precision;
alter table public.scheduled_pickups add column if not exists pickup_lng double precision;
alter table public.scheduled_pickups alter column day_of_week type text using day_of_week::text;

alter table public.investor_fleet_rides add column if not exists name text;
alter table public.investor_fleet_rides add column if not exists vehicle_number text;
alter table public.investor_fleet_rides add column if not exists vehicle_photo text;
alter table public.investor_fleet_rides add column if not exists is_active boolean not null default true;

alter table public.investor_earnings add column if not exists description text;

alter table public.collection_commissions add column if not exists payment_method text;
alter table public.collection_commissions add column if not exists paid_at timestamptz;

alter table public.collector_score_events add column if not exists note text;

alter table public.dumping_reports add column if not exists resolved_at timestamptz;

alter table public.commission_rules add column if not exists name text;
