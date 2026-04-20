-- Allow photo + song social posts to be persisted and tracked in feed tables.

DO $$
BEGIN
  BEGIN
    ALTER TABLE public.feed_items
      DROP CONSTRAINT IF EXISTS feed_items_item_type_check;
  EXCEPTION
    WHEN undefined_object THEN NULL;
  END;

  ALTER TABLE public.feed_items
    ADD CONSTRAINT feed_items_item_type_check
    CHECK (item_type IN ('live', 'battle', 'song', 'video', 'event', 'photo_post'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  BEGIN
    ALTER TABLE public.engagement_events
      DROP CONSTRAINT IF EXISTS engagement_events_target_type_check;
  EXCEPTION
    WHEN undefined_object THEN NULL;
  END;

  ALTER TABLE public.engagement_events
    ADD CONSTRAINT engagement_events_target_type_check
    CHECK (target_type IN ('live', 'battle', 'song', 'video', 'artist', 'event', 'photo_post'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
