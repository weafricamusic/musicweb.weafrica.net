-- Seed ad units for WeAfrica Music
-- Safe to run multiple times (uses ON CONFLICT DO NOTHING)

create table if not exists ads (
  id serial primary key,
  name text not null,
  ad_unit_id text not null,
  platform text,
  format text,
  placement text,
  country text,
  is_active boolean default true,
  created_at timestamptz default now(),
  constraint uniq_ad_unit unique(ad_unit_id)
);
-- Insert known ad units
insert into ads (name, ad_unit_id, platform, format, placement, country)
values
  ('WeAfrica_Banner_Android_Home','ca-app-pub-5041738275497275/6690144731','android','banner','home','MW'),
  ('WeAfrica_Interstitial_Main','ca-app-pub-5041738275497275/9380876933','android','interstitial','main','MW'),
  ('WeAfrica_Native_Android_Feed','ca-app-pub-5041738275497275/4543483227','android','native','feed','MW'),
  ('WeAfrica_Rewarded_Android_Main','ca-app-pub-5041738275497275/4891785829','android','rewarded','main','MW')
on conflict (ad_unit_id) do nothing;
-- You can extend this file with platform=ios variants or additional targeting rules.;
