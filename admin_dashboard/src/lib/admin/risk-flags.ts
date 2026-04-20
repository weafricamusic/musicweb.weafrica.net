import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

export type RiskSeverity = 'low' | 'medium' | 'high' | 'critical'
export type RiskEntityType = 'artist' | 'dj' | 'stream' | 'withdrawal'

export type SuggestedAction = {
	label: string
	href?: string
	kind?: 'review' | 'open' | 'freeze' | 'reject' | 'stop_stream' | 'investigate'
}

export type RiskFlag = {
	fingerprint: string
	kind: string
	severity: RiskSeverity
	entity_type: RiskEntityType
	entity_id: string
	country_code?: string | null
	title: string
	description: string
	evidence: Record<string, unknown>
	suggested_actions: SuggestedAction[]
}

export type RiskScanResult = {
	flags: RiskFlag[]
	warnings: string[]
}

function clampInt(v: unknown, min: number, max: number, fallback: number): number {
	const n = Number(v)
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.floor(n)))
}

function isoSinceDays(days: number): string {
	const d = Math.max(1, Math.min(365, Math.floor(days)))
	return new Date(Date.now() - d * 24 * 60 * 60 * 1000).toISOString()
}

function parseJsonObject(value: unknown): Record<string, any> {
	if (!value || typeof value !== 'object') return {}
	return value as any
}

