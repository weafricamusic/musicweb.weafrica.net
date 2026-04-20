# 🎭 WE AFRICAN STAGE — Complete Platform Specification

**Document Status:** Final · v1.0  
**Prepared for:** We African Platform  
**Classification:** Product Specification · No Code  
**Date:** February 27, 2026

---

## Executive Summary
A professional live battle platform for African DJs, Artists, and Radio hosts where creators compete and fans support with gifts. Built in 10 phases with theatrical psychology, premium aesthetics, and sustainable creator economy.

---

# 📋 PART 1: SYSTEM MAP

## Client Applications
| App | Purpose | Access |
|-----|---------|--------|
| **Viewer App** | Watch battles, send gifts, comment | All users |
| **Creator Studio** | Same app, gated by role/tier | Tier: Rising+ |

## Technology Layers
```
┌─────────────────────────────────────────────┐
│         CLIENT LAYER                         │
│  Viewer App · Creator Studio (Flutter)       │
├─────────────────────────────────────────────┤
│         REALTIME LAYER                        │
│  • Agora RTC: Live audio/video streaming     │
│  • Agora RTM: Chat + gift events             │
│  • WebSockets: Score updates                  │
├─────────────────────────────────────────────┤
│         BACKEND LAYER                          │
│  • Auth + User Profiles                       │
│  • Creator Tiers + Verification                │
│  • Battles + Modes                             │
│  • Gifts + Coins + Wallet                      │
│  • Rankings + Leaderboards                      │
│  • Moderation Tools                             │
├─────────────────────────────────────────────┤
│         OPERATIONS LAYER                       │
│  • Admin Console                               │
│  • Analytics/Telemetry                         │
│  • Fraud Controls                              │
│  • Audit Logs                                  │
│  • Customer Support Workflows                   │
├─────────────────────────────────────────────┤
│         MESSAGING LAYER                        │
│  • Push Notifications                          │
│  • In-App Inbox                                │
└─────────────────────────────────────────────┘
```

---

# 🎭 PART 2: IDENTITY, ROLES & TIERS

## User Roles (Multi-role allowed)
| Role | Capabilities |
|------|--------------|
| **Viewer** | Watch, comment, gift, follow, share |
| **DJ** | Create battles, stream music, accept challenges |
| **Artist** | Solo performances, collaborate, sell tickets |
| **Radio Host** | Talk sessions, interviews, call-ins |
| **Moderator** | Monitor streams, remove violations, verify creators |
| **Admin** | Full control, approvals, payouts |

## Creator Tiers (Source of Truth)
| Tier | Access Method | Payout Split | Features |
|------|---------------|--------------|----------|
| **Rising** | Auto-approved (50 followers, phone verified, tutorial) | 70% | Basic streaming, Stage access |
| **Verified** | Manual review (500 followers, 10+ streams, ID) | 80% | Badge, featured placement |
| **Elite** | Invite-only (top 1%) | 90% | Championship card, homepage |

## Verification State Machine
```
not_creator → applied → tutorial_pending → rising_active → 
verified_pending_review → verified_active → elite_active
                                    ↳ rejected/suspended
```

---

# 🎬 PART 3: CORE USER JOURNEYS

## Journey 1: Become a Creator (Rising)
```
1. User taps "Become Creator"
2. System checks: 50 followers? Phone verified?
3. If no → "Build audience first" screen
4. If yes → 2-minute platform tutorial
5. Complete tutorial → Tier: RISING granted
6. "THE STAGE" unlocked
```

## Journey 2: Enter Stage (Any Mode)
```
1. Tap "THE STAGE" from home
2. View 4 premium cards (DJ, Artist, Concert, Radio)
3. Select mode → Configuration Room opens
4. Configure using panel modules (not forms)
5. Tap "ENTER STAGE" (gold button)
6. 5-second cinematic countdown begins
7. Gold flash → Live session starts
```

## Journey 3: Viewer Experience
```
1. Discover battles (Featured/Live Now/Upcoming/Following)
2. Enter battle room (split screen)
3. Watch, comment, send gifts
4. Tap left side → Gift to Artist 1
5. Tap right side → Gift to Artist 2
6. See real-time score updates
7. Follow/share after battle
```

## Journey 4: Post-Session
```
1. Battle ends → Results screen
2. Winner announced with animation
3. Highlights eligible for replay
4. Moderation review triggers
5. Earnings added to wallet
6. Rankings updated
```

