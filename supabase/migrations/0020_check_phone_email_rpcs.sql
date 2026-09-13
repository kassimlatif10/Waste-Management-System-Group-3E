-- Pre-login existence checks (mirrors Django's CheckPhoneView) must work
-- for a fully anonymous caller — there's no session yet at this point in
-- the login flow. profiles_select_own blocks exactly that (by design, for
-- every OTHER read), so this needs a narrow SECURITY DEFINER RPC that
-- returns only {exists, role, has_password} rather than exposing the table.

create or replace function public.check_phone_exists(p_phone text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role text; v_has_password boolean;
begin
  select role::text, password_set into v_role, v_has_password from profiles where phone = p_phone;
  if v_role is null then
    return jsonb_build_object('exists', false);
  end if;
  return jsonb_build_object('exists', true, 'role', v_role, 'has_password', coalesce(v_has_password, false));
end;
$$;
revoke all on function public.check_phone_exists(text) from public;
grant execute on function public.check_phone_exists(text) to anon, authenticated;

create or replace function public.check_email_exists(p_email text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role text; v_has_password boolean;
begin
  select role::text, password_set into v_role, v_has_password from profiles where email = p_email;
  if v_role is null then
    return jsonb_build_object('exists', false);
  end if;
  return jsonb_build_object('exists', true, 'role', v_role, 'has_password', coalesce(v_has_password, false));
end;
$$;
revoke all on function public.check_email_exists(text) from public;
grant execute on function public.check_email_exists(text) to anon, authenticated;
