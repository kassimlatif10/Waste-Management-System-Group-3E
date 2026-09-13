-- Custom Access Token Hook: injects role + branch_id into the JWT at mint
-- time, so RLS policies can read (auth.jwt() ->> 'role') directly instead of
-- joining profiles on every row check. The function is created here, but
-- Supabase requires it to be *enabled* as the active hook from the
-- Dashboard (Authentication -> Hooks) — that one toggle can't be done via
-- SQL migration and is a manual step for Phase 0.

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer set search_path = public
as $$
declare
  claims jsonb;
  user_role text;
  user_branch bigint;
begin
  select role::text, branch_id into user_role, user_branch
  from public.profiles
  where id = (event->>'user_id')::uuid;

  -- NOTE: do NOT set claims.role — Supabase/PostgREST reserves that exact
  -- claim for the *Postgres* role (anon/authenticated/service_role) and
  -- uses it to `SET ROLE` on every request. Overwriting it with the app
  -- role broke every authenticated request ("role \"customer\" does not
  -- exist") the first time this was tried. The app role lives under
  -- app_role instead — see public.jwt_role() in 0003_rls.sql.
  claims := coalesce(event->'claims', '{}'::jsonb);
  claims := jsonb_set(claims, '{app_role}', to_jsonb(coalesce(user_role, 'customer')));
  if user_branch is not null then
    claims := jsonb_set(claims, '{branch_id}', to_jsonb(user_branch));
  end if;

  event := jsonb_set(event, '{claims}', claims);
  return event;
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook from authenticated, anon, public;

grant select on public.profiles to supabase_auth_admin;
