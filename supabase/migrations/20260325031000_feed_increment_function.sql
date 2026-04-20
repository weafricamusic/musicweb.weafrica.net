create or replace function public.increment_feed_item_count(
  p_type text,
  p_item_id text,
  p_field text,
  p_increment integer default 1
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_increment integer := greatest(coalesce(p_increment, 1), 1);
begin
  if p_type is null or btrim(p_type) = '' then
    raise exception 'type_required' using errcode = 'P0001';
  end if;

  if p_item_id is null or btrim(p_item_id) = '' then
    raise exception 'item_id_required' using errcode = 'P0001';
  end if;

  if p_field = 'view_count' then
    update public.feed_items
      set view_count = coalesce(view_count, 0) + v_increment,
          score = coalesce(score, 0) + v_increment,
          updated_at = now()
    where item_type = p_type
      and item_id = p_item_id;
  elsif p_field = 'like_count' then
    update public.feed_items
      set like_count = coalesce(like_count, 0) + v_increment,
          score = coalesce(score, 0) + (2 * v_increment),
          updated_at = now()
    where item_type = p_type
      and item_id = p_item_id;
  elsif p_field = 'gift_count' then
    update public.feed_items
      set gift_count = coalesce(gift_count, 0) + v_increment,
          score = coalesce(score, 0) + (5 * v_increment),
          updated_at = now()
    where item_type = p_type
      and item_id = p_item_id;
  elsif p_field = 'comment_count' then
    update public.feed_items
      set comment_count = coalesce(comment_count, 0) + v_increment,
          score = coalesce(score, 0) + v_increment,
          updated_at = now()
    where item_type = p_type
      and item_id = p_item_id;
  else
    raise exception 'unsupported_field:%', p_field using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.increment_feed_item_count(text, text, text, integer) from public;
grant execute on function public.increment_feed_item_count(text, text, text, integer) to service_role;

notify pgrst, 'reload schema';