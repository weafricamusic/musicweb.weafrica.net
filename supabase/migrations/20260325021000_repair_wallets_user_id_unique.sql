-- Repair wallet upsert conflict target on drifted environments.

with duplicate_wallets as (
  select
    ctid,
    row_number() over (
      partition by user_id
      order by updated_at desc nulls last, created_at desc nulls last, ctid desc
    ) as row_num
  from public.wallets
  where user_id is not null
    and btrim(user_id) <> ''
)
delete from public.wallets w
using duplicate_wallets d
where w.ctid = d.ctid
  and d.row_num > 1;

delete from public.wallets
where user_id is null
   or btrim(user_id) = '';

alter table public.wallets
  alter column user_id set not null;

create unique index if not exists wallets_user_id_unique_idx
  on public.wallets (user_id);

notify pgrst, 'reload schema';
