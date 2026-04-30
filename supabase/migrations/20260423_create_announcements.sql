-- Migration: Create announcements table for in-app notifications
-- Fixes 404 error: announcements table not found

-- Create announcements table
CREATE TABLE IF NOT EXISTS public.announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  image_url TEXT,
  action_type TEXT DEFAULT 'navigate', -- navigate, link, deep_link
  action_value TEXT, -- URL or route path
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  priority INTEGER NOT NULL DEFAULT 0, -- Higher = more important
  target_roles TEXT[], -- NULL means all roles, otherwise ['artist', 'dj', 'consumer']
  target_countries TEXT[], -- NULL means all countries, otherwise ['ZA', 'NG', 'KE']
  start_at TIMESTAMPTZ, -- NULL means immediately
  end_at TIMESTAMPTZ, -- NULL means no expiry
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS announcements_is_active_idx ON public.announcements(is_active);
CREATE INDEX IF NOT EXISTS announcements_priority_idx ON public.announcements(priority DESC);
CREATE INDEX IF NOT EXISTS announcements_created_at_idx ON public.announcements(created_at DESC);
CREATE INDEX IF NOT EXISTS announcements_active_date_range_idx 
  ON public.announcements(created_at DESC) 
  WHERE is_active = TRUE;

-- Enable Row Level Security
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Create policies (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'announcements'
      AND policyname = 'Anyone can view active announcements'
  ) THEN
    EXECUTE
      'CREATE POLICY "Anyone can view active announcements"
         ON public.announcements
         FOR SELECT
         TO authenticated
         USING (is_active = TRUE)';
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'announcements'
      AND policyname = 'Admins can manage announcements'
  ) THEN
    EXECUTE
      'CREATE POLICY "Admins can manage announcements"
         ON public.announcements
         FOR ALL
         TO authenticated
         USING (
           EXISTS (
             SELECT 1 FROM public.user_roles 
             WHERE user_id = auth.uid()::TEXT 
             AND role IN (''admin'', ''super_admin'')
           )
         )
         WITH CHECK (
           EXISTS (
             SELECT 1 FROM public.user_roles 
             WHERE user_id = auth.uid()::TEXT 
             AND role IN (''admin'', ''super_admin'')
           )
         )';
  END IF;
END;
$$;

-- Create updated_at trigger function (idempotent via CREATE OR REPLACE)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'announcements_set_updated_at'
      AND tgrelid = 'public.announcements'::regclass
  ) THEN
    EXECUTE
      'CREATE TRIGGER announcements_set_updated_at
         BEFORE UPDATE ON public.announcements
         FOR EACH ROW
         EXECUTE FUNCTION public.set_updated_at()';
  END IF;
END;
$$;

-- Grant permissions
GRANT SELECT ON public.announcements TO authenticated;
GRANT ALL ON public.announcements TO service_role;