---

# 📱 PART 4: INFORMATION ARCHITECTURE

## Creator Surfaces
| Screen | Purpose |
|--------|---------|
| **THE STAGE Hub** | 4-card grid (DJ, Artist, Concert, Radio) + hidden Elite card |
| **Configuration Rooms** | Mode-specific setup with panel modules |
| **5-Second Countdown** | Cinematic entrance ritual |
| **Live Session** | Split view, timer, scores, comments, gifts |
| **Creator Wallet** | Balance, earnings history, withdrawal requests |
| **Creator Profile** | Tier badge, stats, past sessions, schedule |

## Viewer Surfaces
| Screen | Purpose |
|--------|---------|
| **Discovery** | Featured, Live Now, Upcoming, Following |
| **Watch Live** | Comments, gifting, reactions, share, follow |
| **Viewer Profile** | Badges, purchases, following list |

## Moderator/Admin Surfaces
| Screen | Purpose |
|--------|---------|
| **Live Monitoring** | Streams list, flags, quick actions |
| **Reports Queue** | Appeals, strike management |
| **Verification Review** | Manual approval for Verified tier |
| **Payout Management** | Withdrawals, holds, audit |
| **Content Policy** | Keywords, thresholds, rules |

---

# 🧩 PART 5: DOMAIN MODULES

## 5.1 Users & Social Graph
- Profiles with verification status
- Follow/unfollow
- Follower counts (used for Rising eligibility)
- Blocks/mutes

## 5.2 Creator Program
- Tier rules engine
- Verification artifacts storage
- Tutorial completion tracking
- Approvals workflow
- Suspensions/appeals

## 5.3 Sessions (Modes)

### DJ Battle
```
- Type: 1v1 / Tag Team
- Opponent: Invite specific / Open challenge
- Duration: 15/30/60 minutes
- Target: Gift goal (10K/50K/100K/custom)
```

### Artist Mode
```
- Type: Original / Cover / Collaboration
- Background: Select from library / Upload
- Tickets: Free / Paid (price tiers)
```

### Concert Mode
```
- Venue: Virtual / Hybrid / Physical
- Schedule: Date, time, duration
- Tickets: Early, General, VIP pricing
```

### Radio Session
```
- Type: Interview / Talk Show / Call-in
- Guest: Invite co-host/guest
- Call-in: Enable with screening
```

## 5.4 Realtime Engagement
- Comments stream with moderation hooks
- Gift stream with animation metadata
- Score engine (gift value × multiplier)
- Live leaderboards

## 5.5 Economy
| Component | Description |
|-----------|-------------|
| **Diamonds** | Purchased via IAP (in-app purchase) |
| **Gifts** | Convert diamonds → send to artists |
| **Earnings** | Creator share (by tier) from gifts |
| **Wallet** | Balance, holds, available for withdrawal |
| **Payouts** | Weekly/monthly withdrawals to bank/mobile money |

## 5.6 Rankings & Competition
| Timeline | Structure |
|----------|-----------|
| **Weekly** | Top DJs by gift volume, Top Artists by engagement |
| **Monthly** | Regional brackets, tournament style, prize pools |
| **Continental** | Pan-African leaderboards, country filters |

## 5.7 Safety & Moderation
| Phase | Actions |
|-------|---------|
| **Pre-live** | Verification check, guideline acknowledgment, audio check |
| **During live** | Mute chat, remove user, end stream |
| **Post-live** | Review, strikes (3 strikes = ban), appeals |

---

# 📊 PART 6: DATA MODEL (Conceptual)

## Core Entities & Relationships

