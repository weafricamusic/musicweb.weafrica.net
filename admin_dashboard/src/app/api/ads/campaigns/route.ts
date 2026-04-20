import { NextRequest, NextResponse } from 'next/server'

import { isAdCampaignSurface, isAdCampaignType } from '@/lib/admin/promotions'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type AdCampaignApiRow = {
	id: string
	country_code: string
	campaign_type: string
	format: string
	surface: string
	title: string
	description: string | null
	sponsor_name: string | null
	asset_url: string | null
	video_url: string | null
	cta_label: string | null
	cta_url: string | null
	audience: string | null
	target_type: string | null
	target_ref_id: string | null
	starts_at: string | null
	ends_at: string | null
	frequency_cap_daily: number
	priority: number
	metadata: unknown
	status: string
	approval_status: string
	is_enabled: boolean
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET(req: NextRequest) {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const countryCode = String(req.nextUrl.searchParams.get('country_code') ?? 'MW').trim().toUpperCase()
	if (!/^[A-Z]{2}$/.test(countryCode)) return json({ error: 'Invalid country_code' }, { status: 400 })

	const surface = req.nextUrl.searchParams.get('surface')?.trim() ?? null
	if (surface && !isAdCampaignSurface(surface)) return json({ error: 'Invalid surface' }, { status: 400 })

	const campaignType = req.nextUrl.searchParams.get('campaign_type')?.trim() ?? null
	if (campaignType && !isAdCampaignType(campaignType)) return json({ error: 'Invalid campaign_type' }, { status: 400 })

	const limitRaw = Number(req.nextUrl.searchParams.get('limit') ?? '20')
	const limit = Number.isFinite(limitRaw) ? Math.min(100, Math.max(1, Math.trunc(limitRaw))) : 20

	let query = supabase
		.from('ad_campaigns')
		.select('id,country_code,campaign_type,format,surface,title,description,sponsor_name,asset_url,video_url,cta_label,cta_url,audience,target_type,target_ref_id,starts_at,ends_at,frequency_cap_daily,priority,metadata,status,approval_status,is_enabled')
		.eq('country_code', countryCode)
		.eq('approval_status', 'approved')
		.eq('is_enabled', true)
		.in('status', ['scheduled', 'active'])
		.order('priority', { ascending: false })
		.order('starts_at', { ascending: false })
		.limit(limit)

	if (surface) query = query.eq('surface', surface)
	if (campaignType) query = query.eq('campaign_type', campaignType)

	const { data, error } = await query
	if (error) {
		const msg = String(error.message ?? 'Failed to load campaigns')
		const status = /ad_campaigns|schema cache|could not find/i.test(msg) ? 503 : 500
		return json({ error: msg }, { status })
	}

	const now = Date.now()
	const rows = ((data ?? []) as AdCampaignApiRow[]).filter((row) => {
		if (!row.is_enabled || row.approval_status !== 'approved') return false
		const startsAt = row.starts_at ? new Date(row.starts_at).getTime() : null
		const endsAt = row.ends_at ? new Date(row.ends_at).getTime() : null
		if (startsAt != null && Number.isFinite(startsAt) && startsAt > now) return false
		if (endsAt != null && Number.isFinite(endsAt) && endsAt <= now) return false
		return true
	})

	return json(
		{
			ok: true,
			country_code: countryCode,
			count: rows.length,
			data: rows,
		},
		{
			headers: {
				'cache-control': 'no-store',
			},
		},
	)
}