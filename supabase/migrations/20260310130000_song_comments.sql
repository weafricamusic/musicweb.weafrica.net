-- Song comments (consumer engagement)
--
-- Creates `public.song_comments` for per-song comments.
-- - song_id: TEXT for schema flexibility (uuid/int/string-safe)
-- - user_id: TEXT (Firebase UID)
-- - display_name/avatar_url: optional cached identity for fast rendering
--
-- Also adds `songs.comments_count` (if songs is a table) and keeps it synced
-- via a SECURITY DEFINER trigger (works even when songs has FORCE RLS).
--
-- Idempotent and safe for existing environments.

DO $migration$
DECLARE
  songs_oid regclass;
  songs_relkind "char";
BEGIN
  CREATE EXTENSION IF NOT EXISTS pgcrypto;

  -- Create table if missing.
  IF to_regclass('public.song_comments') IS NULL THEN
    CREATE TABLE public.song_comments (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      song_id text NOT NULL,
      user_id text NOT NULL,
      comment text NOT NULL,
      display_name text,
      avatar_url text,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_song_comments_song_created
      ON public.song_comments (song_id, created_at DESC);

    CREATE INDEX IF NOT EXISTS idx_song_comments_user
      ON public.song_comments (user_id);
  END IF;

  -- Add comments_count column to songs when songs is a TABLE.
  songs_oid := to_regclass('public.songs');
  IF songs_oid IS NOT NULL THEN
    SELECT c.relkind
    INTO songs_relkind
    FROM pg_class c
    WHERE c.oid = songs_oid
    LIMIT 1;

    IF songs_relkind = 'r' THEN
      ALTER TABLE public.songs
        ADD COLUMN IF NOT EXISTS comments_count integer NOT NULL DEFAULT 0;

      CREATE INDEX IF NOT EXISTS idx_songs_comments_count
        ON public.songs (comments_count);
    END IF;
  END IF;

  -- Helper: recompute and persist comment count for a given song id.
  -- SECURITY DEFINER so it can update songs even under FORCE RLS.
  CREATE OR REPLACE FUNCTION public.weafrica_refresh_song_comments_count(p_song_id text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  DECLARE
    sid text;
    cnt integer;
    songs_tbl regclass;
    relkind_char "char";
    dt text;
  BEGIN
    sid := btrim(coalesce(p_song_id, ''));
    IF sid = '' THEN
      RETURN;
    END IF;

    songs_tbl := to_regclass('public.songs');
    IF songs_tbl IS NULL THEN
      RETURN;
    END IF;

    SELECT c.relkind
    INTO relkind_char
    FROM pg_class c
    WHERE c.oid = songs_tbl
    LIMIT 1;

    IF relkind_char <> 'r' THEN
      RETURN;
    END IF;

    SELECT count(*) INTO cnt
    FROM public.song_comments
    WHERE song_id = sid;

    -- Update songs.comments_count if it exists and is numeric.
    SELECT data_type INTO dt
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'songs'
      AND column_name = 'comments_count'
    LIMIT 1;

    IF dt IS NOT NULL AND dt IN ('smallint', 'integer', 'bigint', 'numeric') THEN
      EXECUTE 'UPDATE public.songs SET comments_count = $1 WHERE id::text = $2'
      USING cnt, sid;
    END IF;

    -- Compatibility: also update songs.comments if present and numeric.
    SELECT data_type INTO dt
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'songs'
      AND column_name = 'comments'
    LIMIT 1;

    IF dt IS NOT NULL AND dt IN ('smallint', 'integer', 'bigint', 'numeric') THEN
      EXECUTE 'UPDATE public.songs SET comments = $1 WHERE id::text = $2'
      USING cnt, sid;
    END IF;
  END;
  $$;

  -- Trigger: keep counts synced on insert/update/delete.
  CREATE OR REPLACE FUNCTION public.weafrica_song_comments_sync_counts()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  BEGIN
    IF TG_OP = 'INSERT' THEN
      PERFORM public.weafrica_refresh_song_comments_count(NEW.song_id);
      RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
      PERFORM public.weafrica_refresh_song_comments_count(OLD.song_id);
      RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
      PERFORM public.weafrica_refresh_song_comments_count(NEW.song_id);
      IF OLD.song_id IS DISTINCT FROM NEW.song_id THEN
        PERFORM public.weafrica_refresh_song_comments_count(OLD.song_id);
      END IF;
      RETURN NEW;
    END IF;

    RETURN NULL;
  END;
  $$;

  DROP TRIGGER IF EXISTS trg_song_comments_sync_counts ON public.song_comments;
  CREATE TRIGGER trg_song_comments_sync_counts
  AFTER INSERT OR UPDATE OR DELETE ON public.song_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.weafrica_song_comments_sync_counts();

  -- RLS: comments are public-readable; writes are expected via service_role (Edge Function).
  ALTER TABLE public.song_comments ENABLE ROW LEVEL SECURITY;

  BEGIN
    DROP POLICY IF EXISTS "Public read song_comments" ON public.song_comments;
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;

  CREATE POLICY "Public read song_comments"
    ON public.song_comments
    FOR SELECT
    TO anon, authenticated
    USING (true);

  -- Minimal grants (RLS still applies).
  GRANT SELECT ON public.song_comments TO anon, authenticated;

  -- Ask PostgREST to reload schema cache.
  PERFORM pg_notify('pgrst', 'reload schema');
END $migration$;
