-- check_email_exists (0020) checked profiles.email — a plain display column
-- that admin_home.dart's profile screen writes independently of the real
-- Supabase Auth login email (auth.users.email). The moment an admin changes
-- their email there, the two columns drift apart: profiles.email updates
-- immediately, auth.users.email is the one that actually governs login.
-- That made the pre-login "does this email exist" probe check the wrong
-- column — after a real email change it could no longer find the account by
-- either the old or the new address, so admin_login.dart always fell
-- through to the (unreachable) Django endpoint. Checking auth.users.email
-- directly makes this match what actually gates sign-in.
create or replace function public.check_email_exists(p_email text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_role text; v_has_password boolean;
begin
  select id into v_id from auth.users where lower(email) = lower(trim(p_email));
  if v_id is null then
    return jsonb_build_object('exists', false);
  end if;
  select role::text, password_set into v_role, v_has_password from profiles where id = v_id;
  return jsonb_build_object('exists', true, 'role', v_role, 'has_password', coalesce(v_has_password, false));
end;
$$;
revoke all on function public.check_email_exists(text) from public;
grant execute on function public.check_email_exists(text) to anon, authenticated;
