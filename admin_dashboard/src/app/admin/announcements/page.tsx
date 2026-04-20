'use client'

import { useState } from 'react'

type ApiCreate =
	| { ok: true; announcement: { id: string } }
	| { ok: false; error: string }

type TargetsState = {
	all: boolean
	artists: boolean
	djs: boolean
	consumers: boolean
}

function buildTargetString(targets: TargetsState): string {
	if (targets.all) return 'all'
	const parts: string[] = []
	if (targets.artists) parts.push('artists')
	if (targets.djs) parts.push('djs')
	if (targets.consumers) parts.push('consumers')
	return parts.join(',')
}

export default function AdminAnnouncementsPage() {
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [notice, setNotice] = useState<string | null>(null)

	const [title, setTitle] = useState('')
	const [message, setMessage] = useState('')
	const [targets, setTargets] = useState<TargetsState>({ all: true, artists: false, djs: false, consumers: false })
	const [actionLink, setActionLink] = useState('')
	const [active, setActive] = useState(true)

	function toggleAll(next: boolean) {
		setTargets({ all: next, artists: false, djs: false, consumers: false })
	}

	function toggleTarget(key: Exclude<keyof TargetsState, 'all'>, next: boolean) {
		setTargets((prev) => ({ ...prev, all: next ? false : prev.all, [key]: next }))
	}

	async function publish() {
		setError(null)
		setNotice(null)

		const t = title.trim()
		const m = message.trim()
		if (!t) {
			setError('Title is required.')
			return
		}
		if (!m) {
			setError('Message is required.')
			return
		}

		const target = buildTargetString(targets)
		if (!target) {
			setError('Select at least one target user group.')
			return
		}

		setBusy(true)
		try {
			const res = await fetch('/api/admin/announcements', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					title: t,
					message: m,
					target,
					action_link: actionLink.trim() || null,
					is_active: Boolean(active),
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

			setNotice('Announcement published.')
			setTitle('')
			setMessage('')
			setTargets({ all: true, artists: false, djs: false, consumers: false })
			setActionLink('')
			setActive(true)
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Publish failed.')
		} finally {
			setBusy(false)
		}
	}

	return (
		<div className="space-y-6">
			<div>
				<h1 className="text-2xl font-bold">Create Announcement</h1>
			</div>

			{error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}
			{notice ? <div className="rounded-2xl border border-white/10 bg-white/5 p-4 text-sm text-gray-200">{notice}</div> : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="grid gap-4">
					<div>
						<label className="text-xs text-gray-400">Title</label>
						<input
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={title}
							onChange={(e) => setTitle(e.target.value)}
							placeholder="🔥 Malawi Battle Night"
							disabled={busy}
						/>
					</div>

					<div>
						<label className="text-xs text-gray-400">Message</label>
						<textarea
							rows={4}
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={message}
							onChange={(e) => setMessage(e.target.value)}
							placeholder="Top artists battle tonight at 20:00"
							disabled={busy}
						/>
					</div>

					<div>
						<div className="text-xs text-gray-400">Target Users</div>
						<div className="mt-2 flex flex-wrap gap-4 text-sm">
							<label className="inline-flex items-center gap-2">
								<input
									type="checkbox"
									checked={targets.all}
									onChange={(e) => toggleAll(e.target.checked)}
									disabled={busy}
									className="h-4 w-4"
								/>
								All
							</label>
							<label className="inline-flex items-center gap-2">
								<input
									type="checkbox"
									checked={targets.artists}
									onChange={(e) => toggleTarget('artists', e.target.checked)}
									disabled={busy}
									className="h-4 w-4"
								/>
								Artists
							</label>
							<label className="inline-flex items-center gap-2">
								<input
									type="checkbox"
									checked={targets.djs}
									onChange={(e) => toggleTarget('djs', e.target.checked)}
									disabled={busy}
									className="h-4 w-4"
								/>
								DJs
							</label>
							<label className="inline-flex items-center gap-2">
								<input
									type="checkbox"
									checked={targets.consumers}
									onChange={(e) => toggleTarget('consumers', e.target.checked)}
									disabled={busy}
									className="h-4 w-4"
								/>
								Consumers
							</label>
						</div>
					</div>

					<div>
						<label className="text-xs text-gray-400">Action Link (optional)</label>
						<input
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={actionLink}
							onChange={(e) => setActionLink(e.target.value)}
							placeholder="watch-battle"
							disabled={busy}
						/>
					</div>

					<div>
						<div className="text-xs text-gray-400">Active</div>
						<label className="mt-2 inline-flex items-center gap-2 text-sm">
							<input
								type="checkbox"
								checked={active}
								onChange={(e) => setActive(e.target.checked)}
								disabled={busy}
								className="h-4 w-4"
							/>
							Yes
						</label>
					</div>

					<div>
						<button
							type="button"
							onClick={() => void publish()}
							disabled={busy}
							className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
						>
							{busy ? 'Publishing…' : 'Publish Announcement'}
						</button>
					</div>
				</div>
			</div>
		</div>
	)
}
