'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'

type TargetPlan = 'all' | 'free' | 'premium'

type Promotion = {
	id: string
	title: string
	description: string | null
	image_url: string
	target_plan: TargetPlan
	is_active: boolean
	priority: number
	starts_at: string | null
	ends_at: string | null
	created_at: string
	updated_at: string
}

type ApiCreate = { ok: true; data: Promotion } | { ok: false; error: string }

function localInputToIso(value: string): string | null {
	const v = value.trim()
	if (!v) return null
	const d = new Date(v)
	return Number.isNaN(d.getTime()) ? null : d.toISOString()
}

export default function NewPromotionPage() {
	const router = useRouter()
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)

	const [title, setTitle] = useState('')
	const [description, setDescription] = useState('')
	const [imageUrl, setImageUrl] = useState('')
	const [targetPlan, setTargetPlan] = useState<TargetPlan>('all')
	const [isActive, setIsActive] = useState(true)
	const [priority, setPriority] = useState('0')
	const [startsAt, setStartsAt] = useState('')
	const [endsAt, setEndsAt] = useState('')

	async function submit() {
		setError(null)
		const t = title.trim()
		if (!t) {
			setError('Title is required.')
			return
		}

		const p = Number(priority)
		if (!Number.isFinite(p) || Number.isNaN(p)) {
			setError('Priority must be a number.')
			return
		}

		const startIso = localInputToIso(startsAt)
		const endIso = localInputToIso(endsAt)
		if (startsAt && !startIso) {
			setError('Invalid starts_at date/time.')
			return
		}
		if (endsAt && !endIso) {
			setError('Invalid ends_at date/time.')
			return
		}

		setBusy(true)
		try {
			const res = await fetch('/api/admin/promotions', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					title: t,
					description: description.trim() || null,
					image_url: imageUrl.trim(),
					target_plan: targetPlan,
					is_active: isActive,
					priority: Math.trunc(p),
					starts_at: startIso,
					ends_at: endIso,
				}),
			})
			const json = (await res.json().catch(() => null)) as ApiCreate | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || json.ok === false) {
				setError(json.ok === false ? json.error : `Request failed (status ${res.status}).`)
				return
			}

			router.push('/admin/content/promotions')
			router.refresh()
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Create failed.')
		} finally {
			setBusy(false)
		}
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">New promotion</h1>
					<p className="mt-1 text-sm text-gray-400">Creates a row in the promotions table. Consumer apps typically show only active promotions within the schedule window.</p>
				</div>
				<Link href="/admin/content/promotions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			{error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="grid gap-4 md:grid-cols-2">
					<div className="md:col-span-2">
						<label className="text-xs text-gray-400">Title</label>
						<input
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={title}
							onChange={(e) => setTitle(e.target.value)}
							placeholder="New user promo"
						/>
					</div>

					<div className="md:col-span-2">
						<label className="text-xs text-gray-400">Description (optional)</label>
						<textarea
							rows={4}
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={description}
							onChange={(e) => setDescription(e.target.value)}
							placeholder="Shown as body text in the app"
						/>
					</div>

					<div className="md:col-span-2">
						<label className="text-xs text-gray-400">Image URL (optional)</label>
						<input
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={imageUrl}
							onChange={(e) => setImageUrl(e.target.value)}
							placeholder="https://..."
						/>
					</div>

					<div>
						<label className="text-xs text-gray-400">Target plan</label>
						<select
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={targetPlan}
							onChange={(e) => {
								const v = e.target.value
								if (v === 'all' || v === 'free' || v === 'premium') setTargetPlan(v)
							}}
						>
							<option value="all">All</option>
							<option value="free">Free</option>
							<option value="premium">Premium</option>
						</select>
					</div>

					<div className="flex items-end">
						<label className="inline-flex items-center gap-2 text-sm text-gray-200">
							<input
								type="checkbox"
								checked={isActive}
								onChange={(e) => setIsActive(e.target.checked)}
								className="h-4 w-4 rounded border border-white/20 bg-black/20"
							/>
							Active
						</label>
					</div>

					<div>
						<label className="text-xs text-gray-400">Priority</label>
						<input
							inputMode="numeric"
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={priority}
							onChange={(e) => setPriority(e.target.value)}
							placeholder="0"
						/>
					</div>

					<div>
						<label className="text-xs text-gray-400">Starts at (optional)</label>
						<input
							type="datetime-local"
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={startsAt}
							onChange={(e) => setStartsAt(e.target.value)}
						/>
					</div>

					<div>
						<label className="text-xs text-gray-400">Ends at (optional)</label>
						<input
							type="datetime-local"
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={endsAt}
							onChange={(e) => setEndsAt(e.target.value)}
						/>
					</div>

					<div className="md:col-span-2 flex items-center justify-end gap-3">
						<button
							type="button"
							onClick={submit}
							disabled={busy}
							className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
						>
							{busy ? 'Working…' : 'Save'}
						</button>
					</div>
				</div>
			</div>
		</div>
	)
}
