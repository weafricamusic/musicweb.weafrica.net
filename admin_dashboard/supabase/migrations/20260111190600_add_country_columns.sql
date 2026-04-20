-- Add optional country dimension columns to key finance tables

do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='transactions' and column_name='country_code'
  ) then
    alter table public.transactions add column country_code text;
    create index if not exists transactions_country_code_idx on public.transactions (country_code);
  end if;
end $$;

do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='withdrawals' and column_name='country_code'
  ) then
    alter table public.withdrawals add column country_code text;
    create index if not exists withdrawals_country_code_idx on public.withdrawals (country_code);
  end if;
end $$;
