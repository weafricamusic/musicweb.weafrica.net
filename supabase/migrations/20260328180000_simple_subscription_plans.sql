-- Simple migration that works regardless of current state.
--
-- IMPORTANT: do NOT drop `subscription_plans`.
-- Dropping with CASCADE removes foreign keys from other tables (e.g. user_subscriptions,
-- subscription_payments, paychangu_payments) and can silently degrade data integrity.

create extension if not exists pgcrypto;

-- 1) Ensure the table exists.
create table if not exists public.subscription_plans (
    id uuid primary key default gen_random_uuid(),
    plan_id text not null unique,
    audience text not null default 'consumer',
    role text not null default 'consumer',
    plan text not null,
    name text not null,
    price integer not null default 0,
    price_mwk integer not null default 0,
    billing_interval text not null default 'month',
    currency text not null default 'MWK',
    active boolean not null default true,
    sort_order integer not null default 0,
    features jsonb default '{}'::jsonb,
    marketing jsonb default '{}'::jsonb,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- 2) If a legacy table already exists, ensure the columns this migration relies on exist.
alter table public.subscription_plans
    add column if not exists id uuid,
    add column if not exists plan_id text,
    add column if not exists audience text,
    add column if not exists role text,
    add column if not exists plan text,
    add column if not exists name text,
    add column if not exists price integer,
    add column if not exists price_mwk integer,
    add column if not exists billing_interval text,
    add column if not exists currency text,
    add column if not exists active boolean,
    add column if not exists sort_order integer,
    add column if not exists features jsonb,
    add column if not exists marketing jsonb,
    add column if not exists created_at timestamptz,
    add column if not exists updated_at timestamptz;

-- Ensure key columns are non-null-ish before we attempt to de-dupe and index.
update public.subscription_plans
set
    role = coalesce(role, 'consumer'),
    billing_interval = coalesce(billing_interval, 'month'),
    plan = coalesce(plan, plan_id, md5(ctid::text) || '__legacy'),
    audience = coalesce(audience, role, 'consumer')
where role is null
   or billing_interval is null
   or plan is null
   or audience is null;

-- 3) If legacy data contains duplicate tuples, unique index creation will fail.
-- De-dupe by demoting all but one row per (role, plan, billing_interval) tuple.
with ranked as (
        select
        ctid,
                row_number() over (
                        partition by role, plan, billing_interval
                        order by
                                (plan_id in ('free', 'premium', 'platinum', 'premium_weekly', 'platinum_weekly')) desc,
                                created_at nulls last,
                                sort_order nulls last,
                id nulls last,
                ctid
                ) as rn
        from public.subscription_plans
)
update public.subscription_plans p
set
    plan = coalesce(p.plan_id, p.id::text, md5(p.ctid::text)) || '__legacy__' || md5(p.ctid::text),
        active = false,
        updated_at = now()
from ranked r
where p.ctid = r.ctid
    and r.rn > 1;

-- 4) Ensure the legacy uniqueness pattern exists (used by some older backends).
create unique index if not exists idx_subscription_plans_role_plan_interval
on public.subscription_plans (role, plan, billing_interval);

-- 4.5) Normalize canonical consumer plan_ids to expected tuples.
--
-- Why: this repo uses stable plan_id values ('free', 'premium', etc.) as foreign keys.
-- On some legacy databases those rows may exist but with different role/plan/billing_interval.
-- If a legacy row is already occupying the canonical tuple with a different plan_id,
-- first demote it to a legacy tuple so the canonical plan_id can take ownership.
update public.subscription_plans
set plan = coalesce(plan_id, id::text, md5(ctid::text)) || '__legacy__' || md5(ctid::text), active = false, updated_at = now()
where role = 'consumer' and plan = 'free' and billing_interval = 'month'
    and plan_id is distinct from 'free';

update public.subscription_plans
set plan = coalesce(plan_id, id::text, md5(ctid::text)) || '__legacy__' || md5(ctid::text), active = false, updated_at = now()
where role = 'consumer' and plan = 'premium' and billing_interval = 'month'
    and plan_id is distinct from 'premium';

update public.subscription_plans
set plan = coalesce(plan_id, id::text, md5(ctid::text)) || '__legacy__' || md5(ctid::text), active = false, updated_at = now()
where role = 'consumer' and plan = 'platinum' and billing_interval = 'month'
    and plan_id is distinct from 'platinum';

update public.subscription_plans
set plan = coalesce(plan_id, id::text, md5(ctid::text)) || '__legacy__' || md5(ctid::text), active = false, updated_at = now()
where role = 'consumer' and plan = 'premium_weekly' and billing_interval = 'week'
    and plan_id is distinct from 'premium_weekly';

update public.subscription_plans
set plan = coalesce(plan_id, id::text, md5(ctid::text)) || '__legacy__' || md5(ctid::text), active = false, updated_at = now()
where role = 'consumer' and plan = 'platinum_weekly' and billing_interval = 'week'
    and plan_id is distinct from 'platinum_weekly';

