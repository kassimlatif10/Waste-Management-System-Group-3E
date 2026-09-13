-- Ports customer_views.py's AcceptProposedCollectorView (:352) and
-- SkipProposedCollectorView (:384) — the customer's side of the
-- accept-collector handshake, sitting between accept_pickup_request and
-- mark_pickup_on_way.

create or replace function public.confirm_proposed_collector(p_request_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare v_req public.pickup_requests;
begin
  update pickup_requests set status = 'assigned'
  where id = p_request_id and customer_id = auth.uid() and status = 'proposed'
  returning * into v_req;
  if v_req is null then
    raise exception 'No proposed collector to accept.' using errcode = 'P0001';
  end if;
  return v_req;
end;
$$;
revoke all on function public.confirm_proposed_collector(bigint) from public;
grant execute on function public.confirm_proposed_collector(bigint) to authenticated;

create or replace function public.skip_proposed_collector(p_request_id bigint)
returns public.pickup_requests
language plpgsql security definer set search_path = public as $$
declare v_req public.pickup_requests;
begin
  select * into v_req from pickup_requests where id = p_request_id and customer_id = auth.uid() for update;
  if v_req is null or v_req.status != 'proposed' then
    raise exception 'No proposed collector to skip.' using errcode = 'P0001';
  end if;

  update pickup_requests set
    declined_collector_ids = case
      when collector_id is null then declined_collector_ids
      when declined_collector_ids @> to_jsonb(collector_id::text) then declined_collector_ids
      else declined_collector_ids || to_jsonb(collector_id::text)
    end,
    collector_id = null,
    status = 'finding'
  where id = p_request_id
  returning * into v_req;

  return v_req;
end;
$$;
revoke all on function public.skip_proposed_collector(bigint) from public;
grant execute on function public.skip_proposed_collector(bigint) to authenticated;
