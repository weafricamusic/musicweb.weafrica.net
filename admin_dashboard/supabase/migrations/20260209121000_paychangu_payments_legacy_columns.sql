-- Legacy compatibility: some older PayChangu edge functions write to public.paychangu_payments
-- with columns like months/raw/tx_ref.
--
-- This migration is safe to run even if paychangu_payments does not exist.

do $$
begin
  if to_regclass('public.paychangu_payments') is null then
    -- Nothing to do.
    return;
  end if;

  -- Duration purchased
  execute 'alter table public.paychangu_payments add column if not exists months integer';
  execute 'update public.paychangu_payments set months = 1 where months is null';
  execute 'alter table public.paychangu_payments alter column months set default 1';
  execute 'alter table public.paychangu_payments alter column months set not null';

  -- Provider reference
  execute 'alter table public.paychangu_payments add column if not exists tx_ref text';

  -- Payload storage
  execute 'alter table public.paychangu_payments add column if not exists raw jsonb';
  execute 'update public.paychangu_payments set raw = ''{}''::jsonb where raw is null';
  execute 'alter table public.paychangu_payments alter column raw set default ''{}''::jsonb';
  execute 'alter table public.paychangu_payments alter column raw set not null';

  execute 'alter table public.paychangu_payments add column if not exists meta jsonb';
  execute 'update public.paychangu_payments set meta = ''{}''::jsonb where meta is null';
  execute 'alter table public.paychangu_payments alter column meta set default ''{}''::jsonb';
  execute 'alter table public.paychangu_payments alter column meta set not null';

  -- Common fields used by various implementations
  execute 'alter table public.paychangu_payments add column if not exists status text';
  execute 'alter table public.paychangu_payments add column if not exists uid text';
  execute 'alter table public.paychangu_payments add column if not exists user_id text';
  execute 'alter table public.paychangu_payments add column if not exists plan_id text';
  execute 'alter table public.paychangu_payments add column if not exists amount_mwk numeric(14,2)';
  execute 'alter table public.paychangu_payments add column if not exists currency text';
  execute 'alter table public.paychangu_payments add column if not exists country_code text';
  execute 'alter table public.paychangu_payments add column if not exists checkout_url text';

  -- Timestamps (if your table already has different names, keep them)
  execute 'alter table public.paychangu_payments add column if not exists created_at timestamptz not null default now()';
  execute 'alter table public.paychangu_payments add column if not exists updated_at timestamptz not null default now()';

  -- Helpful index for reconciliation
  begin
    execute 'create index if not exists paychangu_payments_tx_ref_idx on public.paychangu_payments (tx_ref)';
  exception when others then
    -- Ignore index failures (e.g., permissions/locks).
    null;
  end;

  -- Some legacy clients/functions send `uid` instead of `user_id`.
  -- If user_id is NOT NULL, this prevents inserts from failing.
  execute $$
    create or replace function public.paychangu_payments_coalesce_user_id()
    returns trigger
    language plpgsql
    as $$
    begin
      if new.user_id is null or btrim(new.user_id) = '' then
        if new.uid is not null and btrim(new.uid) <> '' then
          new.user_id := new.uid;
        end if;
      end if;
      return new;
    end;
    $$;
  $$;

  begin
    execute 'drop trigger if exists trg_paychangu_payments_coalesce_user_id on public.paychangu_payments';
  exception when others then
    null;
  end;

  execute 'create trigger trg_paychangu_payments_coalesce_user_id before insert or update on public.paychangu_payments for each row execute function public.paychangu_payments_coalesce_user_id()';
end $$;

-- Hint PostgREST to refresh its schema cache quickly.
notify pgrst, 'reload schema';
