import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import { asSubscriptionPlanId } from '@/lib/subscription/plans'
import { trySetSubscriptionClaims } from '@/lib/subscription/firebase-claims'
import { resolveCanonicalSubscriptionUserId } from '@/lib/subscription/resolve-user-id'
import type { SupabaseClient } from '@supabase/supabase-js'

export const runtime = 'nodejs'

type SetSubscriptionBody = {
  action: 'set_user_subscription'
  user_id: string
  plan_id: string
  months?: number
  duration_minutes?: number
  auto_renew?: boolean
  create_transaction?: boolean
  source?: string | null
}

type ExpireNowBody = {
	action: 'expire_user_subscription_now'
	user_id: string
	reason?: string | null
}

type Body = SetSubscriptionBody | ExpireNowBody

function asInt(value: unknown): number {
  if (typeof value === 'number') return Math.trunc(value)
  if (typeof value === 'string' && value.trim()) return Math.trunc(Number(value))
  return NaN
}

function addMonthsUtc(d: Date, months: number): Date {
  const out = new Date(d)
  out.setUTCMonth(out.getUTCMonth() + months)
  return out
}

async function tryLog(
  supabase: SupabaseClient,
  input: {
    admin_email: string | null
    action: string
    target_type: string
    target_id: string
    meta?: Record<string, unknown>
  },
) {
  try {
    const reason = typeof input.meta?.reason === 'string' ? input.meta.reason : null
    await supabase.from('admin_logs').insert({
      admin_email: input.admin_email,
      action: input.action,
      target_type: input.target_type,
      target_id: input.target_id,
      reason,
      meta: input.meta ?? {},
    })
  } catch {
    // best-effort
  }
}

