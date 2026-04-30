-- Migration: Create saved_albums table for library functionality
-- Fixes 404 error: saved_albums table not found

-- Create saved_albums table
CREATE TABLE IF NOT EXISTS public.saved_albums (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  album_id UUID NOT NULL REFERENCES public.albums(id) ON DELETE CASCADE,
  saved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, album_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS saved_albums_user_id_idx ON public.saved_albums(user_id, saved_at DESC);
CREATE INDEX IF NOT EXISTS saved_albums_album_id_idx ON public.saved_albums(album_id);
CREATE INDEX IF NOT EXISTS saved_albums_created_at_idx ON public.saved_albums(created_at DESC);

-- Enable Row Level Security
ALTER TABLE public.saved_albums ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own saved albums"
  ON public.saved_albums
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid()::TEXT);

CREATE POLICY "Users can save albums"
  ON public.saved_albums
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid()::TEXT);

CREATE POLICY "Users can unsave albums"
  ON public.saved_albums
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid()::TEXT);

-- Allow public read access to album data through the join
CREATE POLICY "Anyone can view album details through saved_albums"
  ON public.saved_albums
  FOR SELECT
  TO authenticated
  USING (TRUE);

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER saved_albums_set_updated_at
  BEFORE UPDATE ON public.saved_albums
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- Grant permissions
GRANT SELECT, INSERT, DELETE ON public.saved_albums TO authenticated;