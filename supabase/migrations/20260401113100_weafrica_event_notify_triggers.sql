-- Emit lightweight database events for backend LISTEN/NOTIFY fan-out.

create extension if not exists pgcrypto;

create or replace function public.weafrica_emit_event()
returns trigger
language plpgsql
as $$
declare
  row_data jsonb;
  entity_id text;
  actor_id text;
  country_code text;
  payload text;
begin
  if tg_op = 'DELETE' then
    row_data := to_jsonb(old);
  else
    row_data := to_jsonb(new);
  end if;

  entity_id := coalesce(
    row_data->>'id',
    row_data->>'battle_id',
    row_data->>'channel_id'
  );

  actor_id := coalesce(
    row_data->>'creator_uid',
    row_data->>'user_id',
    row_data->>'host_id',
    row_data->>'host_a_id',
    row_data->>'artist_id'
  );

  country_code := lower(coalesce(
    row_data->>'country_code',
    row_data->>'country',
    row_data->>'region'
  ));

  payload := json_build_object(
    'event_id', gen_random_uuid()::text,
    'event_type', lower(tg_table_name) || '.' || lower(tg_op),
    'table', lower(tg_table_name),
    'op', lower(tg_op),
    'entity_id', entity_id,
    'actor_id', actor_id,
    'country_code', country_code,
    'created_at', now()
  )::text;

  perform pg_notify('weafrica_events', payload);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.songs') is not null then
    drop trigger if exists trg_weafrica_notify_songs on public.songs;
    create trigger trg_weafrica_notify_songs
      after insert on public.songs
      for each row execute function public.weafrica_emit_event();
  end if;

  if to_regclass('public.live_sessions') is not null then
    drop trigger if exists trg_weafrica_notify_live_sessions_insert on public.live_sessions;
    create trigger trg_weafrica_notify_live_sessions_insert
      after insert on public.live_sessions
      for each row execute function public.weafrica_emit_event();

    drop trigger if exists trg_weafrica_notify_live_sessions_update on public.live_sessions;
    create trigger trg_weafrica_notify_live_sessions_update
      after update of is_live, ended_at on public.live_sessions
      for each row execute function public.weafrica_emit_event();
  end if;

  if to_regclass('public.live_battles') is not null then
    drop trigger if exists trg_weafrica_notify_live_battles_insert on public.live_battles;
    create trigger trg_weafrica_notify_live_battles_insert
      after insert on public.live_battles
      for each row execute function public.weafrica_emit_event();

    drop trigger if exists trg_weafrica_notify_live_battles_update on public.live_battles;
    create trigger trg_weafrica_notify_live_battles_update
      after update of status, ended_at on public.live_battles
      for each row execute function public.weafrica_emit_event();
  end if;

  if to_regclass('public.photo_song_posts') is not null then
    drop trigger if exists trg_weafrica_notify_photo_song_posts on public.photo_song_posts;
    create trigger trg_weafrica_notify_photo_song_posts
      after insert on public.photo_song_posts
      for each row execute function public.weafrica_emit_event();
  end if;
end $$;

select pg_notify('pgrst', 'reload schema');
