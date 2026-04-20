import { NextResponse } from 'next/server'
import { createHmac, timingSafeEqual } from 'crypto'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { asSubscriptionPlanId } from '@/lib/subscription/plans'
import { trySetSubscriptionClaims } from '@/lib/subscription/firebase-claims'
import { resolveCanonicalSubscriptionUserId } from '@/lib/subscription/resolve-user-id'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function normalizeSecret(): string | null {
	const s = process.env.PAYCHANGU_WEBHOOK_SECRET
	return s && s.trim() ? s.trim() : null
}

function getSignatureHeader(req: Request): string | null {
	// Support a few common naming conventions.
	return (
		req.headers.get('signature') ||
		req.headers.get('Signature') ||
		req.headers.get('x-paychangu-signature') ||
		req.headers.get('paychangu-signature') ||
		req.headers.get('x-signature') ||
		req.headers.get('x-webhook-signature')
	)
}

function safeEqual(a: string, b: string): boolean {
	try {
		const ab = Buffer.from(a)
		const bb = Buffer.from(b)
		if (ab.length !== bb.length) return false
		return timingSafeEqual(ab, bb)
	} catch {
		return false
	}
}

function verifySignature(rawBody: string, signature: string, secret: string): boolean {
	// Default: HMAC-SHA256 hex.
	const hex = createHmac('sha256', secret).update(rawBody).digest('hex')
	if (safeEqual(hex.toLowerCase(), signature.toLowerCase())) return true
	// Some systems use base64.
	const b64 = createHmac('sha256', secret).update(rawBody).digest('base64')
	if (safeEqual(b64, signature)) return true
	return false
}

function normalizePayChanguSecretKey(): string | null {
	const s = process.env.PAYCHANGU_SECRET_KEY || process.env.PAYCHANGU_SECRET
	return s && s.trim() ? s.trim() : null
}

async function verifyPayChanguTransaction(txRef: string, secretKey: string) {
	const url = `https://api.paychangu.com/verify-payment/${encodeURIComponent(txRef)}`
	const res = await fetch(url, {
		headers: {
			accept: 'application/json',
			authorization: `Bearer ${secretKey}`,
		},
	})
	const data = (await res.json().catch(() => null)) as any
	return { ok: res.ok, status: res.status, data }
}

function pickString(v: unknown): string | null {
	if (typeof v === 'string' && v.trim()) return v.trim()
	if (typeof v === 'number' && Number.isFinite(v)) return String(v)
	return null
}

function pickNumber(v: unknown): number | null {
	if (typeof v === 'number' && Number.isFinite(v)) return v
	if (typeof v === 'string' && v.trim() && Number.isFinite(Number(v))) return Number(v)
	return null
}

function normalizeStatus(v: unknown): 'pending' | 'paid' | 'failed' | 'cancelled' | 'refunded' | 'unknown' {
	const s = String(v ?? '').trim().toLowerCase()
	if (['success', 'successful', 'paid', 'completed'].includes(s)) return 'paid'
	if (['failed', 'error'].includes(s)) return 'failed'
	if (['cancelled', 'canceled'].includes(s)) return 'cancelled'
	if (['refunded', 'refund'].includes(s)) return 'refunded'
	if (['pending', 'processing'].includes(s)) return 'pending'
	return 'unknown'
}

function toIntervalCount(raw: unknown): number {
	const n = typeof raw === 'number' ? raw : typeof raw === 'string' ? Number(raw) : NaN
	if (!Number.isFinite(n)) return 1
	return Math.max(1, Math.min(24, Math.trunc(n)))
}

function normalizeBillingInterval(value: unknown): 'month' | 'week' | null {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'month' || s === 'monthly') return 'month'
	if (s === 'week' || s === 'weekly') return 'week'
	return null
}

function addMonthsUtc(base: Date, months: number): Date {
	const out = new Date(base)
	out.setUTCMonth(out.getUTCMonth() + months)
	return out
}

function addDaysUtc(base: Date, days: number): Date {
	const out = new Date(base)
	out.setUTCDate(out.getUTCDate() + days)
	return out
}

function addIntervalUtc(base: Date, interval: 'month' | 'week', count: number): Date {
	const n = toIntervalCount(count)
	return interval === 'week' ? addDaysUtc(base, n * 7) : addMonthsUtc(base, n)
}

