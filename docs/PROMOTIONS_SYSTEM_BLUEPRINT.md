# Promotions System Blueprint

This repo now treats promotions as one system with four connected layers:

1. Database lifecycle
2. Admin operations
3. Feed scoring
4. In-app visual indicators

## Database

Primary tables:

- `public.promotions`
  - canonical active/completed campaign record
  - stores `content_id`, `content_type`, `plan`, `status`, schedule, social links, and feed bonus metadata
- `public.paid_promotions`
  - creator-submitted queue for review
  - stores `plan`, `coins`, `duration_days`, review metadata, and handoff into `promotions`
- `public.promotion_posts`
  - per-platform posting log for `facebook`, `instagram`, `x`, `whatsapp`
- `public.promotion_events`
  - view/click/engagement telemetry for promotion reporting
- `public.active_content_promotions`
  - view of live content promotions with computed `promotion_bonus`

Alignment migration:

- `admin_dashboard/supabase/migrations/20260328120000_promotions_system_alignment.sql`

## Status Flow

Creator flow:

`pending -> approved -> active -> completed`

Operational variants:

- `rejected`
- `paused`
- `cancelled`
- `ended`

`paid_promotions` is the request queue.
`promotions` is the live campaign record.

## Plans

Plans are normalized in `admin_dashboard/src/lib/admin/promotions.ts`.

Current tiers:

- `basic`
  - `50` coins
  - in-app boost only
- `pro`
  - `200` coins
  - stronger feed weight
  - Facebook + Instagram workflow
- `premium`
  - `500` coins
  - strongest feed weight
  - all social platforms
  - featured/banner treatment

## Feed Scoring

Track feed ranking now uses a promotion-aware score in Flutter when songs are fetched for feed-oriented sections.

Base score:

- likes weight: `1.0`
- plays weight: `0.5`
- recency weight: latest 30 days

Promotion bonus:

- `500 * days_remaining * plan_weight * boost_multiplier`

Plan weights:

- `basic = 1`
- `pro = 2`
- `premium = 3`

Relevant code:

- `lib/features/tracks/tracks_repository.dart`
- `lib/features/tracks/track.dart`

## App Indicators

Tracks enriched with active promotion metadata expose badge labels:

- `premium -> PROMOTED`
- `pro -> BOOSTED`
- `basic -> SPONSORED`

Current badge rendering is applied in the home feed cards:

- `lib/features/home/home_tab.dart`

## Admin Operations View

The Growth campaigns page is now the top-level promotions operations view:

- totals for total/pending/active/completed
- plan economics
- status flow summary
- active promotions table
- pending approval table
- completed promotions table
- social action links and generated caption text

Relevant code:

- `admin_dashboard/src/app/admin/growth/promotions/campaigns/page.tsx`

## Social Channels

Default official links:

- Facebook: `https://www.facebook.com/share/1DzRfNVBSc/`
- Instagram: `https://www.instagram.com/weafricamusic?igsh=b3l0eHc3cm5zNmQx`
- X: `https://x.com/WeafricaMusic`
- WhatsApp: `https://whatsapp.com/channel/0029VbCKK5V0gcfObTkWfT12`

These are centralized in:

- `admin_dashboard/src/lib/admin/promotions.ts`

## Notes

- The admin overview tolerates partial schema rollout, but the alignment migration should be applied before relying on the full workflow.
- Instagram remains a manual posting workflow. The dashboard provides the destination link and reusable caption text.