-- AI monetization core (daily limits + balances helper)

-- Tracks per-user daily usage for free AI features.
create table if not exists public.ai_daily_usage (
  uid text not null,
  day date not null,
  beat_generate_count integer not null default 0 check (beat_generate_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (uid, day)
);

alter table public.ai_daily_usage enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_daily_usage'
      and policyname = 'deny_all_ai_daily_usage'
  ) then
    create policy deny_all_ai_daily_usage
      on public.ai_daily_usage
      for all
      using (false)
      with check (false);
  end if;
end $$;

create index if not exists ai_daily_usage_day_idx on public.ai_daily_usage (day);

-- Atomically increment daily beat usage.
create or replace function public.ai_increment_daily_beat_usage(p_uid text, p_day date)
returns integer
language plpgsql
as $$
declare
  next_count integer;
begin
  insert into public.ai_daily_usage (uid, day, beat_generate_count, updated_at)
  values (p_uid, p_day, 1, now())
  on conflict (uid, day)
  do update
    set beat_generate_count = public.ai_daily_usage.beat_generate_count + 1,
        updated_at = now()
  returning beat_generate_count into next_count;

  return next_count;
end;
$$;

-- Read current daily usage (returns 0 if no row).
create or replace function public.ai_get_daily_beat_usage(p_uid text, p_day date)
returns integer
language sql
stable
as $$
  select coalesce((select beat_generate_count from public.ai_daily_usage where uid = p_uid and day = p_day), 0);
$$;

-- Compute a user's current coin balance from the transactions ledger.
-- Convention: coin purchases/subscriptions/etc add positive coins;
-- AI spends (or other spends) can be recorded as negative coins in an 'adjustment' row.
create or replace function public.user_coin_balance(p_actor_id text)
returns bigint
language sql
stable
as $$
  select coalesce(sum(coins), 0)::bigint
  from public.transactions
  where actor_type = 'user'
    and actor_id = p_actor_id;
$$;
