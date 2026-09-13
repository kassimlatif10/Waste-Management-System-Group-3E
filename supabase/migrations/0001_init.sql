-- WastePick / Bɔla Aba — Supabase schema (Phase 0)
-- Derived from the Django models in wastbankend/wast/models.py and
-- accounts/models.py. Replaces Django's auto-generated tables (dropped in
-- Phase 6) with a Supabase-native schema: auth.users + profiles instead of
-- a custom user model, RLS instead of DRF permission classes.

create extension if not exists postgis;

-- ============================================================================
-- PROFILES (merges accounts.CustomUser + wast.UserProfile)
-- ============================================================================

create type user_role as enum ('customer','collector','staff','admin','super_admin','investor');

create table public.branches (
  id bigint generated always as identity primary key,
  name text not null,
  region text,
  country text,
  address text,
  lat double precision,
  lng double precision,
  service_radius_km numeric,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  email text,
  phone text unique,
  first_name text,
  last_name text,
  role user_role not null default 'customer',
  branch_id bigint references public.branches(id) on delete set null,
  password_set boolean not null default false,
  is_staff boolean not null default false,
  is_superuser boolean not null default false,
  is_active boolean not null default true,
  profile_image text,
  bio text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.otp_verifications (
  id bigint generated always as identity primary key,
  phone text not null,
  otp_code text not null,
  purpose text not null check (purpose in ('password_reset','verification')),
  expires_at timestamptz not null,
  is_used boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- CATALOG TABLES
-- ============================================================================

create table public.waste_types (
  id bigint generated always as identity primary key,
  key text unique not null,
  label text not null,
  base_price numeric not null default 0,
  icon text,
  color_hex text,
  is_active boolean not null default true,
  sort_order int not null default 0
);

create table public.bin_types (
  id bigint generated always as identity primary key,
  waste_type_id bigint not null references public.waste_types(id) on delete cascade,
  name text not null,
  display_name text,
  price numeric not null default 0,
  unique (waste_type_id, name)
);

create table public.system_config (
  id int primary key default 1 check (id = 1),
  commission_rate numeric not null default 18
);
insert into public.system_config (id, commission_rate) values (1, 18);

create table public.commission_rules (
  id bigint generated always as identity primary key,
  min_amount numeric not null,
  max_amount numeric,
  commission_type text not null check (commission_type in ('percentage','fixed')),
  value numeric not null,
  is_active boolean not null default true
);

-- ============================================================================
-- INVESTOR / COLLECTOR (circular FK — collector_profiles.investor_id and
-- investor_fleet_rides.assigned_collector_id — resolved with ALTER TABLE below)
-- ============================================================================

create table public.investor_profiles (
  id bigint generated always as identity primary key,
  user_id uuid unique not null references public.profiles(id) on delete cascade,
  company_name text,
  location text,
  location_latitude numeric,
  location_longitude numeric,
  investment_amount numeric,
  roi_percentage numeric,
  yearly_profit_margin numeric,
  id_card_front text,
  id_card_back text,
  created_at timestamptz not null default now()
);

create table public.collector_profiles (
  id bigint generated always as identity primary key,
  user_id uuid unique not null references public.profiles(id) on delete cascade,
  vehicle_type text,
  is_online boolean not null default false,
  is_approved boolean not null default false,
  rating numeric not null default 0,
  rating_count int not null default 0,
  account_balance numeric not null default 0,
  today_earnings numeric not null default 0,
  weekly_earnings numeric not null default 0,
  total_earnings numeric not null default 0,
  unpaid_commission numeric not null default 0,
  total_collections int not null default 0,
  credit_score int not null default 100,
  current_lat double precision,
  current_lng double precision,
  location geography(Point, 4326),
  investor_id bigint references public.investor_profiles(id) on delete set null,
  registered_by_investor boolean not null default false,
  is_company_collector boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index collector_profiles_location_idx on public.collector_profiles using gist (location);

create table public.investor_fleet_rides (
  id bigint generated always as identity primary key,
  investor_id bigint not null references public.investor_profiles(id) on delete cascade,
  assigned_collector_id bigint references public.collector_profiles(id) on delete set null,
  management_mode text check (management_mode in ('bola_aba','self')),
  assignment_source text,
  current_lat double precision,
  current_lng double precision,
  total_collections int not null default 0,
  total_revenue numeric not null default 0,
  service_fee_percent numeric not null default 0,
  created_at timestamptz not null default now()
);

create table public.investor_earnings (
  id bigint generated always as identity primary key,
  investor_id bigint not null references public.investor_profiles(id) on delete cascade,
  amount numeric not null,
  earning_type text not null check (earning_type in ('daily','monthly','dividend','payout')),
  date date not null,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- VEHICLES / KYC
-- ============================================================================

create table public.collector_vehicles (
  id bigint generated always as identity primary key,
  collector_id bigint references public.collector_profiles(id) on delete cascade,
  driver_id uuid references public.profiles(id) on delete set null,
  vehicle_photo text,
  needs_admin_approval boolean not null default false,
  is_default boolean not null default false,
  total_collections int not null default 0,
  total_earnings numeric not null default 0,
  created_at timestamptz not null default now()
);

create table public.vehicle_driver_registrations (
  id bigint generated always as identity primary key,
  vehicle_id bigint unique not null references public.collector_vehicles(id) on delete cascade,
  registered_by_id uuid references public.profiles(id) on delete set null,
  driver_user_id uuid references public.profiles(id) on delete set null,
  docs jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table public.collector_kyc (
  id bigint generated always as identity primary key,
  user_id uuid unique not null references public.profiles(id) on delete cascade,
  ghana_card_number text,
  license_number text,
  kyc_status text not null default 'pending' check (kyc_status in ('pending','under_review','approved','rejected','suspended')),
  reviewed_by_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.kyc_documents (
  id bigint generated always as identity primary key,
  kyc_id bigint not null references public.collector_kyc(id) on delete cascade,
  document_type text not null check (document_type in ('ghana_card_front','ghana_card_back','selfie','proof_of_address','vehicle_photo','license_front','license_back')),
  file text not null,
  unique (kyc_id, document_type)
);

create table public.collector_score_events (
  id bigint generated always as identity primary key,
  collector_id bigint not null references public.collector_profiles(id) on delete cascade,
  pickup_request_id bigint,
  event_type text not null check (event_type in ('cancellation','rejection','missed_schedule','late_arrival','good_rating','manual')),
  points_change int not null,
  score_after int not null,
  created_at timestamptz not null default now()
);

create table public.credit_score_actions (
  id bigint generated always as identity primary key,
  collector_id bigint not null references public.collector_profiles(id) on delete cascade,
  action_type text not null check (action_type in ('share_collector','share_customer','rate_app','share_rate')),
  created_at timestamptz not null default now(),
  unique (collector_id, action_type)
);

-- ============================================================================
-- CORE: PICKUP REQUESTS / SCHEDULES
-- ============================================================================

create table public.scheduled_pickups (
  id bigint generated always as identity primary key,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  assigned_collector_id uuid references public.profiles(id) on delete set null,
  created_by_id uuid references public.profiles(id) on delete set null,
  branch_id bigint references public.branches(id) on delete set null,
  bin_type_id bigint references public.bin_types(id) on delete set null,
  frequency text not null check (frequency in ('weekly','biweekly','monthly')),
  day_of_week int,
  pickup_time time,
  num_bins int not null default 1,
  is_active boolean not null default true,
  collector_confirmed boolean not null default false,
  last_triggered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pickup_requests (
  id bigint generated always as identity primary key,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  collector_id uuid references public.profiles(id) on delete set null,
  bin_type_id bigint references public.bin_types(id) on delete set null,
  vehicle_id bigint references public.collector_vehicles(id) on delete set null,
  source_schedule_id bigint references public.scheduled_pickups(id) on delete set null,
  status text not null default 'finding' check (status in ('finding','proposed','assigned','on_way','arrived','completed','cancelled')),
  price numeric,
  base_price numeric,
  distance_km numeric,
  distance_fee numeric,
  declined_collector_ids jsonb not null default '[]',
  customer_rating int,
  rating_comment text,
  pickup_address text,
  pickup_lat double precision,
  pickup_lng double precision,
  destination_address text,
  destination_lat double precision,
  destination_lng double precision,
  collector_start_lat double precision,
  collector_start_lng double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index pickup_requests_customer_idx on public.pickup_requests (customer_id);
create index pickup_requests_collector_idx on public.pickup_requests (collector_id);
create index pickup_requests_status_idx on public.pickup_requests (status);

alter table public.collector_score_events
  add constraint collector_score_events_pickup_request_fkey
  foreign key (pickup_request_id) references public.pickup_requests(id) on delete set null;

create table public.collection_commissions (
  id bigint generated always as identity primary key,
  pickup_request_id bigint unique not null references public.pickup_requests(id) on delete cascade,
  rule_id bigint references public.commission_rules(id) on delete set null,
  collection_amount numeric not null,
  commission_amount numeric not null,
  status text not null default 'owed' check (status in ('owed','paid','waived')),
  created_at timestamptz not null default now()
);

-- ============================================================================
-- MISC: notifications, addresses, reports, payments, support, FCM
-- ============================================================================

create table public.saved_addresses (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text,
  address text,
  lat double precision,
  lng double precision
);

create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  body text,
  notification_type text check (notification_type in ('request','payment','system','schedule')),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.dumping_reports (
  id bigint generated always as identity primary key,
  reported_by_id uuid not null references public.profiles(id) on delete cascade,
  location text,
  lat double precision,
  lng double precision,
  description text,
  photo text,
  status text not null default 'pending' check (status in ('pending','investigating','resolved')),
  created_at timestamptz not null default now()
);

create table public.payment_methods (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  payment_type text not null check (payment_type in ('mobile_money','bank','card')),
  details jsonb not null default '{}',
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.withdrawal_requests (
  id bigint generated always as identity primary key,
  collector_id uuid not null references public.profiles(id) on delete cascade,
  payment_method_id bigint references public.payment_methods(id) on delete set null,
  amount numeric not null,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  created_at timestamptz not null default now()
);

create table public.fcm_tokens (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text unique not null,
  created_at timestamptz not null default now()
);

create table public.company_waste_bins (
  id bigint generated always as identity primary key,
  name text,
  size text,
  location text,
  lat double precision,
  lng double precision,
  monthly_subscription numeric,
  assigned_collector_id uuid references public.profiles(id) on delete set null
);

create table public.support_tickets (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_admin_id uuid references public.profiles(id) on delete set null,
  category text check (category in ('support','complaint','feedback')),
  status text not null default 'open' check (status in ('open','assigned','resolved')),
  needs_human boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.support_messages (
  id bigint generated always as identity primary key,
  ticket_id bigint not null references public.support_tickets(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message text,
  is_auto_reply boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- updated_at trigger helper (applied where the table has the column)
-- ============================================================================

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['branches','profiles','collector_profiles','pickup_requests','scheduled_pickups','collector_kyc','support_tickets']
  loop
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at();', t);
  end loop;
end $$;

-- ============================================================================
-- Storage buckets
-- ============================================================================

insert into storage.buckets (id, name, public) values
  ('kyc-documents', 'kyc-documents', false),
  ('vehicle-photos', 'vehicle-photos', false),
  ('profile-images', 'profile-images', true),
  ('dump-report-photos', 'dump-report-photos', false),
  ('investor-id-cards', 'investor-id-cards', false)
on conflict (id) do nothing;
