import { NextResponse } from 'next/server'
import { asSubscriptionPlanId, getEquivalentSubscriptionPlanIds, normalizeSubscriptionPlanId } from '@/lib/subscription/plans'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { randomUUID } from 'crypto'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function normalizeEnvOptional(key: string): string | null {
	const v = process.env[key]
	if (!v) return null
	const t = v.trim().replace(/^['"]|['"]$/g, '')
	return t ? t : null
}

function shouldExposeDebug(): boolean {
	if (process.env.NODE_ENV !== 'production') return true
	const flag = normalizeEnvOptional('WEAFRICA_DEBUG') || normalizeEnvOptional('PAYCHANGU_DEBUG')
	if (!flag) return false
	return ['1', 'true', 'yes', 'on'].includes(flag.toLowerCase())
}

function toEnvSuffix(planId: string): string {
	// premium_weekly -> PREMIUM_WEEKLY
	return planId
		.trim()
		.toUpperCase()
		.replace(/[^A-Z0-9]+/g, '_')
		.replace(/^_+|_+$/g, '')
}

function getPlanIdCandidates(planId: string | null): string[] {
	if (!planId) return []
	return [...new Set([planId, ...getEquivalentSubscriptionPlanIds(planId)])]
}

function resolveCheckoutUrl(planId: string | null): { url: string | null; sourceKey: string | null } {
	for (const candidate of getPlanIdCandidates(planId)) {
		const suffix = toEnvSuffix(candidate)
		const keys = [`PAYCHANGU_CHECKOUT_URL_${suffix}`, `PAYCHANGU_CHECKOUT_URL_${candidate.toUpperCase()}`]
		for (const key of keys) {
			const v = normalizeEnvOptional(key)
			if (v) return { url: v, sourceKey: key }
		}
	}

	const fallback = normalizeEnvOptional('PAYCHANGU_CHECKOUT_URL')
	return { url: fallback, sourceKey: fallback ? 'PAYCHANGU_CHECKOUT_URL' : null }
}

function resolveConfiguredPlanAmount(planId: string | null): number {
	for (const candidate of getPlanIdCandidates(planId)) {
		const suffix = toEnvSuffix(candidate)
		const raw = normalizeEnvOptional(`PAYCHANGU_AMOUNT_${suffix}`) || normalizeEnvOptional(`PAYCHANGU_AMOUNT_${candidate.toUpperCase()}`)
		if (raw && Number.isFinite(Number(raw))) return Number(raw)
	}

	const fallback = normalizeEnvOptional('PAYCHANGU_AMOUNT')
	return fallback && Number.isFinite(Number(fallback)) ? Number(fallback) : 0
}

function resolvePayChanguSecretKey(): string | null {
	return normalizeEnvOptional('PAYCHANGU_SECRET_KEY') || normalizeEnvOptional('PAYCHANGU_SECRET')
}

function resolveCurrency(countryCode: string | null): string {
	// PayChangu supports MWK and USD (per docs). Default to MWK unless overridden.
	const override = normalizeEnvOptional('PAYCHANGU_CURRENCY')
	if (override) return override
	if (countryCode && countryCode !== 'MW') {
		// Keep MWK as default; allow override per deployment via PAYCHANGU_CURRENCY.
		return 'MWK'
	}
	return 'MWK'
}

function resolveCallbackUrl(requestUrl: URL): string {
	return (
		normalizeEnvOptional('PAYCHANGU_CALLBACK_URL') ||
		normalizeEnvOptional('PAYCHANGU_IPN_URL') ||
		`${requestUrl.origin}/api/paychangu/callback`
	)
}

function resolveReturnUrl(requestUrl: URL): string {
	return normalizeEnvOptional('PAYCHANGU_RETURN_URL') || `${requestUrl.origin}/paychangu/success`
}

function applyTemplate(url: string, vars: Record<string, string | number | null | undefined>): string {
	let out = url
	for (const [k, v] of Object.entries(vars)) {
		out = out.replaceAll(`{{${k}}}`, v == null ? '' : String(v))
	}
	return out
}

function addQueryParams(url: string, params: Record<string, string | number | null | undefined>): string {
	try {
		const u = new URL(url)
		for (const [k, v] of Object.entries(params)) {
			if (v == null || String(v).trim() === '') continue
			if (u.searchParams.has(k)) continue
			u.searchParams.set(k, String(v))
		}
		return u.toString()
	} catch {
		// If the URL isn't a valid absolute URL, don't mutate it.
		return url
	}
}

function toIntervalCount(raw: unknown): number {
	const n = typeof raw === 'number' ? raw : typeof raw === 'string' ? Number(raw) : NaN
	if (!Number.isFinite(n)) return 1
	return Math.max(1, Math.min(24, Math.trunc(n)))
}

function readIntervalCount(body: any): number {
	// Backward compatible: existing clients send `months`.
	return toIntervalCount(body?.interval_count ?? body?.intervals ?? body?.periods ?? body?.months ?? 1)
}

function normalizeBillingInterval(value: unknown): 'month' | 'week' | null {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'month' || s === 'monthly') return 'month'
	if (s === 'week' || s === 'weekly') return 'week'
	return null
}

export async function POST(req: Request) {
	const exposeDebug = shouldExposeDebug()
	const body = (await req.json().catch(() => null)) as any
	const requestedPlanId = asSubscriptionPlanId(body?.plan_id)
	let planId = requestedPlanId
	const userId = typeof body?.user_id === 'string' && body.user_id.trim() ? body.user_id.trim() : null
	const intervalCount = readIntervalCount(body)
	const countryCode = typeof body?.country_code === 'string' && body.country_code.trim() ? body.country_code.trim().toUpperCase() : null

	const requestUrl = new URL(req.url)
	const paychanguSecretKey = resolvePayChanguSecretKey()

	// Preferred (real product): create a PayChangu Standard Checkout transaction.
	// Docs: POST https://api.paychangu.com/payment (Authorization: Bearer {secret_key})
	if (paychanguSecretKey) {
		if (!planId || !userId) {
			return json({ error: 'Missing required fields: user_id and plan_id.' }, { status: 400 })
		}

		const supabase = tryCreateSupabaseAdminClient()
		let amount = 0
		let planBillingInterval: 'month' | 'week' | null = null
		let pricePerInterval = 0
		try {
			if (supabase) {
				const planLookupIds = getPlanIdCandidates(requestedPlanId)
				const { data } = await supabase
					.from('subscription_plans')
					.select('plan_id,price_mwk,billing_interval')
					.in('plan_id', planLookupIds.length ? planLookupIds : [planId])
					.limit(Math.max(1, planLookupIds.length || 1))
				const planRows = ((data ?? []) as Array<Record<string, unknown>>)
				const normalizedRequestedPlanId = requestedPlanId ? normalizeSubscriptionPlanId(requestedPlanId) : null
				const chosenPlan =
					planRows.find((row) => String(row.plan_id ?? '').trim() === requestedPlanId) ??
					planRows.find((row) => String(row.plan_id ?? '').trim() === normalizedRequestedPlanId) ??
					planRows[0] ??
					null
				const resolvedPlanId = asSubscriptionPlanId((chosenPlan as any)?.plan_id)
				if (resolvedPlanId) planId = resolvedPlanId
				const dbPrice = Number((chosenPlan as any)?.price_mwk ?? 0)
				if (Number.isFinite(dbPrice) && dbPrice > 0) {
					pricePerInterval = dbPrice
					planBillingInterval = normalizeBillingInterval((chosenPlan as any)?.billing_interval)
					amount = dbPrice * intervalCount
				}
			}
		} catch {
			// ignore: fall back below
		}
		if (!amount || amount <= 0) {
			// Fallback: use configured amount per plan if provided, else refuse.
			pricePerInterval = resolveConfiguredPlanAmount(planId)
			amount = pricePerInterval > 0 ? pricePerInterval * intervalCount : 0
		}
		if (!amount || amount <= 0) {
			return json(
				{
					error:
						'Missing plan pricing for PayChangu initiation. Seed subscription_plans in DB or set PAYCHANGU_AMOUNT_<PLANID> (or PAYCHANGU_AMOUNT).',
				},
				{ status: 503 },
			)
		}

		const currency = resolveCurrency(countryCode)
		const callbackUrl = resolveCallbackUrl(requestUrl)
		const returnUrl = resolveReturnUrl(requestUrl)
		const txRef = `sub_${planId}_${randomUUID()}`

		const payload = {
			amount,
			currency,
			callback_url: callbackUrl,
			return_url: returnUrl,
			tx_ref: txRef,
			customization: {
				title: `WeAfrica ${planId}`,
				description: `Subscription: ${planId}`,
			},
			meta: {
				user_id: userId,
				plan_id: planId,
				...(requestedPlanId && requestedPlanId !== planId ? { requested_plan_id: requestedPlanId } : null),
				// Backward-compatible: keep `months`, but treat it as "interval count".
				months: intervalCount,
				interval_count: intervalCount,
				billing_interval: planBillingInterval,
				country_code: countryCode,
			},
		}

		const res = await fetch('https://api.paychangu.com/payment', {
			method: 'POST',
			headers: {
				accept: 'application/json',
				'content-type': 'application/json',
				authorization: `Bearer ${paychanguSecretKey}`,
			},
			body: JSON.stringify(payload),
		})

		const data = (await res.json().catch(() => null)) as any
		if (!res.ok) {
			return json(
				{
					error: 'Failed to initiate PayChangu transaction.',
					status: res.status,
					...(exposeDebug ? { response: data } : null),
				},
				{ status: 502 },
			)
		}

		const checkoutUrl = data?.data?.checkout_url
		if (typeof checkoutUrl !== 'string' || !checkoutUrl.trim()) {
			return json(
				{
					error: 'PayChangu response missing checkout_url.',
					...(exposeDebug ? { response: data } : null),
				},
				{ status: 502 },
			)
		}

		// Best-effort: record pending payment locally for traceability.
		if (supabase) {
			await supabase.from('subscription_payments').upsert(
				{
					provider: 'paychangu',
					provider_reference: txRef,
					status: 'pending',
					user_id: userId,
					plan_id: planId,
					amount_mwk: amount,
					currency,
					country_code: countryCode,
					meta: {
						...(requestedPlanId && requestedPlanId !== planId ? { requested_plan_id: requestedPlanId } : null),
						months: intervalCount,
						interval_count: intervalCount,
						billing_interval: planBillingInterval,
						price_per_interval: pricePerInterval || null,
						created_via: 'api/paychangu/start',
					},
					raw: { request: payload, response: data },
				},
				{ onConflict: 'provider,provider_reference' },
			)
		}

		return json({
			checkout_url: checkoutUrl,
			tx_ref: txRef,
			...(exposeDebug ? { mode: 'api' } : null),
		})
	}

	const { url: rawUrl, sourceKey } = resolveCheckoutUrl(planId)
	if (!rawUrl) {
		return json(
			{
				error:
					'Missing PayChangu configuration. For real checkout sessions, set PAYCHANGU_SECRET_KEY. For fallback templated links, set PAYCHANGU_CHECKOUT_URL (or PAYCHANGU_CHECKOUT_URL_<PLANID>).',
			},
			{ status: 503 }
		)
	}

	// Support templated URLs, e.g.
	// PAYCHANGU_CHECKOUT_URL_PREMIUM=https://.../checkout?user_id={{user_id}}&plan_id={{plan_id}}&months={{months}}
	let checkoutUrl = applyTemplate(rawUrl, {
		user_id: userId,
		plan_id: planId,
		months: intervalCount,
		interval_count: intervalCount,
		country_code: countryCode,
	})

	// Best-effort: also include metadata as query params (only if URL is absolute)
	checkoutUrl = addQueryParams(checkoutUrl, {
		user_id: userId,
		plan_id: planId,
		months: intervalCount,
		interval_count: intervalCount,
		country_code: countryCode,
		source: 'weafrica',
	})

	return json({
		checkout_url: checkoutUrl,
		...(exposeDebug ? { source: sourceKey, mode: 'template' } : null),
	})
}
