-- company_waste_bins was missing is_active/notes — found while wiring
-- admin_home.dart's Company Waste Bins page.
alter table public.company_waste_bins add column if not exists is_active boolean not null default true;
alter table public.company_waste_bins add column if not exists notes text;
