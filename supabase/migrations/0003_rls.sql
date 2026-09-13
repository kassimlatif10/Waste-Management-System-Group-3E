-- Row Level Security — replaces Django's DRF permission classes
-- (wast/permissions.py) with declarative per-row policies.

create or replace function public.jwt_role() returns text
language sql stable as $$ select coalesce(auth.jwt() ->> 'app_role', 'customer') $$;

create or replace function public.is_admin() returns boolean
language sql stable as $$ select public.jwt_role() in ('staff','admin','super_admin') $$;

create or replace function public.is_admin_or_above() returns boolean
language sql stable as $$ select public.jwt_role() in ('admin','super_admin') $$;

create or replace function public.is_super_admin() returns boolean
language sql stable as $$ select public.jwt_role() = 'super_admin' $$;

create or replace function public.is_approved_collector() returns boolean
language sql stable as $$
  select exists (
    select 1 from public.collector_profiles
    where user_id = auth.uid() and is_approved
  )
$$;

-- profiles: everyone can read their own row + admins read all; only the
-- owner (or, for role/branch, an admin) can update.
alter table public.profiles enable row level security;
create policy profiles_select_own on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy profiles_update_own on public.profiles for update using (id = auth.uid() or public.is_admin());
create policy profiles_insert_self on public.profiles for insert with check (id = auth.uid());

-- Catalog tables: public read for any authenticated user, admin-only write.
alter table public.branches enable row level security;
create policy branches_select_all on public.branches for select using (auth.role() = 'authenticated');
create policy branches_write_admin on public.branches for all using (public.is_admin()) with check (public.is_admin());

alter table public.waste_types enable row level security;
create policy waste_types_select_all on public.waste_types for select using (auth.role() = 'authenticated');
create policy waste_types_write_admin on public.waste_types for all using (public.is_admin()) with check (public.is_admin());

alter table public.bin_types enable row level security;
create policy bin_types_select_all on public.bin_types for select using (auth.role() = 'authenticated');
create policy bin_types_write_admin on public.bin_types for all using (public.is_admin()) with check (public.is_admin());

alter table public.system_config enable row level security;
create policy system_config_select_all on public.system_config for select using (auth.role() = 'authenticated');
create policy system_config_write_admin on public.system_config for all using (public.is_admin_or_above()) with check (public.is_admin_or_above());

alter table public.commission_rules enable row level security;
create policy commission_rules_select_admin on public.commission_rules for select using (public.is_admin());
create policy commission_rules_write_admin on public.commission_rules for all using (public.is_admin_or_above()) with check (public.is_admin_or_above());

-- collector_profiles: owner + admin read/update; public read of a limited
-- shape (online/approved/location) is handled at the query layer, not RLS,
-- since Flutter needs to see *other* collectors when matching — keep this
-- permissive-for-authenticated for now (Phase 3 can tighten to a view).
alter table public.collector_profiles enable row level security;
create policy collector_profiles_select on public.collector_profiles for select using (auth.role() = 'authenticated');
create policy collector_profiles_update_own on public.collector_profiles for update using (user_id = auth.uid() or public.is_admin());
create policy collector_profiles_insert_own on public.collector_profiles for insert with check (user_id = auth.uid() or public.is_admin());

alter table public.investor_profiles enable row level security;
create policy investor_profiles_select_own on public.investor_profiles for select using (user_id = auth.uid() or public.is_admin());
create policy investor_profiles_update_own on public.investor_profiles for update using (user_id = auth.uid() or public.is_admin());
create policy investor_profiles_insert on public.investor_profiles for insert with check (user_id = auth.uid() or public.is_admin());

alter table public.investor_fleet_rides enable row level security;
create policy investor_fleet_rides_select on public.investor_fleet_rides for select using (
  public.is_admin() or investor_id in (select id from public.investor_profiles where user_id = auth.uid())
  or assigned_collector_id in (select id from public.collector_profiles where user_id = auth.uid())
);
create policy investor_fleet_rides_write on public.investor_fleet_rides for all using (public.is_admin()) with check (public.is_admin());

alter table public.investor_earnings enable row level security;
create policy investor_earnings_select on public.investor_earnings for select using (
  public.is_admin() or investor_id in (select id from public.investor_profiles where user_id = auth.uid())
);
create policy investor_earnings_write_admin on public.investor_earnings for all using (public.is_admin()) with check (public.is_admin());

-- collector_vehicles / KYC
alter table public.collector_vehicles enable row level security;
create policy collector_vehicles_select on public.collector_vehicles for select using (
  public.is_admin() or driver_id = auth.uid()
  or collector_id in (select id from public.collector_profiles where user_id = auth.uid())
);
create policy collector_vehicles_write_own on public.collector_vehicles for all using (
  public.is_admin() or driver_id = auth.uid()
  or collector_id in (select id from public.collector_profiles where user_id = auth.uid())
) with check (
  public.is_admin() or driver_id = auth.uid()
  or collector_id in (select id from public.collector_profiles where user_id = auth.uid())
);

alter table public.vehicle_driver_registrations enable row level security;
create policy vehicle_driver_registrations_select on public.vehicle_driver_registrations for select using (
  public.is_admin() or registered_by_id = auth.uid() or driver_user_id = auth.uid()
);
create policy vehicle_driver_registrations_write on public.vehicle_driver_registrations for all using (
  public.is_admin() or registered_by_id = auth.uid()
) with check (public.is_admin() or registered_by_id = auth.uid());

