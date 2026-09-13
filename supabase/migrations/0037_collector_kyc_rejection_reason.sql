-- Ports DeclineCollectorView's rejection_reason (admin_views.py:718) —
-- needed so SupabaseService.declineCollector can record it, matching Django.
alter table public.collector_kyc add column if not exists rejection_reason text;