```
USER
├── id (PK)
├── role set [viewer, dj, artist, radio, moderator, admin]
├── phone_verified (boolean)
├── follower_count
├── status [active, suspended, banned]
└── created_at

CREATOR_PROFILE
├── id (PK)
├── user_id (FK → USER)
├── tier [rising, verified, elite]
├── genres [afrobeat, amapiano, etc.]
├── verification_state [pending, active, rejected]
├── badges []
├── payout_split [70, 80, 90]
└── verification_artifacts (ID/docs)

SESSION
├── id (PK)
├── mode [dj_battle, artist, concert, radio]
├── host_id (FK → USER)
├── guest_ids [] (opponents/guests)
├── config (JSON snapshot of settings)
├── status [scheduled, live, ended, cancelled]
├── start_time
├── end_time
└── stream_channel_id (Agora reference)

BATTLE_STATE
├── id (PK)
├── session_id (FK → SESSION)
├── contestant_a_score
├── contestant_b_score
├── contestant_a_gifts_total
├── contestant_b_gifts_total
├── winner_id
└── last_updated

GIFT_EVENT
├── id (PK)
├── sender_id (FK → USER)
├── receiver_side [A, B]
├── session_id (FK → SESSION)
├── gift_type [fire, love, diamond, crown, etc.]
├── value (coin amount)
├── timestamp
└── tier_at_time [rising, verified, elite] (for payout calc)

COMMENT_EVENT
├── id (PK)
├── sender_id (FK → USER)
├── session_id (FK → SESSION)
├── text
├── flags []
├── moderation_state [clean, flagged, removed]
└── timestamp

TRANSACTION
├── id (PK)
├── user_id (FK → USER)
├── type [purchase, spend, earn, withdrawal, fee]
├── amount
├── currency [diamond, real]
├── status [pending, completed, failed, held]
├── timestamp
├── external_ref (IAP receipt, payout ID)
└── audit_metadata

RANKING_SNAPSHOT
├── id (PK)
├── period [weekly, monthly, continental]
├── category [dj, artist, radio]
├── entries [] (ranked user_ids with scores)
└── generated_at

MODERATION_CASE
├── id (PK)
├── session_id (FK → SESSION) OR user_id (FK → USER)
├── reason
├── evidence_refs []
├── actions_taken []
├── outcome [warning, strike, suspension, ban]
└── resolved_by (FK → USER - moderator)
```

---

# ⚡ PART 7: REALTIME CONTRACTS

## Low-Latency Channels
| Channel | Content | Latency Requirement |
|---------|---------|---------------------|
| **Comments** | User messages, moderation flags | < 500ms |
| **Gifts** | Gift events with animation metadata | < 200ms |
| **Scores** | Updated totals for both sides | < 100ms |
| **Viewer count** | Live audience size | < 2s |
| **Timer sync** | Battle countdown | < 500ms |