alter table public.collector_kyc enable row level security;
create policy collector_kyc_select_own on public.collector_kyc for select using (user_id = auth.uid() or public.is_admin());
create policy collector_kyc_insert_own on public.collector_kyc for insert with check (user_id = auth.uid());
create policy collector_kyc_update on public.collector_kyc for update using (user_id = auth.uid() or public.is_admin());

alter table public.kyc_documents enable row level security;
create policy kyc_documents_select on public.kyc_documents for select using (
  public.is_admin() or kyc_id in (select id from public.collector_kyc where user_id = auth.uid())
);
create policy kyc_documents_insert on public.kyc_documents for insert with check (
  kyc_id in (select id from public.collector_kyc where user_id = auth.uid())
);

alter table public.collector_score_events enable row level security;
create policy collector_score_events_select on public.collector_score_events for select using (
  public.is_admin() or collector_id in (select id from public.collector_profiles where user_id = auth.uid())
);
create policy collector_score_events_write_admin on public.collector_score_events for insert with check (public.is_admin());

alter table public.credit_score_actions enable row level security;
create policy credit_score_actions_select on public.credit_score_actions for select using (
  public.is_admin() or collector_id in (select id from public.collector_profiles where user_id = auth.uid())
);
create policy credit_score_actions_insert_own on public.credit_score_actions for insert with check (
  collector_id in (select id from public.collector_profiles where user_id = auth.uid())
);

-- pickup_requests: customer or assigned/collector-eligible collector; a
-- collector additionally needs to see 'finding' rows (the open queue) even
-- before they're assigned.
alter table public.pickup_requests enable row level security;
create policy pickup_requests_select on public.pickup_requests for select using (
  public.is_admin()
  or customer_id = auth.uid()
  or collector_id = auth.uid()
  or (status = 'finding' and public.is_approved_collector())
);
create policy pickup_requests_insert_own on public.pickup_requests for insert with check (customer_id = auth.uid());
create policy pickup_requests_update on public.pickup_requests for update using (
  public.is_admin() or customer_id = auth.uid() or collector_id = auth.uid()
  or (status = 'finding' and public.is_approved_collector())
);

alter table public.scheduled_pickups enable row level security;
create policy scheduled_pickups_select on public.scheduled_pickups for select using (
  public.is_admin() or customer_id = auth.uid() or assigned_collector_id = auth.uid()
);
create policy scheduled_pickups_insert on public.scheduled_pickups for insert with check (
  customer_id = auth.uid() or public.is_admin()
);
create policy scheduled_pickups_update on public.scheduled_pickups for update using (
  public.is_admin() or customer_id = auth.uid() or assigned_collector_id = auth.uid()
);

alter table public.collection_commissions enable row level security;
create policy collection_commissions_select on public.collection_commissions for select using (
  public.is_admin()
  or pickup_request_id in (select id from public.pickup_requests where customer_id = auth.uid() or collector_id = auth.uid())
);
create policy collection_commissions_write_admin on public.collection_commissions for all using (public.is_admin()) with check (public.is_admin());

-- Ownership = single user_id column (straightforward pattern, repeated)
alter table public.saved_addresses enable row level security;
create policy saved_addresses_all_own on public.saved_addresses for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.notifications enable row level security;
create policy notifications_select_own on public.notifications for select using (user_id = auth.uid() or public.is_admin());
create policy notifications_update_own on public.notifications for update using (user_id = auth.uid());
create policy notifications_insert_admin on public.notifications for insert with check (public.is_admin() or user_id = auth.uid());

alter table public.dumping_reports enable row level security;
create policy dumping_reports_select on public.dumping_reports for select using (reported_by_id = auth.uid() or public.is_admin());
create policy dumping_reports_insert_own on public.dumping_reports for insert with check (reported_by_id = auth.uid());
create policy dumping_reports_update_admin on public.dumping_reports for update using (public.is_admin());

alter table public.payment_methods enable row level security;
create policy payment_methods_all_own on public.payment_methods for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.withdrawal_requests enable row level security;
create policy withdrawal_requests_select on public.withdrawal_requests for select using (collector_id = auth.uid() or public.is_admin());
create policy withdrawal_requests_insert_own on public.withdrawal_requests for insert with check (collector_id = auth.uid());
create policy withdrawal_requests_update_admin on public.withdrawal_requests for update using (public.is_admin());

alter table public.fcm_tokens enable row level security;
create policy fcm_tokens_all_own on public.fcm_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.company_waste_bins enable row level security;
create policy company_waste_bins_select on public.company_waste_bins for select using (
  assigned_collector_id = auth.uid() or public.is_admin()
);
create policy company_waste_bins_write_admin on public.company_waste_bins for all using (public.is_admin()) with check (public.is_admin());

alter table public.support_tickets enable row level security;
create policy support_tickets_select on public.support_tickets for select using (
  user_id = auth.uid() or assigned_admin_id = auth.uid() or public.is_admin()
);
create policy support_tickets_insert_own on public.support_tickets for insert with check (user_id = auth.uid());
create policy support_tickets_update on public.support_tickets for update using (
  user_id = auth.uid() or public.is_admin()
);

alter table public.support_messages enable row level security;
create policy support_messages_select on public.support_messages for select using (
  public.is_admin()
  or ticket_id in (select id from public.support_tickets where user_id = auth.uid() or assigned_admin_id = auth.uid())
);
create policy support_messages_insert on public.support_messages for insert with check (
  sender_id = auth.uid()
  and ticket_id in (select id from public.support_tickets where user_id = auth.uid() or assigned_admin_id = auth.uid() or public.is_admin())
);

-- otp_verifications: no client access at all — only Edge Functions
-- (running with the service role key) touch this table.
alter table public.otp_verifications enable row level security;
