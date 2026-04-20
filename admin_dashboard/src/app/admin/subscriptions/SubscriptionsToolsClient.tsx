'use client'

import { useEffect, useMemo, useState } from 'react'
import { isArtistPlan, isConsumerPlan, isDjPlan } from '@/lib/subscription/admin-plan-scope'

type PlanRow = {
  plan_id: string
  audience?: string | null
  name?: string | null
  price_mwk?: number | null
  billing_interval?: string | null
  is_active?: boolean | null
  active?: boolean | null
}

type PlansResponse =
  | { ok: true; plans: PlanRow[] }
  | { error: string }

type ApiResponse =
  | { ok: true; subscription_id: number; transaction_id: number | null; warning?: string }
  | { error: string }

type DurationMode = 'days' | 'months'

type AudienceFilter = 'all' | 'consumer' | 'artist' | 'dj'

type SearchUserRow = {
  uid: string
  name: string
  email: string | null
  role: 'consumer' | 'artist' | 'dj'
}

type SearchUsersResponse =
  | { ok: true; users: SearchUserRow[] }
  | { error: string }

type Props = {
  initialUserId?: string
  audience?: AudienceFilter
}

function isValidPlanId(value: string): boolean {
  if (!value) return false
  if (value.length > 64) return false
  return /^[a-z0-9][a-z0-9_-]{1,63}$/.test(value)
}

function isPlanActive(p: PlanRow): boolean {
  if (typeof p.is_active === 'boolean') return p.is_active
  if (typeof p.active === 'boolean') return p.active
  return true
}

function formatPlanLabel(p: PlanRow): string {
  const name = (typeof p.name === 'string' && p.name.trim()) ? p.name.trim() : p.plan_id
  const audience = (typeof p.audience === 'string' && p.audience.trim()) ? p.audience.trim() : null
  const interval = (typeof p.billing_interval === 'string' && p.billing_interval.trim()) ? p.billing_interval.trim() : null
  const price = typeof p.price_mwk === 'number' ? `MWK ${p.price_mwk.toLocaleString()}` : null
  const meta = [audience, price, interval].filter(Boolean).join(' • ')
  return meta ? `${name} (${p.plan_id}) — ${meta}` : `${name} (${p.plan_id})`
}

