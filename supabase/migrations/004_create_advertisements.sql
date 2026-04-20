-- Create advertisement system tables for WeAfrica Music
-- advertisements: campaigns created/managed by Admin
-- ad_impressions: records of views
-- ad_clicks: records of clicks
-- advertiser_companies: optional company metadata

create table if not exists advertiser_companies (
  id serial primary key,
  name text not null,
  contact_email text,
  contact_phone text,
  created_at timestamptz default now()
);
create table if not exists advertisements (
  id serial primary key,
  title text not null,
  company_id integer references advertiser_companies(id) on delete set null,
  company_name text,
  ad_type text not null, -- banner | video | sponsored | popup
  media_url text,
  cta_text text,
  cta_link text,
  target_country text,
  target_city text,
  target_user_role text,
  content_type text,
  budget numeric default 0,
  currency text default 'MWK',
  start_date timestamptz,
  end_date timestamptz,
  frequency_limit integer default 0, -- max views per user per day (0 = unlimited)
  status text default 'draft', -- draft | active | paused | ended
  metadata jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_advertisements_status on advertisements(status);
create index if not exists idx_advertisements_company on advertisements(company_id);
create index if not exists idx_advertisements_start_end on advertisements(start_date, end_date);
create table if not exists ad_impressions (
  id serial primary key,
  ad_id integer not null references advertisements(id) on delete cascade,
  user_id text,
  viewed_at timestamptz default now()
);
create index if not exists idx_ad_impressions_ad on ad_impressions(ad_id);
create index if not exists idx_ad_impressions_user on ad_impressions(user_id);
create table if not exists ad_clicks (
  id serial primary key,
  ad_id integer not null references advertisements(id) on delete cascade,
  user_id text,
  clicked_at timestamptz default now()
);
create index if not exists idx_ad_clicks_ad on ad_clicks(ad_id);
create index if not exists idx_ad_clicks_user on ad_clicks(user_id);
-- Optional: invoices / billing table for campaigns
create table if not exists ad_invoices (
  id serial primary key,
  company_id integer references advertiser_companies(id) on delete set null,
  ad_id integer references advertisements(id) on delete set null,
  amount numeric not null,
  currency text default 'MWK',
  paid boolean default false,
  payment_provider text,
  provider_ref text,
  created_at timestamptz default now()
);
create index if not exists idx_ad_invoices_company on ad_invoices(company_id);
-- Seed a sample admin demo ad (optional)
insert into advertisements (title, company_name, ad_type, media_url, cta_text, cta_link, target_country, status)
values ('WeAfrica Promo','WeAfrica','banner', null, 'Open App', 'weafrica://promo', 'MW', 'active')
on conflict do nothing;
