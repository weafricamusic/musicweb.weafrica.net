-- AI credits ledger (server-only; service-role writes)

create table if not exists public.ai_credit_transactions (
  id bigserial primary key,
  uid text not null,
  delta integer not null,
  reason text,
  created_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);

create index if not exists ai_credit_transactions_uid_idx on public.ai_credit_transactions (uid);
create index if not exists ai_credit_transactions_created_at_idx on public.ai_credit_transactions (created_at desc);

alter table public.ai_credit_transactions enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_credit_transactions'
      and policyname = 'deny_all_ai_credit_transactions'
  ) then
    create policy deny_all_ai_credit_transactions
      on public.ai_credit_transactions
      for all
      using (false)
      with check (false);
  end if;
end $$;

create or replace function public.user_ai_credit_balance(p_uid text)
returns integer
language sql
stable
as $$
  select coalesce(sum(delta), 0)::integer
  from public.ai_credit_transactions
  where uid = p_uid;
$$;

-- Spend credits if available. Returns new balance, or -1 when insufficient.
create or replace function public.ai_try_spend_credits(p_uid text, p_cost integer, p_reason text default 'ai_spend')
returns integer
language plpgsql
as $$
declare
  bal integer;
begin
  if p_cost is null or p_cost <= 0 then
    return (select public.user_ai_credit_balance(p_uid));
  end if;

  bal := (select public.user_ai_credit_balance(p_uid));
  if bal < p_cost then
    return -1;
  end if;

  insert into public.ai_credit_transactions (uid, delta, reason, meta)
  values (p_uid, -p_cost, p_reason, jsonb_build_object('action','spend'));

  return (select public.user_ai_credit_balance(p_uid));
end;
$$;
