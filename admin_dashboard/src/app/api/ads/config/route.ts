import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { asSubscriptionPlanId, getSubscriptionEntitlements } from '@/lib/subscription/plans'

export const runtime = 'nodejs'

type CountryAdsRow = {
	ads_enabled: boolean | null
	is_active: boolean | null
}

type PlanAdsRow = {
	ads_enabled: boolean | null
	is_active: boolean | null
	audience?: string | null
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

async function fetchCountryAdsRow(args: {
	supabase: ReturnType<typeof tryCreateSupabaseAdminClient>
	countryCode: string
}): Promise<CountryAdsRow | null> {
	const { supabase, countryCode } = args
	if (!supabase) return null

	// Prefer new schema: `country_code`.
	let data: CountryAdsRow | null = null
	let error: any = null

	;({ data, error } = await supabase
		.from('countries')
		.select('ads_enabled,is_active')
		.eq('country_code', countryCode)
		.limit(1)
		.maybeSingle<CountryAdsRow>())

	const msg = String(error?.message ?? '')
	const code = String(error?.code ?? '')
	const missingCountryCode = code === '42703' || msg.toLowerCase().includes('country_code')
	if (!error || !missingCountryCode) return data

	// Legacy schema: `code`.
	;({ data, error } = await supabase
		.from('countries')
		.select('ads_enabled,is_active')
		.eq('code', countryCode)
		.limit(1)
		.maybeSingle<CountryAdsRow>())

	if (error) throw error
	return data
}

/**
 * Public endpoint intended for the consumer app.
 *
 * Computes the effective "should show ads" flag from:
 * - countries.ads_enabled (ops toggle per market)
 * - subscription_plans.ads_enabled (entitlement per plan)
 *
 * Query params:
 * - country_code: 2-letter code (optional, default: MW)
 * - plan_id: free | premium | platinum | ... (optional)
 */
export async function GET(req: NextRequest) {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const countryRaw = req.nextUrl.searchParams.get('country_code')
	const countryCode = (countryRaw ?? 'MW').trim().toUpperCase()
	if (!/^[A-Z]{2}$/.test(countryCode)) return json({ error: 'Invalid country_code' }, { status: 400 })

	const planRaw = req.nextUrl.searchParams.get('plan_id')
	const planId = planRaw ? asSubscriptionPlanId(planRaw) : null
	if (planRaw && !planId) return json({ error: 'Invalid plan_id' }, { status: 400 })

	let country: CountryAdsRow | null = null
	try {
		country = await fetchCountryAdsRow({ supabase, countryCode })
	} catch (e: any) {
		return json({ error: String(e?.message ?? 'Country lookup failed') }, { status: 500 })
	}

	const countryAdsEnabled = Boolean(country?.is_active ?? true) && Boolean(country?.ads_enabled ?? false)

	let planAdsEnabled: boolean | null = null
	if (planId) {
		// Prefer filtering by audience if the column exists.
		let planData: PlanAdsRow | null = null
		let planError: any = null

		;({ data: planData, error: planError } = await supabase
			.from('subscription_plans')
			.select('audience,ads_enabled,is_active')
			.eq('plan_id', planId)
			.eq('audience', 'consumer')
			.limit(1)
			.maybeSingle<PlanAdsRow>())

		const msg = String(planError?.message ?? '')
		const code = String(planError?.code ?? '')
		const missingAudience = code === '42703' || msg.toLowerCase().includes('audience')
		if (planError && missingAudience) {
			;({ data: planData, error: planError } = await supabase
				.from('subscription_plans')
				.select('ads_enabled,is_active')
				.eq('plan_id', planId)
				.limit(1)
				.maybeSingle<PlanAdsRow>())
		}

		if (planError) return json({ error: String(planError.message ?? 'Plan lookup failed') }, { status: 500 })

		if (planData) {
			planAdsEnabled = Boolean(planData.is_active ?? true) && Boolean(planData.ads_enabled ?? true)
		} else {
			// If the DB row doesn't exist yet (e.g. during initial setup), fall back to local defaults.
			planAdsEnabled = Boolean(getSubscriptionEntitlements(planId).ads_enabled)
		}
	}

	const adsEnabled = planAdsEnabled == null ? countryAdsEnabled : countryAdsEnabled && planAdsEnabled

	return NextResponse.json(
		{
			ok: true,
			country_code: countryCode,
			plan_id: planId,
			ads_enabled: adsEnabled,
			country_ads_enabled: countryAdsEnabled,
			plan_ads_enabled: planAdsEnabled,
		},
		{
			headers: {
				'cache-control': 'no-store',
			},
		},
	)
}
