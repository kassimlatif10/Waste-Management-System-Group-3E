-- collector_kyc was missing middle_name/email/vehicle_number_plate/
-- vehicle_details — found while wiring collector_kyc.dart's resubmission
-- form.
alter table public.collector_kyc add column if not exists middle_name text;
alter table public.collector_kyc add column if not exists email text;
alter table public.collector_kyc add column if not exists vehicle_number_plate text;
alter table public.collector_kyc add column if not exists vehicle_details text;
