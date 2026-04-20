-- Creates payout request table for the artist dashboard.
-- Safe to run multiple times.

create extension if not exists pgcrypto;

create table if not exists public.payout_requests (
  id uuid primary key default gen_random_uuid(),

  -- Firebase artist UID (string)
  artist_uid text not null,

  -- pending | approved | rejected | paid
  status text not null default 'pending',

  -- mobile_money | bank
  method text not null,

  -- Requested amount
  amount_coins bigint not null,
  amount_mwk numeric,
  coin_to_mwk_rate numeric,

  -- Payout details (nullable depending on method)
  phone text,
  bank_name text,
  account_number text,
  account_name text,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint payout_requests_status_check check (status in ('pending', 'approved', 'rejected', 'paid')),
  constraint payout_requests_method_check check (method in ('mobile_money', 'bank')),
  constraint payout_requests_amount_coins_positive check (amount_coins > 0)
);

create index if not exists payout_requests_artist_uid_idx on public.payout_requests (artist_uid);
create index if not exists payout_requests_created_at_idx on public.payout_requests (created_at desc);
create index if not exists payout_requests_artist_uid_created_at_idx on public.payout_requests (artist_uid, created_at desc);

-- Recommended: keep RLS enabled by default. This dashboard uses the Supabase service role
-- key server-side (bypasses RLS), so policies are optional here.
alter table public.payout_requests enable row level security;
