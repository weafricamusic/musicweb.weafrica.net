-- Live sessions trending score
--
-- Adds a lightweight materialized score used by the consumer Live tab to order
-- live sessions by momentum (viewers + gifts + likes + recency).
--
-- Compute periodically (e.g. every ~5 minutes) by calling:
--   select public.update_live_session_trending_scores(5);

alter table public.live_sessions
  add column if not exists trending_score double precision not null default 0;

-- Backfill legacy rows (best-effort).
update public.live_sessions
set trending_score = 0
where trending_score is null;

create index if not exists live_sessions_trending_order_idx
  on public.live_sessions (trending_score desc, started_at desc)
  where is_live = true;

create or replace function public.update_live_session_trending_scores(window_minutes integer default 5)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
  w integer;
begin
  w := greatest(1, least(coalesce(window_minutes, 5), 60));

  with live_channels as (
    select channel_id, viewer_count, started_at, created_at, updated_at
    from public.live_sessions
    where is_live = true
  ),
  likes as (
    select lc.channel_id, lc.count::bigint as like_count
    from public.live_like_counters lc
    join live_channels lch on lch.channel_id = lc.channel_id
  ),
  gifts_total as (
    select e.channel_id, sum(e.coin_cost)::bigint as coin_total
    from public.live_gift_events e
    join live_channels lch on lch.channel_id = e.channel_id
    group by e.channel_id
  ),
  gifts_recent as (
    select e.channel_id, sum(e.coin_cost)::bigint as coin_recent
    from public.live_gift_events e
    join live_channels lch on lch.channel_id = e.channel_id
    where e.created_at >= now() - make_interval(mins => w)
    group by e.channel_id
  ),
  scored as (
    select
      lch.channel_id,
      (
        (coalesce(lch.viewer_count, 0) * 10)::double precision
        + ln((coalesce(l.like_count, 0) + 1)::double precision) * 3
        + ln((coalesce(gt.coin_total, 0) + 1)::double precision) * 5
        + ln((coalesce(gr.coin_recent, 0) + 1)::double precision) * 8
        + (100 * exp(- (extract(epoch from (now() - coalesce(lch.started_at, lch.created_at, lch.updated_at, now()))) / 3600.0)))
      ) as score
    from live_channels lch
    left join likes l on l.channel_id = lch.channel_id
    left join gifts_total gt on gt.channel_id = lch.channel_id
    left join gifts_recent gr on gr.channel_id = lch.channel_id
  )
  update public.live_sessions ls
  set trending_score = scored.score
  from scored
  where ls.channel_id = scored.channel_id;

  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.update_live_session_trending_scores(integer) from public;
grant execute on function public.update_live_session_trending_scores(integer) to service_role;

-- Optional: auto-refresh trending scores every 5 minutes using pg_cron.
-- This is best-effort and will no-op if pg_cron is not available.
do $$
declare
  has_pg_cron boolean;
begin
  begin
    create extension if not exists pg_cron;
  exception
    when insufficient_privilege then
      null;
    when undefined_file then
      null;
  end;

  select exists(
    select 1
    from pg_extension
    where extname = 'pg_cron'
  ) into has_pg_cron;

  if has_pg_cron then
    begin
      if not exists (
        select 1
        from cron.job
        where jobname = 'live_sessions_trending_scores_5m'
      ) then
        perform cron.schedule(
          'live_sessions_trending_scores_5m',
          '*/5 * * * *',
          'select public.update_live_session_trending_scores(5);'
        );
      end if;
    exception
      when undefined_table then null;
      when undefined_function then null;
      when undefined_column then null;
      when invalid_schema_name then null;
      when insufficient_privilege then null;
      when others then null;
    end;
  end if;
end $$;