function getMetaString(meta: Record<string, any>, keys: string[]): string | null {
	for (const k of keys) {
		const v = meta?.[k]
		if (typeof v === 'string' && v.trim()) return v.trim()
		if (typeof v === 'number' && Number.isFinite(v)) return String(v)
	}
	return null
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

async function safeCountriesMinPayoutByCode(
	supabase: SupabaseClient,
): Promise<{ map: Map<string, number> | null; warning?: string }> {
	try {
		type CountryRow = { country_code?: unknown; code?: unknown; min_payout_amount?: unknown }

		// Primary schema: `country_code`
		const primary = await supabase.from('countries').select('country_code,min_payout_amount').limit(250)
		if (!primary.error) {
			const map = new Map<string, number>()
			for (const r of (primary.data ?? []) as unknown as CountryRow[]) {
				const code = String(r.country_code ?? '').trim().toUpperCase()
				const minP = Number(r.min_payout_amount ?? 0)
				if (code && Number.isFinite(minP)) map.set(code, minP)
			}
			return { map }
		}

		// Fallback legacy schema: `code`
		if (primary.error.code === '42703') {
			const legacy = await supabase.from('countries').select('code,min_payout_amount').limit(250)
			if (!legacy.error) {
				const map = new Map<string, number>()
				for (const r of (legacy.data ?? []) as unknown as CountryRow[]) {
					const code = String(r.code ?? '').trim().toUpperCase()
					const minP = Number(r.min_payout_amount ?? 0)
					if (code && Number.isFinite(minP)) map.set(code, minP)
				}
				return { map }
			}
			return {
				map: null,
				warning: `countries query failed: ${legacy.error?.code ?? ''} ${legacy.error?.message ?? ''}`.trim(),
			}
		}

		return {
			map: null,
			warning: `countries query failed: ${primary.error.code ?? ''} ${primary.error.message ?? ''}`.trim(),
		}
	} catch {
		return { map: null, warning: 'countries query failed: unexpected error' }
	}
}

function median(values: number[]): number | null {
	if (!values.length) return null
	const sorted = [...values].sort((a, b) => a - b)
	const mid = Math.floor(sorted.length / 2)
	if (sorted.length % 2 === 0) return (sorted[mid - 1] + sorted[mid]) / 2
	return sorted[mid]
}

function minutesBetween(startIso: unknown, endIso: unknown): number | null {
	try {
		const s = new Date(String(startIso))
		const e = new Date(String(endIso))
		if (Number.isNaN(s.getTime()) || Number.isNaN(e.getTime())) return null
		return Math.max(0, (e.getTime() - s.getTime()) / 60000)
	} catch {
		return null
	}
}

export async function computeAutomatedRiskFlags(input: {
	supabase: SupabaseClient
	days?: number
	countryCode?: string | null
}): Promise<RiskScanResult> {
	const warnings: string[] = []
	const days = clampInt(input.days ?? 7, 1, 90, 7)
	const countryCode = (input.countryCode ?? '').trim().toUpperCase() || null

	const since7 = isoSinceDays(days)
	const since14 = isoSinceDays(days * 2)
	const since1 = isoSinceDays(1)
	const since30 = isoSinceDays(30)

	const byCountry = (q: any) => (countryCode ? q.eq('country_code', countryCode) : q)

	// Countries map for payout thresholds
	const minPayoutByCountry = new Map<string, number>()
	const countries = await safeCountriesMinPayoutByCode(input.supabase)
	if (!countries.map) {
		warnings.push(countries.warning ?? 'countries table not accessible (RLS?)')
	} else {
		for (const [code, minP] of countries.map.entries()) minPayoutByCountry.set(code, minP)
	}

	const flags: RiskFlag[] = []

	// 1) Artists with unusual growth (gift coins 7d vs previous window)
	const artistTx = await safeList(
		input.supabase,
		'transactions',
		'target_id,target_type,type,coins,amount_mwk,created_at,country_code',
		(q) => byCountry(q).gte('created_at', since14).eq('target_type', 'artist').in('type', ['gift', 'battle_reward']),
		5000,
	)
	if (artistTx === null) {
		warnings.push('transactions table not accessible (RLS?)')
	} else {
		type Agg = { curCoins: number; prevCoins: number; curCount: number; prevCount: number; curMwk: number; prevMwk: number }
		const agg = new Map<string, Agg>()
		const cutoff = new Date(since7).getTime()
		for (const r of artistTx) {
			const id = String(r.target_id ?? '').trim()
			if (!id) continue
			const coins = Number(r.coins ?? 0)
			const mwk = Number(r.amount_mwk ?? 0)
			const created = new Date(String(r.created_at ?? '')).getTime()
			if (!Number.isFinite(created)) continue
			const isCur = created >= cutoff
			const a = agg.get(id) ?? { curCoins: 0, prevCoins: 0, curCount: 0, prevCount: 0, curMwk: 0, prevMwk: 0 }
			if (isCur) {
				if (Number.isFinite(coins)) a.curCoins += coins
				if (Number.isFinite(mwk)) a.curMwk += mwk
				a.curCount += 1
			} else {
				if (Number.isFinite(coins)) a.prevCoins += coins
				if (Number.isFinite(mwk)) a.prevMwk += mwk
				a.prevCount += 1
			}
			agg.set(id, a)
		}

		for (const [artistId, a] of agg.entries()) {
			if (a.curCount < 5) continue
			const ratio = (a.curCoins + 1) / (a.prevCoins + 1)
			const meaningful = a.curCoins >= 1500 || a.curMwk >= 150000
			if (!meaningful) continue
			if (ratio < 3) continue

			const severity: RiskSeverity = ratio >= 10 && a.curCoins >= 5000 ? 'high' : ratio >= 5 ? 'medium' : 'low'

			flags.push({
				fingerprint: `artist_unusual_growth:artist:${artistId}`,
				kind: 'artist_unusual_growth',
				severity,
				entity_type: 'artist',
				entity_id: artistId,
				country_code: countryCode,
				title: 'Artist unusual growth',
				description: `Gift/battle coins increased ~${Math.round(ratio * 10) / 10}× vs previous ${days}d window.`,
				evidence: {
					window_days: days,
					current_coins: a.curCoins,
					previous_coins: a.prevCoins,
					current_tx_count: a.curCount,
					previous_tx_count: a.prevCount,
					current_amount_mwk: Math.round(a.curMwk * 100) / 100,
					previous_amount_mwk: Math.round(a.prevMwk * 100) / 100,
					ratio,
				},
				suggested_actions: [
					{ label: 'Review artist', href: `/dashboard/artists/${encodeURIComponent(artistId)}`, kind: 'review' },
					{ label: 'Check transactions', href: `/admin/payments/transactions?type=gift`, kind: 'investigate' },
				],
			})
		}
	}

	// 2) DJs with low engagement (avg viewers in recent streams)
	const djStreams = await safeList(
		input.supabase,
		'live_streams',
		'host_type,host_id,viewer_count,started_at,ended_at,region,status',
		(q) => {
			let qq = q.gte('started_at', since14).eq('host_type', 'dj')
			if (countryCode) qq = qq.eq('region', countryCode)
			return qq
		},
		5000,
	)
	if (djStreams === null) {
		warnings.push('live_streams table not accessible (RLS?)')
	} else {
		type Agg = { curAvg: number; curCount: number; prevAvg: number; prevCount: number }
		const agg = new Map<string, Agg>()
		const cutoff = new Date(since7).getTime()

		for (const s of djStreams) {
			const djId = String(s.host_id ?? '').trim()
			if (!djId) continue
			const viewers = Number(s.viewer_count ?? 0)
			const started = new Date(String(s.started_at ?? '')).getTime()
			if (!Number.isFinite(started)) continue
			const isCur = started >= cutoff
			const a = agg.get(djId) ?? { curAvg: 0, curCount: 0, prevAvg: 0, prevCount: 0 }
			if (isCur) {
				a.curAvg += Number.isFinite(viewers) ? viewers : 0
				a.curCount += 1
			} else {
				a.prevAvg += Number.isFinite(viewers) ? viewers : 0
				a.prevCount += 1
			}
			agg.set(djId, a)
		}

		for (const [djId, a] of agg.entries()) {
			if (a.curCount < 2) continue
			const curAvg = a.curCount ? a.curAvg / a.curCount : 0
			const prevAvg = a.prevCount ? a.prevAvg / a.prevCount : null

			const veryLow = curAvg < 3
			const dropped = prevAvg != null && prevAvg > 0 && (prevAvg - curAvg) / prevAvg >= 0.6
			if (!(veryLow || (dropped && curAvg < 5))) continue

			const severity: RiskSeverity = veryLow && a.curCount >= 4 ? 'medium' : 'low'

			flags.push({
				fingerprint: `dj_low_engagement:dj:${djId}`,
				kind: 'dj_low_engagement',
				severity,
				entity_type: 'dj',
				entity_id: djId,
				country_code: countryCode,
				title: 'DJ low engagement',
				description: `Average viewers is low (${Math.round(curAvg * 10) / 10}).`,
				evidence: {
					window_days: days,
					current_streams: a.curCount,
					current_avg_viewers: Math.round(curAvg * 100) / 100,
					previous_streams: a.prevCount,
					previous_avg_viewers: prevAvg == null ? null : Math.round(prevAvg * 100) / 100,
				},
				suggested_actions: [
					{ label: 'Review DJ', href: `/dashboard/djs/${encodeURIComponent(djId)}`, kind: 'review' },
					{ label: 'Check live streams', href: `/admin/live-streams?status=all`, kind: 'investigate' },
				],
			})
		}
	}

	// 3) Streams with abnormal coin flow
	const recentStreams = await safeList(
		input.supabase,
		'live_streams',
		'id,viewer_count,started_at,ended_at,status,region,host_type,host_id',
		(q) => {
			let qq = q.gte('started_at', since1)
			if (countryCode) qq = qq.eq('region', countryCode)
			return qq
		},
		2000,
	)

	const giftTx = await safeList(
		input.supabase,
		'transactions',
		'id,type,coins,created_at,country_code,meta',
		(q) => byCountry(q).gte('created_at', since1).in('type', ['gift', 'battle_reward']),
		5000,
	)

	if (recentStreams && giftTx) {
		const streamById = new Map<string, any>()
		recentStreams.forEach((s) => streamById.set(String(s.id), s))

		const coinsByStream = new Map<string, number>()
		for (const tx of giftTx) {
			const meta = parseJsonObject(tx.meta)
			const streamId = getMetaString(meta, ['stream_id', 'live_stream_id', 'streamId', 'liveStreamId'])
			if (!streamId) continue
			const coins = Number(tx.coins ?? 0)
			if (!Number.isFinite(coins) || coins <= 0) continue
			coinsByStream.set(streamId, (coinsByStream.get(streamId) ?? 0) + coins)
		}

		const coinsPerViewerValues: number[] = []
		for (const [streamId, coins] of coinsByStream.entries()) {
			const s = streamById.get(String(streamId))
			if (!s) continue
			const viewers = Math.max(1, Number(s.viewer_count ?? 0) || 0)
			coinsPerViewerValues.push(coins / viewers)
		}

		const base = median(coinsPerViewerValues) ?? 0

		for (const [streamId, coins] of coinsByStream.entries()) {
			const s = streamById.get(String(streamId))
			if (!s) continue
			const viewers = Math.max(0, Number(s.viewer_count ?? 0) || 0)
			const startedAt = String(s.started_at ?? '')
			const endedAt = s.ended_at ? String(s.ended_at) : new Date().toISOString()
			const mins = minutesBetween(startedAt, endedAt) ?? null

			const coinsPerViewer = coins / Math.max(1, viewers)
			const coinsPerMinute = mins ? coins / Math.max(1, mins) : null

			const suspiciousRate = coins >= 1000 && (coinsPerViewer >= Math.max(200, base * 5) || (viewers <= 5 && coins >= 3000))
			if (!suspiciousRate) continue

			const severity: RiskSeverity = viewers <= 3 && coins >= 5000 ? 'high' : coins >= 3000 ? 'medium' : 'low'

			flags.push({
				fingerprint: `stream_abnormal_coin_flow:stream:${streamId}`,
				kind: 'stream_abnormal_coin_flow',
				severity,
				entity_type: 'stream',
				entity_id: String(streamId),
				country_code: countryCode,
				title: 'Stream abnormal coin flow',
				description: `High coins relative to viewers (coins/viewer: ${Math.round(coinsPerViewer * 10) / 10}).`,
				evidence: {
					window_hours: 24,
					coins,
					viewers,
					coins_per_viewer: Math.round(coinsPerViewer * 100) / 100,
					coins_per_minute: coinsPerMinute == null ? null : Math.round(coinsPerMinute * 100) / 100,
					baseline_median_coins_per_viewer: Math.round(base * 100) / 100,
					host_type: s.host_type ?? null,
					host_id: s.host_id ?? null,
					status: s.status ?? null,
				},
				suggested_actions: [
					{ label: 'Open stream', href: `/admin/live-streams/${encodeURIComponent(String(streamId))}`, kind: 'open' },
					{ label: 'Investigate gifts/transactions', href: `/admin/payments/transactions?type=gift`, kind: 'investigate' },
				],
			})
		}
	} else {
		if (!recentStreams) warnings.push('live_streams not accessible for coin-flow analysis')
		if (!giftTx) warnings.push('transactions not accessible for coin-flow analysis')
	}

	// 4) Payouts above threshold (pending withdrawals)
	const withdrawals = await safeList(
		input.supabase,
		'withdrawals',
		'id,beneficiary_type,beneficiary_id,amount_mwk,status,requested_at,country_code,method',
		(q) => byCountry(q).gte('requested_at', since30).eq('status', 'pending').order('requested_at', { ascending: false }),
		2000,
	)
	if (withdrawals === null) {
		warnings.push('withdrawals table not accessible (RLS?)')
	} else {
		const cutoff24h = new Date(isoSinceDays(1)).getTime()
		const pendingByBeneficiary24h = new Map<string, number>()
		for (const w of withdrawals) {
			const bType = String(w.beneficiary_type ?? '').trim()
			const bId = String(w.beneficiary_id ?? '').trim()
			if (!bType || !bId) continue
			const t = new Date(String(w.requested_at ?? '')).getTime()
			if (Number.isFinite(t) && t >= cutoff24h) {
				const key = `${bType}:${bId}`
				pendingByBeneficiary24h.set(key, (pendingByBeneficiary24h.get(key) ?? 0) + 1)
			}
		}

		for (const w of withdrawals) {
			const id = String(w.id)
			const bType = String(w.beneficiary_type ?? '').trim() as 'artist' | 'dj'
			const bId = String(w.beneficiary_id ?? '').trim()
			const amount = Number(w.amount_mwk ?? 0)
			const c = String(w.country_code ?? countryCode ?? '').trim().toUpperCase() || null
			if (!id || !bId || !Number.isFinite(amount) || amount <= 0) continue

			const minP = c ? (minPayoutByCountry.get(c) ?? null) : null
			const base = minP != null && Number.isFinite(minP) && minP > 0 ? minP : 50000
			const warnThreshold = base * 5
			const criticalThreshold = base * 20

			const over = amount >= warnThreshold
			const velocity = (pendingByBeneficiary24h.get(`${bType}:${bId}`) ?? 0) >= 3
			if (!over && !velocity) continue

			const severity: RiskSeverity = amount >= criticalThreshold ? 'critical' : amount >= warnThreshold * 2 ? 'high' : velocity ? 'medium' : 'low'

			flags.push({
				fingerprint: `payout_above_threshold:withdrawal:${id}`,
				kind: 'payout_above_threshold',
				severity,
				entity_type: 'withdrawal',
				entity_id: id,
				country_code: c,
				title: 'Payout flagged for review',
				description: `Pending withdrawal is high-risk (amount: ${Math.round(amount)} MWK${velocity ? ', rapid requests' : ''}).`,
				evidence: {
					withdrawal_id: id,
					beneficiary_type: bType,
					beneficiary_id: bId,
					amount_mwk: Math.round(amount * 100) / 100,
					method: w.method ?? null,
					country_code: c,
					min_payout_amount: minP,
					threshold_warn: warnThreshold,
					threshold_critical: criticalThreshold,
					pending_requests_24h: pendingByBeneficiary24h.get(`${bType}:${bId}`) ?? 0,
				},
				suggested_actions: [
					{ label: 'Open withdrawals (pending)', href: `/admin/payments/withdrawals?status=pending`, kind: 'review' },
					{ label: 'Consider freezing earnings', href: `/admin/payments/earnings/${encodeURIComponent(bType)}s`, kind: 'freeze' },
				],
			})
		}
	}

	return { flags, warnings }
}

export async function persistRiskFlags(input: {
	supabase: SupabaseClient
	flags: RiskFlag[]
}): Promise<{ inserted: number; error?: string }> {
	if (!input.flags.length) return { inserted: 0 }
	try {
		const payload = input.flags.map((f) => ({
			status: 'open',
			severity: f.severity,
			kind: f.kind,
			entity_type: f.entity_type,
			entity_id: f.entity_id,
			country_code: f.country_code ?? null,
			title: f.title,
			description: f.description,
			evidence: f.evidence ?? {},
			suggested_actions: f.suggested_actions ?? [],
			fingerprint: f.fingerprint,
		}))

		const { data, error } = await (input.supabase as any)
			.from('risk_flags')
			.upsert(payload, { onConflict: 'fingerprint', ignoreDuplicates: true })
			.select('id')

		if (error) return { inserted: 0, error: error.message ?? 'insert_failed' }
		return { inserted: Array.isArray(data) ? data.length : 0 }
	} catch (e) {
		return { inserted: 0, error: e instanceof Error ? e.message : 'insert_failed' }
	}
}
