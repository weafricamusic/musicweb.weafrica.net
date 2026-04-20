import { NextResponse } from 'next/server'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import { loadPlatformIntelligence } from '@/lib/admin/platform-intelligence'
import { toCsv } from '@/lib/admin/csv'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function clampInt(raw: string | null, min: number, max: number, fallback: number): number {
	const n = Number(raw ?? '')
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.floor(n)))
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

	const url = new URL(req.url)
	const days = clampInt(url.searchParams.get('days'), 1, 90, 7)
	const qCountry = (url.searchParams.get('country') ?? '').trim().toUpperCase()
	const cookieCountry = await getAdminCountryCode().catch(() => null)
	const country = qCountry || (cookieCountry ? String(cookieCountry).toUpperCase() : '')

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for admin analytics export (no anon fallback).' },
			{ status: 500 },
		)
	}
	const intel = await loadPlatformIntelligence({ supabase, days, countryCode: country || null })

	const rows: Array<Record<string, string | number | null>> = []
	rows.push({ section: 'meta', metric: 'generated_at', day: '', value: new Date().toISOString(), unit: '' })
	rows.push({ section: 'meta', metric: 'country', day: '', value: country || null, unit: '' })
	rows.push({ section: 'meta', metric: 'days', day: '', value: intel.range.days, unit: 'days' })
	
	const summary: Array<[string, number | null, string]> = [
		['revenue_mwk', intel.revenueMwk7d ?? null, 'MWK'],
		['coins_sold', intel.coinsSold7d ?? null, 'coins'],
		['pending_withdrawals_mwk', intel.pendingWithdrawalsMwk ?? null, 'MWK'],
		['pending_withdrawals_count', intel.pendingWithdrawalsCount ?? null, 'count'],
		['new_users', intel.newUsers7d ?? null, 'count'],
		['new_songs', intel.newSongs7d ?? null, 'count'],
		['new_videos', intel.newVideos7d ?? null, 'count'],
		['open_reports', intel.openReports ?? null, 'count'],
		['frozen_earnings_accounts', intel.frozenEarningsAccounts ?? null, 'count'],
		['active_streams', intel.activeStreams ?? null, 'count'],
		['avg_viewers_recent', intel.avgViewersRecent == null ? null : Math.round(intel.avgViewersRecent), 'viewers'],
		['max_viewers_recent', intel.maxViewersRecent == null ? null : Math.round(intel.maxViewersRecent), 'viewers'],
		['dau_1d', intel.dau1d ?? null, 'users'],
		['mau_30d', intel.mau30d ?? null, 'users'],
		['stickiness', intel.stickiness ?? null, 'ratio'],
		['stream_join_success_rate', intel.streamJoinSuccessRate ?? null, 'ratio'],
	]

	for (const [metric, value, unit] of summary) {
		rows.push({ section: 'summary', metric, day: '', value: value as any, unit })
	}

	function pushSeries(metric: string, unit: string, series: Array<{ day: string; value: number }> | null | undefined) {
		for (const p of series ?? []) {
			rows.push({ section: 'series', metric, day: p.day, value: p.value, unit })
		}
	}

	pushSeries('revenue_mwk_per_day', 'MWK', intel.revenueSeriesMwk)
	pushSeries('coins_sold_per_day', 'coins', intel.coinsSoldSeries)
	pushSeries('new_users_per_day', 'count', intel.newUsersSeries)
	pushSeries('new_songs_per_day', 'count', intel.newSongsSeries)
	pushSeries('new_videos_per_day', 'count', intel.newVideosSeries)
	pushSeries('streams_started_per_day', 'count', intel.streamsStartedSeries)

	const csv = toCsv(['section', 'metric', 'day', 'value', 'unit'], rows)
	const filename = `analytics_${country || 'ALL'}_${intel.range.days}d_${new Date().toISOString().slice(0, 10)}.csv`

	await logAdminAction({
		ctx,
		action: 'analytics_export_csv',
		target_type: 'analytics',
		target_id: country || 'ALL',
		meta: { days: intel.range.days, rows: rows.length },
		req,
	}).catch(() => {})

	return new NextResponse(csv, {
		status: 200,
		headers: {
			'content-type': 'text/csv; charset=utf-8',
			'content-disposition': `attachment; filename="${filename}"`,
			'cache-control': 'no-store',
		},
	})
}
