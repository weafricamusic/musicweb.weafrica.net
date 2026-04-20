import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

export type PlatformIntelligenceRange = {
	days: number
	startIso: string
}

export type PlatformIntelligence = {
	range: PlatformIntelligenceRange

	// Simple time-series (by day, newest last)
	revenueSeriesMwk: Array<{ day: string; value: number }> | null
	coinsSoldSeries: Array<{ day: string; value: number }> | null
	newUsersSeries: Array<{ day: string; value: number }> | null
	newSongsSeries: Array<{ day: string; value: number }> | null
	newVideosSeries: Array<{ day: string; value: number }> | null
	streamsStartedSeries: Array<{ day: string; value: number }> | null

	// Revenue / monetization
	revenueMwk7d: number | null
	revenueByTypeMwk: Record<string, number> | null
	coinsSold7d: number | null
	pendingWithdrawalsMwk: number | null
	pendingWithdrawalsCount: number | null

	// Users / content
	newUsers7d: number | null
	newSongs7d: number | null
	newVideos7d: number | null

	// Behavior (telemetry)
	dau1d: number | null
	mau30d: number | null
	stickiness: number | null

	// Moderation / fraud
	openReports: number | null
	frozenEarningsAccounts: number | null

	// Streaming
	activeStreams: number | null
	avgViewersRecent: number | null
	maxViewersRecent: number | null
	streamJoinAttempts: number | null
	streamJoinSuccesses: number | null
	streamJoinSuccessRate: number | null

	warnings: string[]
}

function startRange(days: number): PlatformIntelligenceRange {
	const d = Math.max(1, Math.min(365, Math.floor(days || 7)))
	const start = new Date(Date.now() - d * 24 * 60 * 60 * 1000)
	return { days: d, startIso: start.toISOString() }
}

async function safeCount(
	supabase: SupabaseClient,
	table: string,
	apply?: (q: any) => any,
): Promise<number | null> {
	try {
		let q = supabase.from(table).select('*', { head: true, count: 'exact' })
		q = apply ? apply(q) : q
		const { count, error } = await q
		if (error) return null
		return typeof count === 'number' ? count : null
	} catch {
		return null
	}
}

async function safeList(
	supabase: SupabaseClient,
	table: string,
	select: string,
	apply?: (q: any) => any,
	limit = 5000,
): Promise<any[] | null> {
	try {
		let q = supabase.from(table).select(select)
		q = apply ? apply(q) : q
		q = q.limit(limit)
		const { data, error } = await q
		if (error) return null
		return (data ?? []) as any[]
	} catch {
		return null
	}
}

async function safeRpc<T>(
	supabase: SupabaseClient,
	fn: string,
	args: Record<string, any>,
): Promise<{ data: T | null; error: string | null }> {
	try {
		const { data, error } = await (supabase as any).rpc(fn, args)
		if (error) return { data: null, error: error.message ?? 'rpc_failed' }
		return { data: (data ?? null) as T | null, error: null }
	} catch (e) {
		return { data: null, error: e instanceof Error ? e.message : 'rpc_failed' }
	}
}

function sumNumber(rows: any[] | null, col: string): number | null {
	if (!rows) return null
	let total = 0
	for (const r of rows) {
		const n = Number((r as any)?.[col] ?? 0)
		if (Number.isFinite(n)) total += n
	}
	return total
}

function sumByKey(rows: any[] | null, keyCol: string, valueCol: string): Record<string, number> | null {
	if (!rows) return null
	const out: Record<string, number> = {}
	for (const r of rows) {
		const key = String((r as any)?.[keyCol] ?? '').trim() || 'unknown'
		const n = Number((r as any)?.[valueCol] ?? 0)
		if (!Number.isFinite(n)) continue
		out[key] = (out[key] ?? 0) + n
	}
	return out
}

function avgNumber(rows: any[] | null, col: string): { avg: number | null; max: number | null } {
	if (!rows || rows.length === 0) return { avg: null, max: null }
	let total = 0
	let seen = 0
	let max = 0
	for (const r of rows) {
		const n = Number((r as any)?.[col] ?? 0)
		if (!Number.isFinite(n)) continue
		seen += 1
		total += n
		if (n > max) max = n
	}
	if (!seen) return { avg: null, max: null }
	return { avg: total / seen, max }
}

