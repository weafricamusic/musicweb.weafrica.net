-- STEP 1.7 (PERFORMANCE): batch likes to reduce backend calls.

create or replace function public.increment_live_likes_by(
  p_channel_id text,
  p_delta bigint
)
returns bigint
language plpgsql
as $$
declare
  new_count bigint;
  delta bigint;
begin
  delta := greatest(1, least(coalesce(p_delta, 1), 1000));

  insert into public.live_like_counters(channel_id, count)
  values (p_channel_id, delta)
  on conflict (channel_id) do update
    set count = public.live_like_counters.count + delta,
        updated_at = now()
  returning count into new_count;

  return new_count;
end;
$$;
grant execute on function public.increment_live_likes_by(text, bigint) to anon, authenticated;