update public.subscription_plans p
set audience = 'consumer', role = 'consumer', plan = 'free', billing_interval = 'month'
where p.ctid = (
    select ctid
    from public.subscription_plans
    where plan_id = 'free'
    order by created_at nulls last, id nulls last, ctid
    limit 1
);

update public.subscription_plans p
set audience = 'consumer', role = 'consumer', plan = 'premium', billing_interval = 'month'
where p.ctid = (
    select ctid
    from public.subscription_plans
    where plan_id = 'premium'
    order by created_at nulls last, id nulls last, ctid
    limit 1
);

update public.subscription_plans p
set audience = 'consumer', role = 'consumer', plan = 'platinum', billing_interval = 'month'
where p.ctid = (
    select ctid
    from public.subscription_plans
    where plan_id = 'platinum'
    order by created_at nulls last, id nulls last, ctid
    limit 1
);

update public.subscription_plans p
set audience = 'consumer', role = 'consumer', plan = 'premium_weekly', billing_interval = 'week'
where p.ctid = (
    select ctid
    from public.subscription_plans
    where plan_id = 'premium_weekly'
    order by created_at nulls last, id nulls last, ctid
    limit 1
);

update public.subscription_plans p
set audience = 'consumer', role = 'consumer', plan = 'platinum_weekly', billing_interval = 'week'
where p.ctid = (
    select ctid
    from public.subscription_plans
    where plan_id = 'platinum_weekly'
    order by created_at nulls last, id nulls last, ctid
    limit 1
);

-- 5) Seed/update the basic plans (idempotent).
insert into public.subscription_plans (
    plan_id,
    audience,
    role,
    plan,
    name,
    price,
    price_mwk,
    billing_interval,
    currency,
    active,
    sort_order,
    features,
    marketing
) values
    (
        'free',
        'consumer',
        'consumer',
        'free',
        'Free',
        0,
        0,
        'month',
        'MWK',
        true,
        0,
        '{"ads":true}'::jsonb,
        '{"tagline":"Listen for free","bullets":["Ad-supported listening"]}'::jsonb
    ),
    (
        'premium',
        'consumer',
        'consumer',
        'premium',
        'Premium',
        15000,
        15000,
        'month',
        'MWK',
        true,
        10,
        '{"ads":false,"offline":true,"audio_quality":"320kbps","create_playlist":true,"watch_live_battles":true,"cancel_anytime":true}'::jsonb,
        '{"tagline":"Offline listening + live battles.","bullets":["Download to listen offline","High audio quality up to 320 kbps","Create playlists","Watch live artists/DJs battles","Cancel anytime"]}'::jsonb
    ),
    (
        'platinum',
        'consumer',
        'consumer',
        'platinum',
        'Platinum',
        20000,
        20000,
        'month',
        'MWK',
        true,
        20,
        '{"ads":false,"offline":true,"audio_quality":"24bit/44.1kHz","mix_playlist":true,"ai_dj":true,"watch_live_battles":true,"cancel_anytime":true}'::jsonb,
        '{"tagline":"Studio quality + AI DJ.","bullets":["Download to listen offline","Audio quality up to 24-bit/44.1kHz","Mix your playlist","Your personal AI DJ","Watch live artists/DJs battle streaming","Cancel anytime"]}'::jsonb
    ),
    (
        'premium_weekly',
        'consumer',
        'consumer',
        'premium_weekly',
        'Premium (Weekly)',
        3750,
        3750,
        'week',
        'MWK',
        true,
        11,
        '{"ads":false,"offline":true,"audio_quality":"320kbps","create_playlist":true,"watch_live_battles":true,"cancel_anytime":true}'::jsonb,
        '{"tagline":"Weekly premium access","bullets":["All premium features","Weekly billing","Cancel anytime"]}'::jsonb
    ),
    (
        'platinum_weekly',
        'consumer',
        'consumer',
        'platinum_weekly',
        'Platinum (Weekly)',
        5000,
        5000,
        'week',
        'MWK',
        true,
        21,
        '{"ads":false,"offline":true,"audio_quality":"24bit/44.1kHz","mix_playlist":true,"ai_dj":true,"watch_live_battles":true,"cancel_anytime":true}'::jsonb,
        '{"tagline":"Weekly platinum access","bullets":["All platinum features","Weekly billing","Cancel anytime"]}'::jsonb
    )
on conflict (role, plan, billing_interval) do update set
    audience = excluded.audience,
    name = excluded.name,
    price = excluded.price,
    price_mwk = excluded.price_mwk,
    currency = excluded.currency,
    active = excluded.active,
    sort_order = excluded.sort_order,
    features = excluded.features,
    marketing = excluded.marketing,
    updated_at = now();