function isoDay(value: unknown): string | null {
	try {
		if (!value) return null
		const d = new Date(String(value))
		if (Number.isNaN(d.getTime())) return null
		return d.toISOString().slice(0, 10)
	} catch {
		return null
	}
}

function daySeriesSum(rows: any[] | null, dateCol: string, valueCol: string): Array<{ day: string; value: number }> | null {
	if (!rows) return null
	const byDay = new Map<string, number>()
	for (const r of rows) {
		const day = isoDay((r as any)?.[dateCol])
		if (!day) continue
		const n = Number((r as any)?.[valueCol] ?? 0)
		if (!Number.isFinite(n)) continue
		byDay.set(day, (byDay.get(day) ?? 0) + n)
	}
	return Array.from(byDay.entries())
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([day, value]) => ({ day, value }))
}

function daySeriesCount(rows: any[] | null, dateCol: string): Array<{ day: string; value: number }> | null {
	if (!rows) return null
	const byDay = new Map<string, number>()
	for (const r of rows) {
		const day = isoDay((r as any)?.[dateCol])
		if (!day) continue
		byDay.set(day, (byDay.get(day) ?? 0) + 1)
	}
	return Array.from(byDay.entries())
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([day, value]) => ({ day, value }))
}

export async function loadPlatformIntelligence(input: {
	supabase: SupabaseClient
	days?: number
	countryCode?: string | null
}): Promise<PlatformIntelligence> {
	const range = startRange(input.days ?? 7)
	const warnings: string[] = []

	const countryCode = (input.countryCode ?? '').trim().toUpperCase() || null
	const byCountry = (q: any) => (countryCode ? q.eq('country_code', countryCode) : q)

	// Transactions (revenue/coins)
	const revenueTypes = ['coin_purchase', 'subscription', 'ad']
	const txRows = await safeList(
		input.supabase,
		'transactions',
		'type,amount_mwk,coins,created_at,country_code',
		(q) => byCountry(q).gte('created_at', range.startIso).in('type', revenueTypes).order('created_at', { ascending: false }),
		5000,
	)

	if (txRows === null) warnings.push('transactions table not accessible (RLS?)')

	const revenueMwk7d = sumNumber(txRows, 'amount_mwk')
	const coinsSold7d = sumNumber(txRows, 'coins')
	const revenueByTypeMwk = sumByKey(txRows, 'type', 'amount_mwk')
	const revenueSeriesMwk = daySeriesSum(txRows, 'created_at', 'amount_mwk')
	const coinsSoldSeries = daySeriesSum(txRows, 'created_at', 'coins')

	// Withdrawals
	const pendingWithdrawalsCount = await safeCount(input.supabase, 'withdrawals', (q) =>
		byCountry(q).eq('status', 'pending'),
	)
	if (pendingWithdrawalsCount === null) warnings.push('withdrawals table not accessible (RLS?)')

	const pendingRows = await safeList(
		input.supabase,
		'withdrawals',
		'amount_mwk,status,requested_at,country_code',
		(q) => byCountry(q).eq('status', 'pending').order('requested_at', { ascending: false }),
		5000,
	)
	const pendingWithdrawalsMwk = sumNumber(pendingRows, 'amount_mwk')

	// Users / Content (best-effort; tables may not exist)
	const newUsers7d = await safeCount(input.supabase, 'users', (q) => q.gte('created_at', range.startIso))
	if (newUsers7d === null) warnings.push('users.created_at count not available')
	const usersRows = await safeList(
		input.supabase,
		'users',
		'created_at',
		(q) => q.gte('created_at', range.startIso).order('created_at', { ascending: false }),
		5000,
	)
	const newUsersSeries = daySeriesCount(usersRows, 'created_at')
	if (usersRows === null) warnings.push('users time series not available')

	const newSongs7d = await safeCount(input.supabase, 'songs', (q) => q.gte('created_at', range.startIso))
	if (newSongs7d === null) warnings.push('songs.created_at count not available')
	const songsRows = await safeList(
		input.supabase,
		'songs',
		'created_at',
		(q) => q.gte('created_at', range.startIso).order('created_at', { ascending: false }),
		5000,
	)
	const newSongsSeries = daySeriesCount(songsRows, 'created_at')
	if (songsRows === null) warnings.push('songs time series not available')

	const newVideos7d = await safeCount(input.supabase, 'videos', (q) => q.gte('created_at', range.startIso))
	if (newVideos7d === null) warnings.push('videos.created_at count not available')
	const videosRows = await safeList(
		input.supabase,
		'videos',
		'created_at',
		(q) => q.gte('created_at', range.startIso).order('created_at', { ascending: false }),
		5000,
	)
	const newVideosSeries = daySeriesCount(videosRows, 'created_at')
	if (videosRows === null) warnings.push('videos time series not available')

	// Behavior (telemetry): DAU/MAU from analytics_events
	let dau1d: number | null = null
	let mau30d: number | null = null
	let stickiness: number | null = null
	try {
		const since1d = new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString()
		const since30d = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
		const dau = await safeRpc<number>(input.supabase, 'analytics_distinct_users', {
			p_since: since1d,
			p_event_name: 'app_open',
			p_country_code: countryCode,
		})
		if (!dau.error && typeof dau.data === 'number') dau1d = dau.data
		else warnings.push('analytics_distinct_users (DAU) not available')

		const mau = await safeRpc<number>(input.supabase, 'analytics_distinct_users', {
			p_since: since30d,
			p_event_name: 'app_open',
			p_country_code: countryCode,
		})
		if (!mau.error && typeof mau.data === 'number') mau30d = mau.data
		else warnings.push('analytics_distinct_users (MAU) not available')

		if (dau1d != null && mau30d != null && mau30d > 0) stickiness = dau1d / mau30d
	} catch {
		warnings.push('Behavior telemetry not available')
	}

	// Moderation / fraud risk
	const openReports = await safeCount(input.supabase, 'reports', (q) => q.eq('status', 'open'))
	if (openReports === null) warnings.push('reports table not accessible')

	const frozenEarningsAccounts = await safeCount(input.supabase, 'earnings_freeze_state', (q) => q.eq('frozen', true))
	if (frozenEarningsAccounts === null) warnings.push('earnings_freeze_state table not accessible')

	// Streaming quality (best-effort)
	const activeStreams = await safeCount(input.supabase, 'live_streams', (q) => q.eq('status', 'live'))
	if (activeStreams === null) warnings.push('live_streams table not accessible')

	const recentStreams = await safeList(
		input.supabase,
		'live_streams',
		'viewer_count,started_at,status,region',
		(q) => q.gte('started_at', range.startIso).order('started_at', { ascending: false }),
		2500,
	)
	const viewers = avgNumber(recentStreams, 'viewer_count')
	const streamsStartedSeries = daySeriesCount(recentStreams, 'started_at')

	let streamJoinAttempts: number | null = null
	let streamJoinSuccesses: number | null = null
	let streamJoinSuccessRate: number | null = null
	try {
		const r = await safeRpc<any[] | any>(input.supabase, 'analytics_stream_join_success_rate', {
			p_days: range.days,
			p_country_code: countryCode,
		})
		const row = Array.isArray(r.data) ? r.data[0] : r.data
		if (!r.error && row) {
			streamJoinAttempts = typeof row.attempts === 'number' ? row.attempts : Number(row.attempts ?? 0)
			streamJoinSuccesses = typeof row.successes === 'number' ? row.successes : Number(row.successes ?? 0)
			streamJoinSuccessRate =
				row.success_rate == null ? null : (typeof row.success_rate === 'number' ? row.success_rate : Number(row.success_rate))
		} else {
			warnings.push('Stream join telemetry not available')
		}
	} catch {
		warnings.push('Stream join telemetry not available')
	}

	return {
		range,
		revenueSeriesMwk,
		coinsSoldSeries,
		newUsersSeries,
		newSongsSeries,
		newVideosSeries,
		streamsStartedSeries,
		revenueMwk7d,
		revenueByTypeMwk,
		coinsSold7d,
		pendingWithdrawalsMwk,
		pendingWithdrawalsCount,
		newUsers7d,
		newSongs7d,
		newVideos7d,
		dau1d,
		mau30d,
		stickiness,
		openReports,
		frozenEarningsAccounts,
		activeStreams,
		avgViewersRecent: viewers.avg,
		maxViewersRecent: viewers.max,
		streamJoinAttempts,
		streamJoinSuccesses,
		streamJoinSuccessRate,
		warnings,
	}
}