export default function SubscriptionsToolsClient(props: Props = {}) {
  const initialUserId = typeof props.initialUserId === 'string' ? props.initialUserId.trim() : ''
  const audienceRaw = typeof props.audience === 'string' ? props.audience.trim().toLowerCase() : 'all'
  const audience: AudienceFilter =
    audienceRaw === 'consumer' || audienceRaw === 'artist' || audienceRaw === 'dj' ? (audienceRaw as AudienceFilter) : 'all'
  const [userId, setUserId] = useState(() => initialUserId)
  const [userSearch, setUserSearch] = useState('')
  const [userResults, setUserResults] = useState<SearchUserRow[] | null>(null)
  const [userSearchError, setUserSearchError] = useState<string | null>(null)
  const [plans, setPlans] = useState<PlanRow[] | null>(null)
  const [plansError, setPlansError] = useState<string | null>(null)

  // Optional prefill for pages that deep-link into subscription management.
  // We only apply it if the field is still empty to avoid clobbering manual input.
  useEffect(() => {
    if (!initialUserId) return
    setUserId((prev) => (prev.trim() ? prev : initialUserId))
  }, [initialUserId])

  const [planId, setPlanId] = useState<string>('premium')

  // Manual subscriptions are commonly used for promotions / partnerships / free trials.
  // Default to 30 days to match the requested workflow.
  const [durationMode, setDurationMode] = useState<DurationMode>('days')
  const [days, setDays] = useState(30)
  const [months, setMonths] = useState(1)
  const [autoRenew, setAutoRenew] = useState(false)
  const [createTx, setCreateTx] = useState(false)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<ApiResponse | null>(null)

  useEffect(() => {
  let cancelled = false
  ; (async () => {
    try {
      const res = await fetch('/api/admin/subscriptions/plans', { method: 'GET' })
      const json = (await res.json().catch(() => null)) as PlansResponse | null
      if (!json) throw new Error(`Failed to load plans (status ${res.status}).`)
      if ('error' in json) throw new Error(json.error)
      if (cancelled) return
      const next = (json.plans ?? []).filter((p) => p && typeof p.plan_id === 'string')
      setPlans(next)
      setPlansError(null)
    } catch (e) {
      if (cancelled) return
      setPlans(null)
      setPlansError(e instanceof Error ? e.message : 'Failed to load plans.')
    }
  })()
  return () => {
    cancelled = true
  }
  }, [])

  useEffect(() => {
    const q = userSearch.trim()
    if (q.length < 2) {
      setUserResults(null)
      setUserSearchError(null)
      return
    }

    let cancelled = false
    const handle = setTimeout(() => {
      ;(async () => {
        try {
          const role = audience === 'all' ? 'all' : audience
          const url = `/api/admin/users/search?q=${encodeURIComponent(q)}&role=${encodeURIComponent(role)}`
          const res = await fetch(url, { method: 'GET' })
          const json = (await res.json().catch(() => null)) as SearchUsersResponse | null
          if (!json) throw new Error(`Failed to search users (status ${res.status}).`)
          if ('error' in json) throw new Error(json.error)
          if (cancelled) return
          setUserResults(Array.isArray(json.users) ? json.users : [])
          setUserSearchError(null)
        } catch (e) {
          if (cancelled) return
          setUserResults([])
          setUserSearchError(e instanceof Error ? e.message : 'Failed to search users.')
        }
      })()
    }, 250)

    return () => {
      cancelled = true
      clearTimeout(handle)
    }
  }, [userSearch, audience])

  const normalizedPlanId = useMemo(() => planId.trim().toLowerCase(), [planId])

  const visiblePlans = useMemo(() => {
    const list = plans ?? []
    if (!list.length) return []
    if (audience === 'consumer') return list.filter((p) => isConsumerPlan(p))
    if (audience === 'artist') return list.filter((p) => isArtistPlan(p))
    if (audience === 'dj') return list.filter((p) => isDjPlan(p))
    return list
  }, [plans, audience])

  const isFreeLike = useMemo(() => {
  return normalizedPlanId === 'free' || normalizedPlanId === 'starter'
    }, [normalizedPlanId])

  const daysClamped = useMemo(() => {
  if (isFreeLike) return 0
  const n = Math.trunc(Number(days))
  if (!Number.isFinite(n)) return 30
  return Math.max(1, Math.min(30, n))
  }, [days, isFreeLike])

  const monthsClamped = useMemo(() => {
  if (isFreeLike) return 0
  const n = Math.trunc(Number(months))
  if (!Number.isFinite(n)) return 1
  return Math.max(1, Math.min(24, n))
  }, [months, isFreeLike])

  useEffect(() => {
  if (durationMode !== 'months') setAutoRenew(false)
  }, [durationMode])

  useEffect(() => {
  if (!plans?.length) return
  setPlanId((prev) => {
    const current = String(prev ?? '').trim().toLowerCase()
    const list = visiblePlans.length ? visiblePlans : plans
    if (current && list.some((p) => String(p.plan_id ?? '').trim().toLowerCase() === current)) return current
    const preferred =
      list.find((p) => String(p.plan_id ?? '').trim().toLowerCase() === 'premium')?.plan_id ??
      list.find((p) => String(p.plan_id ?? '').trim().toLowerCase() === 'pro')?.plan_id ??
      list.find((p) => isPlanActive(p))?.plan_id ??
      list[0]!.plan_id
    return String(preferred ?? 'premium')
  })
  }, [plans, visiblePlans])

  useEffect(() => {
  if (!isFreeLike) return
  setAutoRenew(false)
  setCreateTx(false)
  }, [isFreeLike])

  async function submit() {
    setResult(null)
    const uid = userId.trim()
    if (!uid) {
      setResult({ error: 'Enter a user ID (Firebase UID or internal user id).' })
      return
    }

	const pid = normalizedPlanId
	if (!isValidPlanId(pid)) {
		setResult({ error: 'Invalid plan_id. Use letters/numbers with - or _ (max 64 chars).' })
      return
    }

    setBusy(true)
    try {
		const payload: Record<string, unknown> = {
			action: 'set_user_subscription',
			user_id: uid,
			plan_id: pid,
		}

		if (isFreeLike) {
			payload.months = 0
			payload.auto_renew = false
			payload.create_transaction = false
		} else if (durationMode === 'days') {
			payload.duration_minutes = daysClamped * 24 * 60
			payload.months = 0
			payload.auto_renew = false
			payload.create_transaction = !!createTx
		} else {
			payload.months = monthsClamped
			payload.auto_renew = !!autoRenew
			payload.create_transaction = !!createTx
		}

      const res = await fetch('/api/admin/subscriptions/tools', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
		body: JSON.stringify(payload),
      })

      const json = (await res.json().catch(() => null)) as ApiResponse | null
      if (!json) {
        setResult({ error: `Request failed (status ${res.status}).` })
      } else if (!res.ok) {
        const maybeError = (json as unknown as { error?: unknown })?.error
        setResult({ error: typeof maybeError === 'string' ? maybeError : `Request failed (status ${res.status}).` })
      } else {
        setResult(json)
      }
    } catch (e: unknown) {
      setResult({ error: e instanceof Error ? e.message : 'Request failed.' })
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
      <h2 className="text-base font-semibold">Manual subscription</h2>
      <p className="mt-1 text-sm text-gray-400">
        Use this for promotions, partnerships, and free trials. This creates an active row in{' '}
        <span className="font-mono">user_subscriptions</span> and (optionally) inserts a matching{' '}
        <span className="font-mono">transactions</span> entry of type <span className="font-mono">subscription</span>.
      </p>

      {result && 'error' in result ? (
        <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-100">
          {result.error}
        </div>
      ) : null}

      {result && 'ok' in result ? (
        <div className="mt-4 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-100">
          Subscription set. id={result.subscription_id}
          {result.transaction_id ? `, tx=${result.transaction_id}` : ''}
          {result.warning ? ` (warning: ${result.warning})` : ''}
        </div>
      ) : null}

      <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
      <div className="md:col-span-2">
        <label className="text-xs text-gray-400">Search user</label>
        <input
          className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
          value={userSearch}
          onChange={(e) => setUserSearch(e.target.value)}
          placeholder="Type a name (e.g. Steve)"
        />
        {userSearchError ? <p className="mt-1 text-xs text-gray-500">{userSearchError}</p> : null}
        {userResults && userSearch.trim().length >= 2 ? (
          <div className="mt-2 max-h-56 overflow-auto rounded-xl border border-white/10 bg-black/10">
            {userResults.length ? (
              userResults.map((u) => (
                <button
                  key={u.uid}
                  type="button"
                  onClick={() => {
                    setUserId(u.uid)
                    setUserSearch(u.name)
                    setUserResults(null)
                    setUserSearchError(null)
                  }}
                  className="block w-full px-3 py-2 text-left text-sm hover:bg-white/5"
                  title={u.uid}
                >
                  <div className="font-medium">{u.name}</div>
                  <div className="text-xs text-gray-500">
                    {u.role}
                    {u.email ? ` • ${u.email}` : ''}
                    {u.uid ? ` • ${u.uid}` : ''}
                  </div>
                </button>
              ))
            ) : (
              <div className="px-3 py-2 text-sm text-gray-400">No users found.</div>
            )}
          </div>
        ) : null}
      </div>

        <div>
          <label className="text-xs text-gray-400">User ID</label>
          <input
            className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
            value={userId}
            onChange={(e) => setUserId(e.target.value)}
            placeholder="Firebase UID / user id"
          />
        </div>

        <div>
          <label className="text-xs text-gray-400">Plan</label>
          {plans && plans.length ? (
      <select
        className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
        value={normalizedPlanId}
        onChange={(e) => setPlanId(e.target.value)}
      >
				{(visiblePlans.length ? visiblePlans : plans).map((p) => {
					const active = isPlanActive(p)
					const label = active ? formatPlanLabel(p) : `${formatPlanLabel(p)} (inactive)`
					return (
            <option key={p.plan_id} value={String(p.plan_id ?? '').trim().toLowerCase()}>
							{label}
						</option>
					)
				})}
      </select>
    ) : (
      <input
        className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
        value={planId}
        onChange={(e) => setPlanId(e.target.value)}
        placeholder="plan_id (e.g. premium, pro, elite_weekly)"
      />
    )}
    {plansError ? <p className="mt-1 text-xs text-gray-500">Could not load plans: {plansError}</p> : null}
        </div>

        <div>
          <label className="text-xs text-gray-400">Duration</label>
    <div className="mt-1 flex gap-2">
      <select
        value={durationMode}
        disabled={isFreeLike}
        onChange={(e) => setDurationMode(e.target.value as DurationMode)}
        className="h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none focus:border-white/20 disabled:opacity-60"
      >
        <option value="days">Days (default 30)</option>
        <option value="months">Months</option>
      </select>

      {durationMode === 'months' ? (
        <input
          type="number"
          min={1}
          max={24}
          disabled={isFreeLike}
          className="h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20 disabled:opacity-60"
          value={monthsClamped}
          onChange={(e) => setMonths(Number(e.target.value))}
        />
      ) : (
        <input
          type="number"
          min={1}
          max={30}
          disabled={isFreeLike}
          className="h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20 disabled:opacity-60"
          value={daysClamped}
          onChange={(e) => setDays(Number(e.target.value))}
        />
      )}
    </div>
    {isFreeLike ? <p className="mt-1 text-xs text-gray-500">Free plan sets no expiry.</p> : null}
        </div>

        <div className="space-y-2">
          <label className="text-xs text-gray-400">Options</label>

          <label className="flex items-center gap-2 text-sm text-gray-200">
            <input
        type="checkbox"
        checked={!isFreeLike && durationMode === 'months' ? autoRenew : false}
        disabled={isFreeLike || durationMode !== 'months'}
        onChange={(e) => setAutoRenew(e.target.checked)}
      />
            Auto-renew
          </label>

          <label className="flex items-center gap-2 text-sm text-gray-200">
            <input
        type="checkbox"
        checked={isFreeLike ? false : createTx}
        disabled={isFreeLike}
        onChange={(e) => setCreateTx(e.target.checked)}
      />
            Create transaction (revenue)
          </label>
        </div>
      </div>

      <div className="mt-5">
        <button
          type="button"
          onClick={submit}
          disabled={busy}
          className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
        >
          {busy ? 'Working…' : 'Set subscription'}
        </button>
      </div>
    </div>
  )
}
