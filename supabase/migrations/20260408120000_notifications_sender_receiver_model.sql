-- Extend notification center to support sender -> receiver architecture.
-- Existing receiver column remains `user_uid` for backward compatibility.

alter table if exists public.notifications
  add column if not exists sender_uid text,
  add column if not exists sender_role text,
  add column if not exists action text,
  add column if not exists entity_id text,
  add column if not exists entity_type text;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notifications'
      and column_name = 'sender_role'
  ) then
    begin
      alter table public.notifications
        drop constraint if exists notifications_sender_role_check;
      alter table public.notifications
        add constraint notifications_sender_role_check
        check (sender_role is null or sender_role in ('system', 'consumer', 'artist', 'dj'));
    exception
      when others then
        -- Keep migration resilient across schema drift.
        null;
    end;
  end if;
end $$;

create index if not exists notifications_sender_uid_idx
  on public.notifications (sender_uid);

create index if not exists notifications_action_idx
  on public.notifications (action);

create index if not exists notifications_entity_lookup_idx
  on public.notifications (entity_type, entity_id, created_at desc);
