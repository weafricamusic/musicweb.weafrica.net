-- Add unique constraint (index) to ensure subscription_plans(role, plan) is unique
-- This migration is safe to run multiple times (uses IF NOT EXISTS for the index name).

-- Create a unique index on (role, plan) to make inserts idempotent
create unique index if not exists idx_subscription_plans_role_plan on subscription_plans(role, plan);
-- Optional: If you want to ensure the existing seed uses ON CONFLICT (role, plan),
-- keep the seed in 001_create_subscriptions.sql updated to use that conflict clause.;