export async function POST(req: Request) {
  const adminCtx = await getAdminContext()
  if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  try {
    assertPermission(adminCtx, 'can_manage_finance')
  } catch {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) {
    return NextResponse.json(
      { error: 'SUPABASE_SERVICE_ROLE_KEY is required (RLS is deny-all).' },
      { status: 500 },
    )
  }

  const body = (await req.json().catch(() => null)) as Body | null
  if (!body || typeof body !== 'object' || !('action' in body)) {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
  }

  if (body.action !== 'set_user_subscription' && body.action !== 'expire_user_subscription_now') {
    return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
  }

  if (body.action === 'expire_user_subscription_now') {
    const inputUserId = String(body.user_id ?? '').trim()
    if (!inputUserId) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })
    const resolved = await resolveCanonicalSubscriptionUserId({ supabase, userId: inputUserId })
    const userId = resolved.canonicalUserId
    const lookupUserIds = Array.from(new Set([userId, inputUserId].filter(Boolean)))
    if (!userId) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })
    const nowIso = new Date().toISOString()
    const { data, error } = await supabase
      .from('user_subscriptions')
      .update({ status: 'expired', ends_at: nowIso, auto_renew: false, updated_at: nowIso })
      .in('user_id', lookupUserIds)
      .eq('status', 'active')
      .select('id')
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    const expired = data?.length ?? 0

		await trySetSubscriptionClaims(userId, { plan_id: 'free', status: 'expired', ends_at: nowIso })

    await tryLog(supabase, {
      admin_email: adminCtx.admin.email,
      action: 'subscriptions.expire_user_subscription_now',
      target_type: 'user',
      target_id: userId,
      meta: {
        reason: body.reason ?? null,
        affected: expired,
        ...(resolved.inputUserId && resolved.inputUserId !== userId
          ? { input_user_id: resolved.inputUserId, canonical_user_id: userId, resolved_via: resolved.resolvedVia }
          : null),
      },
    })

    return NextResponse.json({ ok: true, expired })
  }

  const inputUserId = String(body.user_id ?? '').trim()
  const planId = asSubscriptionPlanId(body.plan_id)
  if (!inputUserId) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })
  if (!planId) return NextResponse.json({ error: 'Invalid plan_id' }, { status: 400 })

  const resolved = await resolveCanonicalSubscriptionUserId({ supabase, userId: inputUserId })
  const userId = resolved.canonicalUserId
  const lookupUserIds = Array.from(new Set([userId, inputUserId].filter(Boolean)))
  if (!userId) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })

  const durationMinutesRaw = (body as SetSubscriptionBody).duration_minutes
  const durationMinutes = durationMinutesRaw == null ? null : asInt(durationMinutesRaw)
  if (durationMinutes != null && (!Number.isFinite(durationMinutes) || durationMinutes <= 0 || durationMinutes > 60 * 24 * 30)) {
    return NextResponse.json({ error: 'duration_minutes must be between 1 and 43200' }, { status: 400 })
  }

  const monthsRaw = body.months == null ? null : asInt(body.months)
  const months = monthsRaw == null ? (planId === 'free' ? 0 : 1) : monthsRaw
  if (!Number.isFinite(months) || months < 0 || months > 24) {
    return NextResponse.json({ error: 'months must be between 0 and 24' }, { status: 400 })
  }

  const autoRenew = body.auto_renew == null ? (durationMinutes ? false : planId !== 'free') : !!body.auto_renew
  const createTx = body.create_transaction == null ? (durationMinutes ? false : planId !== 'free') : !!body.create_transaction
  const source = (body.source ?? null) || 'admin_dashboard'

  const country = await getAdminCountryCode().catch(() => 'MW')

  // Resolve price from DB to avoid mismatches.
  const { data: planRow, error: planError } = await supabase
    .from('subscription_plans')
    .select('plan_id,price_mwk,name')
    .eq('plan_id', planId)
    .maybeSingle()

  if (planError) return NextResponse.json({ error: planError.message }, { status: 500 })
  if (!planRow) return NextResponse.json({ error: 'Plan not found in DB. Apply subscriptions migration.' }, { status: 500 })

  const priceMwk = Number((planRow as unknown as { price_mwk?: unknown })?.price_mwk ?? 0)

  // Inactivate any existing active subscription for this user.
  await supabase
    .from('user_subscriptions')
    .update({ status: 'replaced', updated_at: new Date().toISOString() })
    .in('user_id', lookupUserIds)
    .eq('status', 'active')

  const now = new Date()
  const endsAt = durationMinutes != null ? new Date(now.getTime() + durationMinutes * 60_000) : months > 0 ? addMonthsUtc(now, months) : null

  const { data: subRow, error: subError } = await supabase
    .from('user_subscriptions')
    .insert({
      user_id: userId,
      plan_id: planId,
      status: 'active',
      started_at: now.toISOString(),
      ends_at: endsAt ? endsAt.toISOString() : null,
      auto_renew: autoRenew,
      country_code: country,
      source,
      meta: {
        created_by: 'admin_dashboard',
        ...(resolved.inputUserId && resolved.inputUserId !== userId
          ? { input_user_id: resolved.inputUserId, canonical_user_id: userId, resolved_via: resolved.resolvedVia }
          : null),
      },
    })
    .select('id')
    .single()

  if (subError) return NextResponse.json({ error: subError.message }, { status: 500 })

	await trySetSubscriptionClaims(userId, { plan_id: planId, status: 'active', ends_at: endsAt ? endsAt.toISOString() : null })

  const subscriptionId = Number((subRow as unknown as { id?: unknown })?.id)
  let txId: number | null = null
  if (createTx && priceMwk > 0) {
    const { data: txRow, error: txError } = await supabase
      .from('transactions')
      .insert({
        type: 'subscription',
        actor_type: 'user',
        actor_id: userId,
        amount_mwk: priceMwk,
        coins: 0,
        source,
        meta: { created_by: 'admin_dashboard', plan_id: planId },
        country_code: country,
      })
      .select('id')
      .single()

    if (txError) {
      // Keep subscription row even if tx fails, but report.
      await tryLog(supabase, {
        admin_email: adminCtx.admin.email,
        action: 'subscriptions.set_user_subscription_tx_failed',
        target_type: 'user',
        target_id: userId,
        meta: { plan_id: planId, error: txError.message },
      })
      return NextResponse.json({ ok: true, subscription_id: subscriptionId, warning: txError.message })
    }

    txId = Number((txRow as unknown as { id?: unknown })?.id ?? 0)
  }

  await tryLog(supabase, {
    admin_email: adminCtx.admin.email,
    action: 'subscriptions.set_user_subscription',
    target_type: 'user',
    target_id: userId,
    meta: {
      plan_id: planId,
      months,
      duration_minutes: durationMinutes,
      auto_renew: autoRenew,
      transaction_id: txId,
      ...(resolved.inputUserId && resolved.inputUserId !== userId
        ? { input_user_id: resolved.inputUserId, canonical_user_id: userId, resolved_via: resolved.resolvedVia }
        : null),
    },
  })

  return NextResponse.json({ ok: true, subscription_id: subscriptionId, transaction_id: txId })
}
