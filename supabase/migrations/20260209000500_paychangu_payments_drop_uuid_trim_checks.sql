-- Fix production error: "function btrim(uuid) does not exist"
--
-- This happens when a CHECK constraint (or trigger) calls trim()/btrim() on a UUID-typed column
-- (commonly `paychangu_payments.user_id uuid`). Postgres implements trim() via btrim(), and
-- there is no btrim(uuid) overload.
--
-- WeAfrica uses Firebase UID strings, so `uid text` is the canonical identifier.
-- `user_id` is treated as an optional compatibility alias.

-- Drop any CHECK constraints on paychangu_payments that call trim()/btrim() on user_id.
do $$
declare
  r record;
begin
  for r in (
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'paychangu_payments'
      and c.contype = 'c'
      and (
        pg_get_constraintdef(c.oid) ilike '%trim(%user_id%'
        or pg_get_constraintdef(c.oid) ilike '%btrim(%user_id%'
        or pg_get_constraintdef(c.oid) ilike '%trim(user_id%'
        or pg_get_constraintdef(c.oid) ilike '%btrim(user_id%'
      )
  ) loop
    execute format('alter table public.paychangu_payments drop constraint if exists %I', r.conname);
  end loop;
exception
  when undefined_table then
    null;
end $$;