export async function POST(req: Request) {
	const secret = normalizeSecret()
	if (!secret) {
		// Refuse to run without a secret; otherwise anyone could upgrade subscriptions.
		return json({ error: 'Server not configured (missing PAYCHANGU_WEBHOOK_SECRET).' }, { status: 503 })
	}

	const sig = getSignatureHeader(req)
	if (!sig) return json({ error: 'Missing webhook signature header.' }, { status: 401 })

	const raw = await req.text()
	if (!verifySignature(raw, sig, secret)) {
		return json({ error: 'Invalid signature.' }, { status: 401 })
	}

	const payload = (raw ? JSON.parse(raw) : null) as any
	if (!payload || typeof payload !== 'object') return json({ error: 'Invalid JSON payload.' }, { status: 400 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 503 })

	// Attempt to extract identifiers (PayChangu fields vary by integration).
	const provider = 'paychangu'
	const transactionId =
		pickString(payload?.transaction_id) ||
		pickString(payload?.data?.transaction_id) ||
		pickString(payload?.id)
	const txRef =
		pickString(payload?.tx_ref) ||
		pickString(payload?.data?.tx_ref) ||
		pickString(payload?.reference) ||
		pickString(payload?.reference) ||
		pickString(payload?.data?.reference) ||
		null

	// Prefer tx_ref for provider_reference so it matches the pending payment record
	// created by /api/paychangu/start.
	const providerRef = txRef || transactionId

	if (!providerRef) {
		// Store anyway with a generated reference to aid debugging.
		const gen = `unknown_${Date.now()}`
		await supabase.from('subscription_payments').insert({
			provider,
			provider_reference: gen,
			status: 'unknown',
			raw: payload,
			meta: { warning: 'missing_provider_reference' },
		})
		return json({ ok: true, warning: 'missing_provider_reference' })
	}

	const eventType = pickString(payload?.event) || pickString(payload?.event_type) || pickString(payload?.type)
	let status = normalizeStatus(payload?.status ?? payload?.data?.status)
	const currency = pickString(payload?.currency ?? payload?.data?.currency)
	const amountMwk = pickNumber(payload?.amount ?? payload?.data?.amount) ?? 0

	// Read metadata: we expect your payment initiation to set these.
	const meta = (payload?.meta ?? payload?.metadata ?? payload?.data?.meta ?? payload?.data?.metadata ?? {}) as any
	let userId = pickString(meta?.user_id ?? meta?.uid ?? payload?.customer?.id ?? payload?.data?.customer?.id)
	let planId = asSubscriptionPlanId(meta?.plan_id ?? meta?.plan)
	const intervalCount = toIntervalCount(meta?.interval_count ?? meta?.intervals ?? meta?.periods ?? meta?.months ?? 1)
	const countryCode = pickString(meta?.country_code ?? meta?.country ?? payload?.country_code ?? payload?.data?.country_code)

	// If PayChangu doesn't echo meta back, reconcile it using the pending row created
	// by /api/paychangu/start (keyed by tx_ref).
	if ((!userId || !planId) && txRef) {
		try {
			const { data: pending } = await supabase
				.from('subscription_payments')
				.select('user_id,plan_id,meta')
				.eq('provider', provider)
				.eq('provider_reference', txRef)
				.maybeSingle()

			const recoveredMeta = (pending as any)?.meta || null
			if (!userId) userId = pickString((pending as any)?.user_id ?? recoveredMeta?.user_id ?? recoveredMeta?.uid)
			if (!planId) planId = asSubscriptionPlanId((pending as any)?.plan_id ?? recoveredMeta?.plan_id ?? recoveredMeta?.plan)
		} catch {
			// best-effort
		}
	}

	// Always re-query (best-effort) to confirm final transaction status.
	// Docs: https://developer.paychangu.com/docs/webhooks (Always Re-query)
	let verifyMeta: Record<string, any> | null = null
	const paychanguSecretKey = normalizePayChanguSecretKey()
	if (paychanguSecretKey && txRef) {
		try {
			const verified = await verifyPayChanguTransaction(txRef, paychanguSecretKey)
			verifyMeta = { tx_ref: txRef, http_status: verified.status, ok: verified.ok }
			const verifiedStatus = verified?.data?.data?.status
			if (verified.ok && typeof verifiedStatus === 'string') {
				status = normalizeStatus(verifiedStatus)
				verifyMeta.verified_status = verifiedStatus
			}
		} catch (e: any) {
			verifyMeta = { tx_ref: txRef, error: String(e?.message ?? e) }
		}
	}

	// Canonicalize `user_id` to Firebase UID when possible.
	const inputUserId = userId
	let userIdResolution: Record<string, unknown> | null = null
	if (userId) {
		try {
			const resolved = await resolveCanonicalSubscriptionUserId({ supabase, userId })
			if (resolved.canonicalUserId) {
				userId = resolved.canonicalUserId
				if (resolved.inputUserId && resolved.inputUserId !== resolved.canonicalUserId) {
					userIdResolution = {
						input_user_id: resolved.inputUserId,
						canonical_user_id: resolved.canonicalUserId,
						resolved_via: resolved.resolvedVia,
					}
				} else if (resolved.resolvedVia) {
					userIdResolution = { canonical_user_id: resolved.canonicalUserId, resolved_via: resolved.resolvedVia }
				}
			}
		} catch {
			// best-effort
		}
	}

	// Upsert payment record (idempotent).
	const nowIso = new Date().toISOString()
	const upsertPayload = {
		provider,
		provider_reference: providerRef,
		event_type: eventType,
		status,
		user_id: userId,
		plan_id: planId,
		amount_mwk: amountMwk,
		currency,
		country_code: countryCode,
		raw: payload,
		meta: {
			...meta,
			// Normalize for backward/forward compatibility.
			months: intervalCount,
			interval_count: intervalCount,
			received_at: nowIso,
			...(userIdResolution ? { user_id_resolution: userIdResolution } : {}),
			...(verifyMeta ? { verify: verifyMeta } : {}),
		},
		updated_at: nowIso,
	}

	const { data: paymentRow, error: upsertErr } = await supabase
		.from('subscription_payments')
		.upsert(upsertPayload, { onConflict: 'provider,provider_reference' })
		.select('id,provider,provider_reference,status,user_id,plan_id')
		.single()

	if (upsertErr) return json({ error: upsertErr.message }, { status: 500 })

	// If we can't map this event to a subscription action, stop here.
	if (!userId || !planId) {
		return json({ ok: true, payment_id: paymentRow.id, warning: 'missing_user_id_or_plan_id', tx_ref: txRef, transaction_id: transactionId })
	}

	const lookupUserIds = Array.from(new Set([userId, inputUserId].filter(Boolean)))

	// Apply subscription state changes.
	if (status === 'paid') {
		// Load plan price (for ledger entry).
		const { data: planRow } = await supabase
			.from('subscription_plans')
			.select('plan_id,price_mwk,billing_interval')
			.eq('plan_id', planId)
			.maybeSingle()

		const planPricePerInterval = Number((planRow as any)?.price_mwk ?? 0)
		const planBillingInterval =
			normalizeBillingInterval((planRow as any)?.billing_interval) ||
			normalizeBillingInterval(meta?.billing_interval) ||
			(planId.endsWith('_weekly') ? 'week' : 'month')
		const expectedTotal = planPricePerInterval > 0 ? planPricePerInterval * intervalCount : 0
		const ledgerAmount = amountMwk > 0 ? amountMwk : expectedTotal

		// Find current active subscription (if any). Prefer canonical userId.
		let active: any | null = null
		let activeKey: string | null = null
		{
			const { data } = await supabase
				.from('user_subscriptions')
				.select('id,user_id,plan_id,ends_at,status')
				.eq('user_id', userId)
				.eq('status', 'active')
				.order('created_at', { ascending: false })
				.limit(1)
				.maybeSingle()
			if (data) {
				active = data as any
				activeKey = userId
			}
		}
		if (!active && inputUserId && inputUserId !== userId) {
			const { data } = await supabase
				.from('user_subscriptions')
				.select('id,user_id,plan_id,ends_at,status')
				.eq('user_id', inputUserId)
				.eq('status', 'active')
				.order('created_at', { ascending: false })
				.limit(1)
				.maybeSingle()
			if (data) {
				active = data as any
				activeKey = inputUserId
			}
		}

		// Best-effort heal: if we found an active row under a legacy key, re-key to canonical.
		if (active && activeKey && activeKey !== userId) {
			try {
				await supabase.from('user_subscriptions').update({ user_id: userId, updated_at: nowIso }).eq('id', (active as any).id)
				;(active as any).user_id = userId
			} catch {
				// ignore
			}
		}

		const now = new Date()
		let subscriptionId: number | null = null
		let endsAtIso: string | null = null

		if (active && String((active as any).plan_id) === planId) {
			// Extend existing subscription.
			const base = (active as any).ends_at ? new Date((active as any).ends_at) : now
			const effectiveBase = base > now ? base : now
			const nextEnd = addIntervalUtc(effectiveBase, planBillingInterval, intervalCount)
			endsAtIso = nextEnd.toISOString()

			const { error: updErr } = await supabase
				.from('user_subscriptions')
				.update({ ends_at: endsAtIso, updated_at: nowIso })
				.eq('id', (active as any).id)

			if (!updErr) subscriptionId = Number((active as any).id)
		} else {
			// Replace current subscription (if any).
			if (active?.id) {
				await supabase
					.from('user_subscriptions')
					.update({ status: 'replaced', updated_at: nowIso })
					.eq('id', (active as any).id)
			}

			const endsAt = addIntervalUtc(now, planBillingInterval, intervalCount)
			endsAtIso = endsAt.toISOString()
			const { data: inserted, error: insErr } = await supabase
				.from('user_subscriptions')
				.insert({
					user_id: userId,
					plan_id: planId,
					status: 'active',
					started_at: nowIso,
					ends_at: endsAtIso,
					auto_renew: true,
					country_code: countryCode ?? 'MW',
					source: 'paychangu',
					meta: {
						provider,
						provider_reference: providerRef,
						payment_id: paymentRow.id,
						months: intervalCount,
						interval_count: intervalCount,
						billing_interval: planBillingInterval,
						...(inputUserId && inputUserId !== userId ? { input_user_id: inputUserId } : {}),
					},
				})
				.select('id')
				.single()

			if (!insErr) subscriptionId = Number((inserted as any)?.id ?? 0)
		}

		// Insert ledger transaction (subscription revenue).
		if (ledgerAmount > 0) {
			await supabase.from('transactions').insert({
				type: 'subscription',
				actor_type: 'user',
				actor_id: userId,
				amount_mwk: ledgerAmount,
				coins: 0,
				source: 'paychangu',
				country_code: countryCode ?? 'MW',
				meta: {
					plan_id: planId,
					provider_reference: providerRef,
					payment_id: paymentRow.id,
					months: intervalCount,
					interval_count: intervalCount,
					billing_interval: planBillingInterval,
				},
			})
		}

		// Link payment record to subscription id (best-effort).
		if (subscriptionId) {
			await supabase
				.from('subscription_payments')
				.update({ user_subscription_id: subscriptionId, updated_at: nowIso })
				.eq('provider', provider)
				.eq('provider_reference', providerRef)
		}

		// Best-effort: sync plan into Firebase custom claims (consumer app uses Firebase auth).
		await trySetSubscriptionClaims(userId, { plan_id: planId, status: 'active', ends_at: endsAtIso })
	}

	if (status === 'cancelled') {
		// Mark active subscription cancelled (best-effort)
		await supabase
			.from('user_subscriptions')
			.update({ status: 'canceled', auto_renew: false, updated_at: nowIso })
			.in('user_id', lookupUserIds)
			.eq('status', 'active')
		await trySetSubscriptionClaims(userId, { plan_id: planId, status: 'canceled' })
	}

	if (status === 'refunded') {
		// Record a refund adjustment if amount is known.
		if (amountMwk > 0) {
			await supabase.from('transactions').insert({
				type: 'adjustment',
				actor_type: 'user',
				actor_id: userId,
				amount_mwk: -Math.abs(amountMwk),
				coins: 0,
				source: 'paychangu',
				country_code: countryCode ?? 'MW',
				meta: { reason: 'gateway_refund', plan_id: planId, provider_reference: providerRef, payment_id: paymentRow.id },
			})
		}
	}

	return json({ ok: true, payment_id: paymentRow.id, status })
}
