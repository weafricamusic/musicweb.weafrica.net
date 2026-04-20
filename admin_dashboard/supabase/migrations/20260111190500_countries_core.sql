-- Countries master configuration table for localization and country-based rules

create table if not exists public.countries (
  id bigserial primary key,
  country_code text not null unique,
  country_name text not null,
  currency_code text not null,
  currency_symbol text not null,
  coin_rate numeric(14,6) not null default 100.0, -- coins per 1 USD
  min_payout_amount numeric(14,2) not null default 0,
  payment_methods jsonb not null default '[]'::jsonb,
  live_stream_enabled boolean not null default true,
  ads_enabled boolean not null default true,
  premium_enabled boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- If the table already existed with a different shape, ensure columns exist before indexes/seed.
do $$
begin
  if to_regclass('public.countries') is not null then
    alter table public.countries
      add column if not exists country_code text,
      add column if not exists country_name text,
      add column if not exists currency_code text,
      add column if not exists currency_symbol text,
      add column if not exists coin_rate numeric(14,6),
      add column if not exists min_payout_amount numeric(14,2),
      add column if not exists payment_methods jsonb,
      add column if not exists live_stream_enabled boolean,
      add column if not exists ads_enabled boolean,
      add column if not exists premium_enabled boolean,
      add column if not exists is_active boolean,
      add column if not exists created_at timestamptz,
      add column if not exists updated_at timestamptz;

    -- Best-effort backfill if a legacy `code` column exists.
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='countries' and column_name='code'
    ) then
      execute 'update public.countries set country_code = coalesce(country_code, code) where country_code is null';
    end if;

    -- Defaults/backfills (safe even if columns existed already)
    update public.countries set
      coin_rate = coalesce(coin_rate, 100.0),
      min_payout_amount = coalesce(min_payout_amount, 0),
      payment_methods = coalesce(payment_methods, '[]'::jsonb),
      live_stream_enabled = coalesce(live_stream_enabled, true),
      ads_enabled = coalesce(ads_enabled, true),
      premium_enabled = coalesce(premium_enabled, true),
      is_active = coalesce(is_active, true),
      created_at = coalesce(created_at, now()),
      updated_at = coalesce(updated_at, now());
  end if;
end $$;

create index if not exists countries_active_idx on public.countries (is_active) where is_active = true;
create index if not exists countries_code_idx on public.countries (country_code);

alter table public.countries enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'countries'
      and policyname = 'deny_all_countries'
  ) then
    create policy deny_all_countries
      on public.countries
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Seed Malawi defaults (idempotent)
do $$
begin
  -- If a unique constraint/index exists on country_code, use ON CONFLICT.
  if exists (
    select 1
    from pg_index i
    join pg_class t on t.oid = i.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'countries'
      and i.indisunique = true
      and pg_get_indexdef(i.indexrelid) ilike '%(country_code%'
  ) then
    insert into public.countries (
      country_code, country_name, currency_code, currency_symbol,
      coin_rate, min_payout_amount, payment_methods,
      live_stream_enabled, ads_enabled, premium_enabled, is_active
    ) values (
      'MW', 'Malawi', 'MWK', 'K',
      1800.0, 50000.00, '["TNM Mpamba","Airtel Money","Card"]'::jsonb,
      true, true, true, true
    )
    on conflict (country_code) do update set
      country_name = excluded.country_name,
      currency_code = excluded.currency_code,
      currency_symbol = excluded.currency_symbol,
      coin_rate = excluded.coin_rate,
      min_payout_amount = excluded.min_payout_amount,
      payment_methods = excluded.payment_methods,
      live_stream_enabled = excluded.live_stream_enabled,
      ads_enabled = excluded.ads_enabled,
      premium_enabled = excluded.premium_enabled,
      is_active = excluded.is_active,
      updated_at = now();
  else
    -- Fallback: insert if missing, then update (doesn't require unique constraint).
    insert into public.countries (
      country_code, country_name, currency_code, currency_symbol,
      coin_rate, min_payout_amount, payment_methods,
      live_stream_enabled, ads_enabled, premium_enabled, is_active
    )
    select
      'MW', 'Malawi', 'MWK', 'K',
      1800.0, 50000.00, '["TNM Mpamba","Airtel Money","Card"]'::jsonb,
      true, true, true, true
    where not exists (
      select 1 from public.countries c where upper(coalesce(c.country_code,'')) = 'MW'
    );

    update public.countries
      set
        country_name = 'Malawi',
        currency_code = 'MWK',
        currency_symbol = 'K',
        coin_rate = 1800.0,
        min_payout_amount = 50000.00,
        payment_methods = '["TNM Mpamba","Airtel Money","Card"]'::jsonb,
        live_stream_enabled = true,
        ads_enabled = true,
        premium_enabled = true,
        is_active = true,
        updated_at = now()
      where upper(coalesce(country_code,'')) = 'MW';
  end if;
end $$;

-- Helper RPC: get a single active country config by code (defaults to MW)
create or replace function public.get_country_config(p_code text)
returns table (
  country_code text,
  country_name text,
  currency_code text,
  currency_symbol text,
  coin_rate numeric(14,6),
  min_payout_amount numeric(14,2),
  payment_methods jsonb,
  live_stream_enabled boolean,
  ads_enabled boolean,
  premium_enabled boolean,
  is_active boolean
)
language sql
stable
as $$
  select
    c.country_code,
    c.country_name,
    c.currency_code,
    c.currency_symbol,
    c.coin_rate,
    c.min_payout_amount,
    c.payment_methods,
    c.live_stream_enabled,
    c.ads_enabled,
    c.premium_enabled,
    c.is_active
  from public.countries c
  where c.is_active = true
    and c.country_code = coalesce(nullif(trim(upper(p_code)), ''), 'MW')
  limit 1
$$;
