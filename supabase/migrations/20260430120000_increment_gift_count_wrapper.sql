-- Wrapper: increment_gift_count(session_id, increment) -> calls increment_feed_item_count for 'live' gift_count
CREATE OR REPLACE FUNCTION public.increment_gift_count(
  p_session_id text,
  p_increment int DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM public.increment_feed_item_count('live', p_session_id, 'gift_count', p_increment);
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_gift_count(text, int) TO service_role;
