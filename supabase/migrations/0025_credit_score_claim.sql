-- Ports collector_views.py's CreditScoreEarnView (:1117) — one-time
-- gamified credit-score bonuses.

create or replace function public.claim_credit_score_action(p_action text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_cp public.collector_profiles;
  v_points int;
  v_new_score int;
begin
  v_points := case p_action
    when 'share_collector' then 5
    when 'share_customer' then 4
    when 'rate_app' then 3
    when 'share_rate' then 2
    else null
  end;
  if v_points is null then
    raise exception 'Invalid action.' using errcode = 'P0001';
  end if;

  select * into v_cp from collector_profiles where user_id = v_uid for update;
  if v_cp is null then
    raise exception 'Collector profile not found.' using errcode = 'P0002';
  end if;
  if exists (select 1 from credit_score_actions where collector_id = v_cp.id and action_type = p_action) then
    raise exception 'You have already claimed credit for this action.' using errcode = 'P0001';
  end if;

  v_new_score := least(100, v_cp.credit_score + v_points);
  update collector_profiles set credit_score = v_new_score where id = v_cp.id;
  insert into credit_score_actions (collector_id, action_type) values (v_cp.id, p_action);

  return jsonb_build_object('message', '+' || v_points || ' credit score added.', 'credit_score', v_new_score);
end;
$$;
revoke all on function public.claim_credit_score_action(text) from public;
grant execute on function public.claim_credit_score_action(text) to authenticated;
