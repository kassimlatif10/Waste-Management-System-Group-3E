-- investor_fleet_rides was missing vehicle_type entirely (0007 added
-- name/vehicle_number/vehicle_photo/is_active but missed this one) —
-- found live-testing investor ride registration.
alter table public.investor_fleet_rides add column if not exists vehicle_type text;
