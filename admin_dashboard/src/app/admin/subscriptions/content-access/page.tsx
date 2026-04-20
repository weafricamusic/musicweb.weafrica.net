'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'

type PlanId = 'free' | 'premium' | 'platinum'

type Row = {
	plan_id: PlanId
	rules: Record<string, unknown>
	created_at: string
	updated_at: string
}

type ApiList = { ok: true; rows: Row[] } | { error: string }

type ApiPut = { ok: true; row: Row } | { error: string }

function prettyJson(value: unknown): string {
	try {
		return JSON.stringify(value ?? {}, null, 2)
	} catch {
		return '{}'
	}
}

export default function ContentAccessRulesPage() {
	const [rows, setRows] = useState<Row[] | null>(null)
	const [selected, setSelected] = useState<PlanId>('free')
	const [text, setText] = useState('')
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)

	const row = useMemo(() => rows?.find((r) => r.plan_id === selected) ?? null, [rows, selected])

	useEffect(() => {
		let cancelled = false
		async function load() {
			setError(null)
			const res = await fetch('/api/admin/subscriptions/content-access', { method: 'GET' })
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
			setRows(json.rows)
		}
		void load()
		return () => {
			cancelled = true
		}
	}, [])

	useEffect(() => {
		if (!row) return
		setText(prettyJson(row.rules))
		setOk(null)
		setError(null)
	}, [row?.plan_id])

	async function save() {
		setOk(null)
		setError(null)
		if (!row) return

		let rules: Record<string, unknown> = {}
		try {
			rules = JSON.parse(text || '{}') as Record<string, unknown>
		} catch {
			setError('Rules JSON is invalid.')
			return
		}

		setBusy(true)
		try {
			const res = await fetch('/api/admin/subscriptions/content-access', {
				method: 'PUT',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ plan_id: row.plan_id, rules }),
			})
			const json = (await res.json().catch(() => null)) as ApiPut | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setRows((prev) => (prev ? prev.map((r) => (r.plan_id === json.row.plan_id ? json.row : r)) : prev))
			setOk('Saved.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Save failed.')
		} finally {
			setBusy(false)
		}
	}

	const examples = {
		free: {
			content_limit_ratio: 0.3,
			allowed_categories: ['trending'],
			live_streams: { can_watch: true, can_go_live: false, can_join_battles: false },
		},
		premium: {
			content_limit_ratio: 1.0,
			allowed_categories: ['all'],
			live_streams: { can_watch: true, can_go_live: false, can_join_battles: true },
			exclusive_content: { level: 'standard' },
		},
		platinum: {
			content_limit_ratio: 1.0,
			allowed_categories: ['all'],
			live_streams: { can_watch: true, can_go_live: false, can_join_battles: true, priority_battles: true },
			exclusive_content: { level: 'vip', featured_artist_dj: true },
		},
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Content Access Rules</h1>
					<p className="mt-1 text-sm text-gray-400">Configure what each plan can see/do.</p>
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
					<h2 className="text-base font-semibold">Plan</h2>
					<div className="mt-4 grid gap-2">
						{(['free', 'premium', 'platinum'] as PlanId[]).map((p) => (
							<button
								key={p}
								type="button"
								onClick={() => setSelected(p)}
								className={`h-10 rounded-xl border px-3 text-left text-sm hover:bg-white/5 ${selected === p ? 'border-white/30 bg-white/10' : 'border-white/10 bg-black/10'}`}
							>
								<span className="font-medium">{p}</span>
							</button>
						))}
					</div>

					<div className="mt-6 rounded-xl border border-white/10 bg-black/10 p-4">
						<p className="text-xs text-gray-400">Example</p>
						<pre className="mt-2 whitespace-pre-wrap break-words text-xs text-gray-200">{prettyJson((examples as any)[selected])}</pre>
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Rules JSON</h2>
					<p className="mt-1 text-sm text-gray-400">This is flexible JSON; backend enforcement can read it later.</p>

					<textarea
						rows={18}
						className="mt-4 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 font-mono text-xs outline-none focus:border-white/20"
						value={text}
						onChange={(e) => setText(e.target.value)}
					/>

					<div className="mt-4 flex items-center justify-between gap-3">
						<button
							type="button"
							onClick={save}
							disabled={busy || !row}
							className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
						>
							{busy ? 'Saving…' : 'Save rules'}
						</button>
						<div className="text-xs text-gray-500">
							{row ? `Updated: ${new Date(row.updated_at).toLocaleString()}` : 'Loading…'}
						</div>
					</div>
				</div>
			</div>
		</div>
	)
}
