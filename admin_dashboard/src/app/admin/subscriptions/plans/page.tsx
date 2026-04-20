'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'

type PlanId = string

type PlanRow = {
	plan_id: PlanId
	audience?: string | null
	name: string
	price_mwk: number
	billing_interval: 'month'
	coins_multiplier: number
	ads_enabled: boolean
	can_participate_battles: boolean
	battle_priority: 'none' | 'standard' | 'priority'
	analytics_level: 'basic' | 'standard' | 'advanced'
	content_access: 'limited' | 'standard' | 'exclusive'
	content_limit_ratio: number | null
	featured_status: boolean
	is_active: boolean
	sort_order?: number | null
	features: Record<string, unknown>
	perks?: Record<string, unknown> | null
	marketing?: Record<string, unknown> | null
	trial_eligible?: boolean | null
	trial_duration_days?: number | null
	created_at: string
	updated_at: string
}

type ApiList = { ok: true; plans: PlanRow[] } | { error: string }

type PatchBody = Partial<Omit<PlanRow, 'created_at' | 'updated_at'>> & { plan_id: PlanId }

type ApiPatch = { ok: true; plan: PlanRow } | { error: string }
type ApiCreate = { ok: true; plan: PlanRow } | { error: string }
type ApiDelete = { ok: true } | { error: string }

function asPlanId(value: unknown): PlanId | null {
	if (typeof value !== 'string' && typeof value !== 'number') return null
	const v = String(value).trim().toLowerCase()
	if (!v) return null
	if (v.length > 64) return null
	if (!/^[a-z0-9][a-z0-9_-]{1,63}$/.test(v)) return null
	return v
}

function prettyJson(value: unknown): string {
	try {
		return JSON.stringify(value ?? {}, null, 2)
	} catch {
		return '{}'
	}
}

function normalizedAudience(value: string | null | undefined): 'consumer' | 'artist' | 'dj' | 'other' {
	const audience = (value ?? '').trim().toLowerCase()
	if (audience === 'artist') return 'artist'
	if (audience === 'dj') return 'dj'
	if (audience === 'consumer') return 'consumer'
	return 'other'
}

function audienceLabel(value: string | null | undefined): string {
	switch (normalizedAudience(value)) {
		case 'artist':
			return 'Artists'
		case 'dj':
			return 'DJs'
		case 'consumer':
			return 'Consumers'
		default:
			return 'Other'
	}
}

function audienceRank(value: string | null | undefined): number {
	switch (normalizedAudience(value)) {
		case 'consumer':
			return 0
		case 'artist':
			return 1
		case 'dj':
			return 2
		default:
			return 3
	}
}

function planOrderValue(plan: PlanRow): number {
	const sortOrder = Number(plan.sort_order)
	if (Number.isFinite(sortOrder)) return sortOrder
	return Number(plan.price_mwk ?? 0)
}

function sortPlans(rows: PlanRow[]): PlanRow[] {
	return [...rows].sort((a, b) => {
		const audienceDiff = audienceRank(a.audience) - audienceRank(b.audience)
		if (audienceDiff !== 0) return audienceDiff

		const orderDiff = planOrderValue(a) - planOrderValue(b)
		if (orderDiff !== 0) return orderDiff

		return a.name.localeCompare(b.name)
	})
}

function groupPlans(rows: PlanRow[]): Array<{ key: string; label: string; plans: PlanRow[] }> {
	const groups = new Map<string, { key: string; label: string; plans: PlanRow[] }>()
	for (const plan of rows) {
		const key = normalizedAudience(plan.audience)
		const existing = groups.get(key)
		if (existing) {
			existing.plans.push(plan)
			continue
		}
		groups.set(key, {
			key,
			label: audienceLabel(plan.audience),
			plans: [plan],
		})
	}
	return [...groups.values()]
}

