-- Battle weekly limits usage tracking (host/join)

create table if not exists creator_usage_events (
  id bigserial primary key,
  user_id text not null,
  role text not null check (role in ('artist', 'dj')),
  action text not null check (action in ('battle_host', 'battle_join')),
  ref text not null,
  occurred_at timestamptz not null default now()
);

create unique index if not exists creator_usage_events_user_action_ref_unique
  on creator_usage_events(user_id, action, ref);

create index if not exists creator_usage_events_user_action_week_idx
  on creator_usage_events(user_id, action, occurred_at);

alter table creator_usage_events enable row level security;

do $$
begin
  create policy "deny_all" on creator_usage_events for all
    using (false)
    with check (false);
exception when duplicate_object then
  null;
end $$;

create or replace function creator_usage_try_consume_weekly(
  p_user_id text,
  p_role text,
  p_action text,
  p_limit integer,
  p_ref text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_week_start timestamptz;
  v_used integer;
  v_key text;
begin
  if p_user_id is null or btrim(p_user_id) = '' then
    return jsonb_build_object('ok', false, 'error', 'bad_request', 'message', 'user_id is required');
  end if;
  if p_role is null or btrim(p_role) = '' then
    return jsonb_build_object('ok', false, 'error', 'bad_request', 'message', 'role is required');
  end if;
  if p_action is null or btrim(p_action) = '' then
    return jsonb_build_object('ok', false, 'error', 'bad_request', 'message', 'action is required');
  end if;
  if p_ref is null or btrim(p_ref) = '' then
    return jsonb_build_object('ok', false, 'error', 'bad_request', 'message', 'ref is required');
  end if;

  v_week_start := date_trunc('week', now());

  -- Unlimited: skip inserting to avoid unbounded growth.
  if p_limit is not null and p_limit < 0 then
    return jsonb_build_object(
      'ok', true,
      'allowed', true,
      'consumed', false,
      'used', null,
      'limit', p_limit,
      'week_start', v_week_start
    );
  end if;

  if p_limit is null then
    return jsonb_build_object('ok', false, 'error', 'bad_request', 'message', 'limit is required');
  end if;

  -- Atomicity: lock per user/action/week.
  v_key := p_user_id || ':' || p_action || ':' || v_week_start::text;
  perform pg_advisory_xact_lock(hashtext(v_key));

  -- Idempotency: allow if we already consumed this ref.
  if exists(
    select 1
      from creator_usage_events
     where user_id = p_user_id
       and action = p_action
       and ref = p_ref
  ) then
    select count(*)::int into v_used
      from creator_usage_events
     where user_id = p_user_id
       and action = p_action
       and occurred_at >= v_week_start
       and occurred_at < (v_week_start + interval '7 days');

    return jsonb_build_object(
      'ok', true,
      'allowed', true,
      'consumed', false,
      'used', v_used,
      'limit', p_limit,
      'week_start', v_week_start
    );
  end if;

  select count(*)::int into v_used
    from creator_usage_events
   where user_id = p_user_id
     and action = p_action
     and occurred_at >= v_week_start
     and occurred_at < (v_week_start + interval '7 days');

  if v_used >= p_limit then
    return jsonb_build_object(
      'ok', true,
      'allowed', false,
      'consumed', false,
      'used', v_used,
      'limit', p_limit,
      'week_start', v_week_start
    );
  end if;

  insert into creator_usage_events(user_id, role, action, ref)
  values (p_user_id, p_role, p_action, p_ref);

  return jsonb_build_object(
    'ok', true,
    'allowed', true,
    'consumed', true,
    'used', v_used + 1,
    'limit', p_limit,
    'week_start', v_week_start
  );
end;
$$;

revoke all on function creator_usage_try_consume_weekly(text, text, text, integer, text) from public;
grant execute on function creator_usage_try_consume_weekly(text, text, text, integer, text) to service_role;
