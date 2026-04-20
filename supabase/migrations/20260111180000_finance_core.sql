-- Finance core tables for admin dashboard.
-- Service-role bypasses RLS; normal clients are denied by default.

-- 1) Coins catalog
create table if not exists public.coins (
  id bigserial primary key,
  code text not null unique,
  name text not null,
  value_mwk integer not null check (value_mwk > 0),
  status text not null default 'active' check (status in ('active','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.coins enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'coins'
      and policyname = 'deny_all_coins'
  ) then
    create policy deny_all_coins
      on public.coins
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- Seed default coin types (idempotent).
insert into public.coins (code, name, value_mwk, status)
values
  ('bronze', 'Bronze', 100, 'active'),
  ('silver', 'Silver', 500, 'active'),
  ('gold', 'Gold', 1000, 'active'),
  ('diamond', 'Diamond', 5000, 'active')
on conflict (code) do update
set name = excluded.name,
    value_mwk = excluded.value_mwk,
    status = excluded.status,
    updated_at = now();
-- 2) Finance settings (read-only for now)
create table if not exists public.finance_settings (
  id bigserial primary key,
  commission_percent numeric(5,2) not null default 30.00,
  artist_share_percent numeric(5,2) not null default 50.00,
  dj_share_percent numeric(5,2) not null default 20.00,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_settings_percent_sum check (commission_percent + artist_share_percent + dj_share_percent = 100.00)
);
alter table public.finance_settings enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'finance_settings'
      and policyname = 'deny_all_finance_settings'
  ) then
    create policy deny_all_finance_settings
      on public.finance_settings
      for all
      using (false)
      with check (false);
  end if;
end $$;
insert into public.finance_settings (commission_percent, artist_share_percent, dj_share_percent)
select 30.00, 50.00, 20.00
where not exists (select 1 from public.finance_settings);
-- 3) Transactions ledger (append-only by convention; do not delete)
create table if not exists public.transactions (
  id bigserial primary key,
  type text not null check (type in (
    'coin_purchase',
    'subscription',
    'ad',
    'gift',
    'battle_reward',
    'adjustment'
  )),
  actor_id text,
  actor_type text not null default 'user' check (actor_type in ('user','admin','system')),
  target_type text check (target_type in ('artist','dj')),
  target_id text,
  amount_mwk numeric(14,2) not null default 0,
  coins bigint not null default 0,
  source text,
  created_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);
create index if not exists transactions_type_idx on public.transactions (type);
create index if not exists transactions_created_at_idx on public.transactions (created_at desc);
create index if not exists transactions_target_idx on public.transactions (target_type, target_id);
create index if not exists transactions_actor_idx on public.transactions (actor_type, actor_id);
alter table public.transactions enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'transactions'
      and policyname = 'deny_all_transactions'
  ) then
    create policy deny_all_transactions
      on public.transactions
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- 4) Withdrawals (manual approval; no auto payouts)
create table if not exists public.withdrawals (
  id bigserial primary key,
  beneficiary_type text not null check (beneficiary_type in ('artist','dj')),
  beneficiary_id text not null,
  amount_mwk numeric(14,2) not null check (amount_mwk > 0),
  method text not null,
  status text not null default 'pending' check (status in ('pending','approved','paid','rejected')),
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  paid_at timestamptz,
  rejected_at timestamptz,
  admin_email text,
  note text,
  meta jsonb not null default '{}'::jsonb
);
create index if not exists withdrawals_status_idx on public.withdrawals (status);
create index if not exists withdrawals_requested_at_idx on public.withdrawals (requested_at desc);
create index if not exists withdrawals_beneficiary_idx on public.withdrawals (beneficiary_type, beneficiary_id);
alter table public.withdrawals enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'withdrawals'
      and policyname = 'deny_all_withdrawals'
  ) then
    create policy deny_all_withdrawals
      on public.withdrawals
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- 5) Earnings freeze state + history (fraud protection)
create table if not exists public.earnings_freeze_state (
  beneficiary_type text not null check (beneficiary_type in ('artist','dj')),
  beneficiary_id text not null,
  frozen boolean not null default false,
  reason text,
  updated_by_email text,
  updated_at timestamptz not null default now(),
  primary key (beneficiary_type, beneficiary_id)
);
alter table public.earnings_freeze_state enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'earnings_freeze_state'
      and policyname = 'deny_all_earnings_freeze_state'
  ) then
    create policy deny_all_earnings_freeze_state
      on public.earnings_freeze_state
      for all
      using (false)
      with check (false);
  end if;