export default function SubscriptionPlansEditorPage() {
	const [plans, setPlans] = useState<PlanRow[] | null>(null)
	const [selected, setSelected] = useState<PlanId>('premium')
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)

	const sortedPlans = useMemo(() => sortPlans(plans ?? []), [plans])
	const groupedPlans = useMemo(() => groupPlans(sortedPlans), [sortedPlans])
	const plan = useMemo(() => sortedPlans.find((p) => p.plan_id === selected) ?? null, [sortedPlans, selected])

	const [name, setName] = useState('')
	const [audience, setAudience] = useState<'consumer' | 'artist' | 'dj'>('consumer')
	const [price, setPrice] = useState(0)
	const [interval, setInterval] = useState<'month'>('month')
	const [coinsMultiplier, setCoinsMultiplier] = useState(1)
	const [adsEnabled, setAdsEnabled] = useState(false)
	const [canBattles, setCanBattles] = useState(false)
	const [battlePriority, setBattlePriority] = useState<'none' | 'standard' | 'priority'>('none')
	const [analyticsLevel, setAnalyticsLevel] = useState<'basic' | 'standard' | 'advanced'>('basic')
	const [contentAccess, setContentAccess] = useState<'limited' | 'standard' | 'exclusive'>('limited')
	const [contentLimitRatio, setContentLimitRatio] = useState<number | ''>('')
	const [featuredStatus, setFeaturedStatus] = useState(false)
	const [isActive, setIsActive] = useState(true)
	const [sortOrder, setSortOrder] = useState<number | ''>('')
	const [trialEligible, setTrialEligible] = useState(false)
	const [trialDurationDays, setTrialDurationDays] = useState<number | ''>('')
	const [featuresText, setFeaturesText] = useState('')
	const [perksText, setPerksText] = useState('')

	useEffect(() => {
		let cancelled = false
		async function load() {
			setError(null)
			const res = await fetch('/api/admin/subscriptions/plans', { method: 'GET' })
			const json = (await res.json().catch(() => null)) as ApiList | null
			if (cancelled) return
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			const rawPlans = Array.isArray(json.plans) ? json.plans : []
			const validPlans = rawPlans
				.map((p) => {
					const planId = asPlanId((p as any)?.plan_id)
					if (!planId) return null
					return { ...(p as any), plan_id: planId } as PlanRow
				})
				.filter(Boolean) as PlanRow[]
			const orderedPlans = sortPlans(validPlans)
			setPlans(orderedPlans)
			const first = orderedPlans[0]?.plan_id
			if (first) setSelected(first)
		}
		void load()
		return () => {
			cancelled = true
		}
	}, [])

	useEffect(() => {
		if (!plan) return
		setName(plan.name)
		const aud = normalizedAudience(plan.audience)
		setAudience(aud === 'artist' ? 'artist' : aud === 'dj' ? 'dj' : 'consumer')
		setPrice(Number(plan.price_mwk ?? 0))
		setInterval(plan.billing_interval)
		setCoinsMultiplier(Number(plan.coins_multiplier ?? 1))
		setAdsEnabled(!!plan.ads_enabled)
		setCanBattles(!!plan.can_participate_battles)
		setBattlePriority(plan.battle_priority)
		setAnalyticsLevel(plan.analytics_level)
		setContentAccess(plan.content_access)
		setContentLimitRatio(plan.content_limit_ratio == null ? '' : Number(plan.content_limit_ratio))
		setFeaturedStatus(!!plan.featured_status)
		setIsActive(plan.is_active)
		setSortOrder(plan.sort_order == null ? '' : Number(plan.sort_order))
		setTrialEligible(!!plan.trial_eligible)
		setTrialDurationDays(plan.trial_duration_days == null ? '' : Number(plan.trial_duration_days))
		setFeaturesText(prettyJson(plan.features))
		setPerksText(prettyJson(plan.perks))
		setOk(null)
		setError(null)
	}, [plan?.plan_id])

	async function save() {
		setOk(null)
		setError(null)
		if (!plan) return

		let features: Record<string, unknown> = {}
		let perks: Record<string, unknown> = {}
		try {
			features = JSON.parse(featuresText || '{}') as Record<string, unknown>
		} catch {
			setError('Features JSON is invalid.')
			return
		}

		try {
			perks = JSON.parse(perksText || '{}') as Record<string, unknown>
		} catch {
			setError('Perks JSON is invalid.')
			return
		}

		const payload: PatchBody = {
			plan_id: plan.plan_id,
			audience: 'consumer',
			name,
			price_mwk: Number(price) || 0,
			billing_interval: interval,
			coins_multiplier: Number(coinsMultiplier) || 1,
			ads_enabled: !!adsEnabled,
			can_participate_battles: !!canBattles,
			battle_priority: battlePriority,
			analytics_level: analyticsLevel,
			content_access: contentAccess,
			content_limit_ratio: contentLimitRatio === '' ? null : Math.max(0, Math.min(1, Number(contentLimitRatio))),
			featured_status: !!featuredStatus,
			is_active: isActive,
			sort_order: sortOrder === '' ? null : Number(sortOrder),
			trial_eligible: trialEligible,
			trial_duration_days: trialEligible
				? Math.max(0, Number(trialDurationDays === '' ? 30 : trialDurationDays) || 0)
				: 0,
			features,
			perks,
		}

		setBusy(true)
		try {
			const res = await fetch('/api/admin/subscriptions/plans', {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(payload),
			})
			const json = (await res.json().catch(() => null)) as ApiPatch | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}

			setPlans((prev) => (prev ? sortPlans(prev.map((p) => (p.plan_id === json.plan.plan_id ? json.plan : p))) : prev))
			setOk('Saved.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Save failed.')
		} finally {
			setBusy(false)
		}
	}

	async function seed(planId: PlanId) {
		setOk(null)
		setError(null)
		setBusy(true)
		try {
			const res = await fetch('/api/admin/subscriptions/plans', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'create_plan', plan_id: planId }),
			})
			const json = (await res.json().catch(() => null)) as ApiCreate | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setPlans((prev) => {
				const next = prev ? [...prev] : []
				const idx = next.findIndex((p) => p.plan_id === json.plan.plan_id)
				if (idx >= 0) next[idx] = json.plan
				else next.push(json.plan)
				return sortPlans(next)
			})
			setSelected(planId)
			setOk('Plan seeded.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Create failed.')
		} finally {
			setBusy(false)
		}
	}

	async function deletePlan(planId: PlanId) {
		setOk(null)
		setError(null)
		if (planId === 'free') {
			setError('Free plan cannot be deleted.')
			return
		}
		if (!confirm(`Delete plan "${planId}"? This is rarely used.`)) return

		setBusy(true)
		try {
			const res = await fetch('/api/admin/subscriptions/plans', {
				method: 'DELETE',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'delete_plan', plan_id: planId }),
			})
			const json = (await res.json().catch(() => null)) as ApiDelete | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setPlans((prev) => (prev ? prev.filter((p) => p.plan_id !== planId) : prev))
			setSelected('free')
			setOk('Deleted.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Delete failed.')
		} finally {
			setBusy(false)
		}
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Subscription Plans</h1>
					<p className="mt-1 text-sm text-gray-400">Edit price, status, and features JSON.</p>
				</div>
				<Link href="/admin/subscriptions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div>
			) : null}
			{ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">{ok}</div>
			) : null}

			<div className="grid gap-6 md:grid-cols-[300px_1fr]">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Select plan</h2>
					<div className="mt-4 space-y-4">
						{groupedPlans.map((group) => (
							<div key={group.key} className="space-y-2">
								<p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-gray-500">{group.label}</p>
								<div className="grid gap-2">
									{group.plans.map((p, idx) => (
										<button
											key={p.plan_id ?? `${p.name ?? 'plan'}-${idx}`}
											type="button"
											onClick={() => setSelected(p.plan_id)}
											className={`rounded-xl border px-3 py-2 text-left text-sm hover:bg-white/5 ${selected === p.plan_id ? 'border-white/30 bg-white/10' : 'border-white/10 bg-black/10'}`}
										>
											<div className="flex items-center justify-between gap-3">
												<span className="font-medium">{p.name}</span>
												<span className="text-xs text-gray-400">MWK {Number(p.price_mwk ?? 0).toLocaleString()}</span>
											</div>
											<div className="mt-1 flex items-center justify-between gap-3 text-[11px] text-gray-500">
												<span>{p.plan_id}</span>
												<span>{p.trial_eligible ? `${Number(p.trial_duration_days ?? 0)}d trial` : 'No trial'}</span>
											</div>
										</button>
									))}
								</div>
							</div>
						))}
					</div>

					<div className="mt-6 rounded-xl border border-white/10 bg-black/10 p-4">
						<p className="text-xs text-gray-400">Missing a consumer launch plan?</p>
						<div className="mt-2 flex flex-wrap gap-2">
							{(['free', 'premium', 'platinum'] as PlanId[]).map((id) => (
								<button
									key={id}
									type="button"
									onClick={() => seed(id)}
									disabled={busy}
									className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5 disabled:opacity-60"
								>
									Seed {id}
								</button>
							))}
						</div>
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					{plan ? (
						<>
							<h2 className="text-base font-semibold">Edit: {plan.name}</h2>
							<p className="mt-1 text-sm text-gray-400">Duration is currently fixed to monthly (30 days).</p>

							<div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
								<div>
									<label className="text-xs text-gray-400">Name</label>
									<input
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={name}
										onChange={(e) => setName(e.target.value)}
									/>
								</div>

								<div>
									<label className="text-xs text-gray-400">Audience</label>
									<select
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={audience}
										disabled
										onChange={() => null}
									>
										<option value="consumer">Consumer</option>
									</select>
								</div>

								<div>
									<label className="text-xs text-gray-400">Price (MWK)</label>
									<input
										type="number"
										min={0}
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={price}
										onChange={(e) => setPrice(Number(e.target.value))}
									/>
								</div>

								<div>
									<label className="text-xs text-gray-400">Billing interval</label>
									<select
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={interval}
										onChange={(e) => setInterval(e.target.value as 'month')}
									>
										<option value="month">Monthly (30 days)</option>
									</select>
								</div>

								<div>
									<label className="text-xs text-gray-400">Sort order</label>
									<input
										type="number"
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={sortOrder}
										onChange={(e) => setSortOrder(e.target.value === '' ? '' : Number(e.target.value))}
										placeholder="10, 20, 30..."
									/>
								</div>

								<div>
									<label className="text-xs text-gray-400">Coins multiplier</label>
									<input
										type="number"
										min={1}
										max={10}
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={coinsMultiplier}
										onChange={(e) => setCoinsMultiplier(Number(e.target.value))}
									/>
								</div>

								<div className="space-y-2">
									<label className="text-xs text-gray-400">Ads</label>
									<label className="flex items-center gap-2 text-sm text-gray-200">
										<input type="checkbox" checked={adsEnabled} onChange={(e) => setAdsEnabled(e.target.checked)} />
										Ads enabled
									</label>
								</div>

								<div className="space-y-2">
									<label className="text-xs text-gray-400">Live battles</label>
									<label className="flex items-center gap-2 text-sm text-gray-200">
										<input type="checkbox" checked={canBattles} onChange={(e) => setCanBattles(e.target.checked)} />
										Can participate
									</label>
								</div>

								<div>
									<label className="text-xs text-gray-400">Battle priority</label>
									<select
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={battlePriority}
										onChange={(e) => setBattlePriority(e.target.value as any)}
									>
										<option value="none">None</option>
										<option value="standard">Standard</option>
										<option value="priority">Priority</option>
									</select>
								</div>

								<div>
									<label className="text-xs text-gray-400">Analytics level</label>
									<select
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={analyticsLevel}
										onChange={(e) => setAnalyticsLevel(e.target.value as any)}
									>
										<option value="basic">Basic</option>
										<option value="standard">Standard</option>
										<option value="advanced">Advanced</option>
									</select>
								</div>

								<div>
									<label className="text-xs text-gray-400">Content access</label>
									<select
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={contentAccess}
										onChange={(e) => setContentAccess(e.target.value as any)}
									>
										<option value="limited">Limited</option>
										<option value="standard">Standard</option>
										<option value="exclusive">Exclusive</option>
									</select>
								</div>

								<div>
									<label className="text-xs text-gray-400">Content limit ratio (0-1)</label>
									<input
										type="number"
										min={0}
										max={1}
										step={0.05}
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={contentLimitRatio}
										onChange={(e) => setContentLimitRatio(e.target.value === '' ? '' : Number(e.target.value))}
										placeholder="0.3 for Free"
									/>
								</div>

								<div className="space-y-2">
									<label className="text-xs text-gray-400">Trial offer</label>
									<label className="flex items-center gap-2 text-sm text-gray-200">
										<input type="checkbox" checked={trialEligible} onChange={(e) => setTrialEligible(e.target.checked)} />
										Trial eligible
									</label>
								</div>

								<div>
									<label className="text-xs text-gray-400">Trial duration (days)</label>
									<input
										type="number"
										min={0}
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20 disabled:opacity-60"
										value={trialDurationDays}
										onChange={(e) => setTrialDurationDays(e.target.value === '' ? '' : Number(e.target.value))}
										disabled={!trialEligible}
										placeholder="30"
									/>
								</div>

								<div className="space-y-2">
									<label className="text-xs text-gray-400">Featured status</label>
									<label className="flex items-center gap-2 text-sm text-gray-200">
										<input type="checkbox" checked={featuredStatus} onChange={(e) => setFeaturedStatus(e.target.checked)} />
										Featured
									</label>
								</div>

								<div className="space-y-2">
									<label className="text-xs text-gray-400">Status</label>
									<label className="flex items-center gap-2 text-sm text-gray-200">
										<input
											type="checkbox"
											checked={isActive}
											onChange={(e) => setIsActive(e.target.checked)}
											disabled={plan.plan_id === 'free'}
										/>
										Active
									</label>
									{plan.plan_id === 'free' ? <p className="text-xs text-gray-500">Free is always active.</p> : null}
								</div>
							</div>

							<div className="mt-4">
								<label className="text-xs text-gray-400">Features JSON</label>
								<textarea
									rows={16}
									className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 font-mono text-xs outline-none focus:border-white/20"
									value={featuresText}
									onChange={(e) => setFeaturesText(e.target.value)}
								/>
									<p className="mt-2 text-xs text-gray-500">Tip: prefer nested keys like ads, playback, downloads, live, tickets, coins, featured, and vip_badge. Legacy keys like ads_enabled and analytics_level are still supported.</p>
							</div>

							<div className="mt-4">
								<label className="text-xs text-gray-400">Perks JSON</label>
								<textarea
									rows={14}
									className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 font-mono text-xs outline-none focus:border-white/20"
									value={perksText}
									onChange={(e) => setPerksText(e.target.value)}
								/>
								<p className="mt-2 text-xs text-gray-500">Keep `perks` as the lighter-weight fan and creator experience contract. Do not bury it under `features.perks`.</p>
							</div>

							<div className="mt-5 flex items-center justify-between gap-3">
								<button
									type="button"
									onClick={save}
									disabled={busy}
									className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
								>
									{busy ? 'Saving…' : 'Save changes'}
								</button>
								<div className="text-xs text-gray-500">Created: {new Date(plan.created_at).toLocaleString()} • Updated: {new Date(plan.updated_at).toLocaleString()}</div>
							</div>

							{plan.plan_id !== 'free' ? (
								<div className="mt-4">
									<button
										type="button"
										onClick={() => deletePlan(plan.plan_id)}
										disabled={busy}
										className="h-10 rounded-xl border border-red-500/30 bg-red-500/10 px-4 text-sm text-red-200 hover:bg-red-500/15 disabled:opacity-60"
									>
										Delete plan
									</button>
									<p className="mt-2 text-xs text-gray-500">Delete only if unused; otherwise disable.</p>
								</div>
							) : null}

							<div className="mt-6 rounded-xl border border-white/10 bg-black/10 p-4">
								<p className="text-xs text-gray-400">Current stored JSON</p>
								<pre className="mt-2 whitespace-pre-wrap break-words text-xs text-gray-200">{prettyJson(plan.features)}</pre>
								<p className="mt-4 text-xs text-gray-400">Current stored perks</p>
								<pre className="mt-2 whitespace-pre-wrap break-words text-xs text-gray-200">{prettyJson(plan.perks)}</pre>
							</div>
						</>
					) : (
						<p className="text-sm text-gray-400">Loading…</p>
					)}
				</div>
			</div>
		</div>
	)
}