## Critical Rules
- **Idempotency**: Gift events must be deduplicated (network retries shouldn't double-count)
- **Ordering**: Events processed in correct sequence for accurate scoring
- **Authoritative scoring**: Server calculates final scores; clients only render
- **Tier snapshot**: Store creator's tier at gift time on earning record (for audit)

---

# 🔒 PART 8: FEATURE GATING RULES

| Feature | Required Tier |
|---------|---------------|
| THE STAGE access | Rising+ |
| DJ Battle mode | Rising+ |
| Artist Mode | Rising+ |
| Concert Mode | Rising+ |
| Radio Session | Rising+ |
| Championship card | Elite only |
| Verified badge | Verified+ |
| Featured placement | Verified+ |
| Homepage feature | Elite only |
| 90% payout split | Elite only |

**Enforcement**: All gates checked at API level and UI level.

---

# 🛠 PART 9: OPERATIONAL REQUIREMENTS

## Auditability
- Immutable ledgers for all transactions
- Each gift traceable: purchase → spend → earning
- Audit logs for all moderator/admin actions
- Session state snapshots for dispute resolution

## Fraud & Risk Controls
| Control | Implementation |
|---------|----------------|
| **Rate limits** | Max gifts per minute, comments per second |
| **Suspicious purchase** | Flag unusual spending patterns |
| **Chargeback handling** | Reverse earnings, deduct from wallet |
| **Payout holds** | Hold for new creators, suspicious activity |
| **Device signals** | Link accounts by device ID |
| **Age verification** | Where legally required |

## Reliability
- Session state recovery on disconnect
- Graceful reconnect behavior
- End-of-stream handling (no abrupt cuts)
- Results finalized in dispute-safe manner

## Compliance Basics
- Age gating (18+ where required)
- Data retention policy (30/90/365 days)
- User report handling SLA (24h for critical)
- Content moderation turnaround targets

---

# 🚀 PART 10: PHASED BUILD ORDER

## PHASE 1 — Foundation (Weeks 1-4)
```
✅ User roles system
✅ Creator application flow (50 followers)
✅ Phone verification
✅ Basic profile creation
```

## PHASE 2 — THE STAGE (Weeks 3-5)
```
✅ Stage hub (4 cards)
✅ DJ Battle configuration room
✅ Artist Mode configuration
✅ Basic streaming integration
```

## PHASE 3 — Live Experience (Weeks 5-7)
```
✅ Split screen battle
✅ Live score system
✅ Timer
✅ Basic comments
```

## PHASE 4 — Gift System (Weeks 7-9)
```
✅ Diamond purchases (IAP)
✅ Gift catalog (fire, love, mic drop)
✅ Gift animations
✅ Gift-to-score conversion
```

## PHASE 5 — Configuration Rooms (Weeks 8-10)
```
✅ Concert Mode config
✅ Radio Session config
✅ All modules finalized
✅ Configuration persistence
```

## PHASE 6 — The Entrance (Weeks 9-11)
```
✅ 5-second cinematic countdown
✅ Stage lighting effects
✅ Audio ambiance (crowd, heartbeat)
✅ Gold flash transition
```

## PHASE 7 — Rankings (Weeks 10-12)
```
✅ Weekly rankings
✅ Monthly championships
✅ Continental leaderboards
✅ Trophy/badge system
```

## PHASE 8 — Creator Economy (Weeks 11-14)
```
✅ Wallet system
✅ Earnings calculation by tier
✅ Withdrawal requests
✅ Payout provider integration
```

## PHASE 9 — Moderation (Weeks 13-15)
```
✅ Live monitoring dashboard
✅ Report/submit system
✅ Strike management
✅ Appeals workflow
```

## PHASE 10 — Viewer Polish (Weeks 14-16)
```
✅ Discovery screens (Featured, Live Now)
✅ Following feed
✅ Share/invite flows
✅ Viewer profile badges
```

---

# 📝 PART 11: LAUNCH CHECKLIST

## Pre-Launch
```
☐ User roles & verification
☐ Rising tier auto-approval
☐ THE STAGE hub (4 cards)
☐ DJ Battle mode end-to-end
☐ Basic gift system
```

## Alpha Test (50 creators)
```
☐ All 4 modes functional
☐ Countdown ritual
☐ Comments working
☐ Scores updating
☐ Basic moderation
```

## Beta Test (500 creators)
```
☐ Full gift catalog
☐ Wallet & earnings
☐ Weekly rankings
☐ Report system
☐ Performance optimization
```

## Soft Launch
```
☐ Verified tier reviews
☐ Payment integration
☐ Withdrawal processing
☐ Analytics dashboard
☐ Support workflows
```

## Public Launch
```
☐ Marketing campaign
☐ Elite invitations
☐ Championship events
☐ Press kit
☐ Community management
```

---

# 🎯 PART 12: KEY DIFFERENTIATORS

| TikTok | WE AFRICAN STAGE |
|--------|------------------|
| "Go Live" | **"ENTER STAGE"** |
| Instant stream | **5-second cinematic countdown** |
| Generic UI | **African premium aesthetic** |
| One format | **4 professional modes** |
| Flat cards | **Stage panels with depth** |
| Basic gifts | **Tiered gift animations** |
| No rankings | **Continental leaderboards** |
| No tiers | **Rising/Verified/Elite progression** |
| 70% payout | **Up to 90% for Elite** |
| Global | **Pan-African focus** |

---

# 🔥 FINAL SUMMARY

```
┌─────────────────────────────────────────────────────────┐
│                    WE AFRICAN STAGE                      │
│                                                          │
│  🎭 IDENTITY: Viewer · DJ · Artist · Radio · Mod · Admin │
│  🏆 TIERS: Rising → Verified → Elite                     │
│  🎬 JOURNEY: Discover → Enter Stage → Configure → Live   │
│  📱 SCREENS: Stage Hub · Config Rooms · Countdown · Live │
│  🧩 MODULES: Battles · Gifts · Wallet · Rankings         │
│  ⚡ REALTIME: Comments · Gifts · Scores · Timer          │
│  🔒 GATES: Tier-based feature access                     │
│  🛠 OPS: Audit · Fraud · Moderation · Support            │
│  🚀 PHASES: 10-phase build → 16-week launch              │
│                                                          │
│         AFRICA'S PREMIER LIVE BATTLE PLATFORM            │
│                      🎭🔥📱💎                            │
└─────────────────────────────────────────────────────────┘
```
