-- Normalize Malawi country codes on songs.
-- Some clients historically wrote `country = 'Malawi'` and/or `country_code = 'Malawi'`.
-- Consumer feeds commonly filter by ISO2 `country_code` (e.g., 'MW'), so normalize existing rows.

DO $$
BEGIN
  IF to_regclass('public.songs') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'songs' AND column_name = 'country_code'
     ) THEN

    -- Fix obvious bad values.
    UPDATE public.songs
      SET country_code = 'MW'
      WHERE country_code IS NOT NULL
        AND btrim(country_code) <> ''
        AND lower(btrim(country_code)) = 'malawi';

    -- Fix missing/blank country_code when country looks like Malawi.
    UPDATE public.songs
      SET country_code = 'MW'
      WHERE (country_code IS NULL OR btrim(country_code) = '' OR lower(btrim(country_code)) = 'malawi')
        AND country IS NOT NULL
        AND lower(country) LIKE '%malawi%';

  END IF;
END $$;
