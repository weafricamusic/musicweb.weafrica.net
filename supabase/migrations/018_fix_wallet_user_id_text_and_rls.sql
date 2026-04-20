-- Ensure wallet tables use TEXT user_id (Firebase UID) and have MVP dev RLS policies/grants.
-- This is intentionally idempotent and safe to run even if the schema already matches.

create extension if not exists pgcrypto;
do $$
declare
  v_type text;
  r record;
begin
  -- If a column is referenced inside an RLS policy, Postgres blocks ALTER COLUMN TYPE.
  -- So we temporarily drop existing policies on these tables, then recreate MVP policies below.

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallets') then
    for r in (
      select policyname from pg_policies where schemaname='public' and tablename='wallets'
    ) loop
      execute format('drop policy if exists %I on public.wallets', r.policyname);
    end loop;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallet_transactions') then
    for r in (
      select policyname from pg_policies where schemaname='public' and tablename='wallet_transactions'
    ) loop
      execute format('drop policy if exists %I on public.wallet_transactions', r.policyname);
    end loop;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='withdrawal_requests') then
    for r in (
      select policyname from pg_policies where schemaname='public' and tablename='withdrawal_requests'
    ) loop
      execute format('drop policy if exists %I on public.withdrawal_requests', r.policyname);
    end loop;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='battle_earnings') then
    for r in (
      select policyname from pg_policies where schemaname='public' and tablename='battle_earnings'
    ) loop
      execute format('drop policy if exists %I on public.battle_earnings', r.policyname);
    end loop;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='coin_purchases') then
    for r in (
      select policyname from pg_policies where schemaname='public' and tablename='coin_purchases'
    ) loop
      execute format('drop policy if exists %I on public.coin_purchases', r.policyname);
    end loop;
  end if;

  -- wallets.user_id
  select data_type into v_type
  from information_schema.columns
  where table_schema = 'public' and table_name = 'wallets' and column_name = 'user_id';

  if v_type is not null and v_type <> 'text' then
    execute 'alter table public.wallets alter column user_id type text using user_id::text';
  end if;

  -- wallet_transactions.user_id
  select data_type into v_type
  from information_schema.columns
  where table_schema = 'public' and table_name = 'wallet_transactions' and column_name = 'user_id';

  if v_type is not null and v_type <> 'text' then
    execute 'alter table public.wallet_transactions alter column user_id type text using user_id::text';
  end if;

  -- withdrawal_requests.user_id
  select data_type into v_type
  from information_schema.columns
  where table_schema = 'public' and table_name = 'withdrawal_requests' and column_name = 'user_id';

  if v_type is not null and v_type <> 'text' then
    execute 'alter table public.withdrawal_requests alter column user_id type text using user_id::text';
  end if;

  -- battle_earnings.user_id
  select data_type into v_type
  from information_schema.columns
  where table_schema = 'public' and table_name = 'battle_earnings' and column_name = 'user_id';

  if v_type is not null and v_type <> 'text' then
    execute 'alter table public.battle_earnings alter column user_id type text using user_id::text';
  end if;

  -- coin_purchases.user_id
  select data_type into v_type
  from information_schema.columns
  where table_schema = 'public' and table_name = 'coin_purchases' and column_name = 'user_id';

  if v_type is not null and v_type <> 'text' then
    execute 'alter table public.coin_purchases alter column user_id type text using user_id::text';
  end if;

  -- Ensure RLS is enabled (MVP).
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallets') then
    execute 'alter table public.wallets enable row level security';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallet_transactions') then
    execute 'alter table public.wallet_transactions enable row level security';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='withdrawal_requests') then
    execute 'alter table public.withdrawal_requests enable row level security';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='battle_earnings') then
    execute 'alter table public.battle_earnings enable row level security';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='coin_purchases') then
    execute 'alter table public.coin_purchases enable row level security';
  end if;

  -- Ensure MVP allow-all policies exist (so PostgREST reads/writes won't be blocked).
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallets') then
    if not exists (
      select 1 from pg_policies where schemaname='public' and tablename='wallets' and policyname='mvp_public_all'
    ) then
      create policy mvp_public_all on public.wallets for all using (true) with check (true);
    end if;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallet_transactions') then
    if not exists (
      select 1 from pg_policies where schemaname='public' and tablename='wallet_transactions' and policyname='mvp_public_all'
    ) then
      create policy mvp_public_all on public.wallet_transactions for all using (true) with check (true);
    end if;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='withdrawal_requests') then
    if not exists (
      select 1 from pg_policies where schemaname='public' and tablename='withdrawal_requests' and policyname='mvp_public_all'
    ) then
      create policy mvp_public_all on public.withdrawal_requests for all using (true) with check (true);
    end if;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='battle_earnings') then
    if not exists (
      select 1 from pg_policies where schemaname='public' and tablename='battle_earnings' and policyname='mvp_public_all'
    ) then
      create policy mvp_public_all on public.battle_earnings for all using (true) with check (true);
    end if;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='coin_purchases') then
    if not exists (
      select 1 from pg_policies where schemaname='public' and tablename='coin_purchases' and policyname='mvp_public_all'
    ) then
      create policy mvp_public_all on public.coin_purchases for all using (true) with check (true);
    end if;
  end if;

  -- Grants (only if the tables exist).
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallets') then
    execute 'grant select, insert, update, delete on public.wallets to anon, authenticated';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallet_transactions') then
    execute 'grant select, insert, update, delete on public.wallet_transactions to anon, authenticated';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='withdrawal_requests') then
    execute 'grant select, insert, update, delete on public.withdrawal_requests to anon, authenticated';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='battle_earnings') then
    execute 'grant select, insert, update, delete on public.battle_earnings to anon, authenticated';
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='coin_purchases') then
    execute 'grant select, insert, update, delete on public.coin_purchases to anon, authenticated';
  end if;

  -- Ask PostgREST to reload its schema cache (helpful after ALTER TYPE).
  notify pgrst, 'reload schema';
end $$;