end $$;
create table if not exists public.earnings_freeze_events (
  id bigserial primary key,
  beneficiary_type text not null check (beneficiary_type in ('artist','dj')),
  beneficiary_id text not null,
  frozen boolean not null,
  reason text,
  admin_email text,
  created_at timestamptz not null default now()
);
create index if not exists earnings_freeze_events_created_at_idx on public.earnings_freeze_events (created_at desc);
create index if not exists earnings_freeze_events_beneficiary_idx on public.earnings_freeze_events (beneficiary_type, beneficiary_id);
alter table public.earnings_freeze_events enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'earnings_freeze_events'
      and policyname = 'deny_all_earnings_freeze_events'
  ) then
    create policy deny_all_earnings_freeze_events
      on public.earnings_freeze_events
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- 6) Aggregation helpers (RPC)
create or replace function public.finance_top_summary()
returns table (
  total_revenue_mwk numeric(14,2),
  coins_sold bigint,
  artist_earnings_mwk numeric(14,2),
  dj_earnings_mwk numeric(14,2),
  weafrica_commission_mwk numeric(14,2),
  pending_withdrawals_mwk numeric(14,2),
  commission_percent numeric(5,2),
  artist_share_percent numeric(5,2),
  dj_share_percent numeric(5,2)
)
language sql
stable
as $$
  with
    revenue as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.transactions
      where type in ('coin_purchase','subscription','ad')
    ),
    coins as (
      select coalesce(sum(coins), 0)::bigint as sold
      from public.transactions
      where type = 'coin_purchase'
    ),
    artist as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.transactions
      where type in ('gift','battle_reward') and target_type = 'artist'
    ),
    dj as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.transactions
      where type in ('gift','battle_reward') and target_type = 'dj'
    ),
    pending as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.withdrawals
      where status = 'pending'
    ),
    settings as (
      select
        commission_percent,
        artist_share_percent,
        dj_share_percent
      from public.finance_settings
      order by id asc
      limit 1
    )
  select
    revenue.total as total_revenue_mwk,
    coins.sold as coins_sold,
    artist.total as artist_earnings_mwk,
    dj.total as dj_earnings_mwk,
    greatest(revenue.total - artist.total - dj.total, 0)::numeric(14,2) as weafrica_commission_mwk,
    pending.total as pending_withdrawals_mwk,
    coalesce(settings.commission_percent, 30.00) as commission_percent,
    coalesce(settings.artist_share_percent, 50.00) as artist_share_percent,
    coalesce(settings.dj_share_percent, 20.00) as dj_share_percent
  from revenue, coins, artist, dj, pending
  left join settings on true;
$$;
create or replace function public.finance_earnings_overview(p_beneficiary_type text)
returns table (
  beneficiary_id text,
  total_coins bigint,
  earned_mwk numeric(14,2),
  withdrawn_mwk numeric(14,2),
  pending_withdrawals_mwk numeric(14,2),
  available_mwk numeric(14,2),
  status text
)
language sql
stable
as $$
  with
    earned as (
      select
        target_id as beneficiary_id,
        coalesce(sum(coins), 0)::bigint as total_coins,
        coalesce(sum(amount_mwk), 0)::numeric(14,2) as earned_mwk
      from public.transactions
      where type in ('gift','battle_reward')
        and target_type = p_beneficiary_type
        and target_id is not null
      group by target_id
    ),
    withdrawn as (
      select
        beneficiary_id,
        coalesce(sum(amount_mwk), 0)::numeric(14,2) as withdrawn_mwk
      from public.withdrawals
      where beneficiary_type = p_beneficiary_type
        and status in ('approved','paid')
      group by beneficiary_id
    ),
    pending as (
      select
        beneficiary_id,
        coalesce(sum(amount_mwk), 0)::numeric(14,2) as pending_withdrawals_mwk
      from public.withdrawals
      where beneficiary_type = p_beneficiary_type
        and status = 'pending'
      group by beneficiary_id
    ),
    freeze_state as (
      select
        beneficiary_id,
        frozen
      from public.earnings_freeze_state
      where beneficiary_type = p_beneficiary_type
    )
  select
    e.beneficiary_id,
    e.total_coins,
    e.earned_mwk,
    coalesce(w.withdrawn_mwk, 0)::numeric(14,2) as withdrawn_mwk,
    coalesce(p.pending_withdrawals_mwk, 0)::numeric(14,2) as pending_withdrawals_mwk,
    greatest(e.earned_mwk - coalesce(w.withdrawn_mwk, 0) - coalesce(p.pending_withdrawals_mwk, 0), 0)::numeric(14,2) as available_mwk,
    case when coalesce(f.frozen, false) then 'frozen' else 'active' end as status
  from earned e
  left join withdrawn w using (beneficiary_id)
  left join pending p using (beneficiary_id)
  left join freeze_state f using (beneficiary_id)
  order by e.earned_mwk desc;
$$;
