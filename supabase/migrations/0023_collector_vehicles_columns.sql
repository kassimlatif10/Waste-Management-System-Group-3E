-- collector_vehicles was missing several real Django CollectorVehicle
-- columns (name, vehicle_type, vehicle_number, notes, is_active) — found
-- while wiring vehicle_detail_page.dart's edit form, which needs all of
-- these.

alter table public.collector_vehicles add column if not exists name text;
alter table public.collector_vehicles add column if not exists vehicle_type text;
alter table public.collector_vehicles add column if not exists vehicle_number text;
alter table public.collector_vehicles add column if not exists notes text;
alter table public.collector_vehicles add column if not exists is_active boolean not null default true;
alter table public.collector_vehicles add column if not exists phone text;
