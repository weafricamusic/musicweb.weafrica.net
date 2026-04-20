'use client'

import Link from 'next/link'
import { useEffect, useMemo, useState } from 'react'

type Row = {
	id: string
	title: string | null
	body: string
	topic: string
	delivery?: 'tokens' | 'fcm_topic'
	token_topic?: string | null
	target_country_code?: string | null
	target_role?: 'consumers' | 'artists' | 'djs' | null
	target_user_uid?: string | null
	data: Record<string, unknown>
	status: 'draft' | 'sent' | 'failed' | 'archived'
	sent_at: string | null
	error: string | null
	created_by: string | null
	created_at: string
	updated_at: string
}

type ApiList = { ok: true; messages: Row[] } | { error: string }
type ApiRow = { ok: true; message: Row } | { error: string }

function prettyJson(value: unknown): string {
	try {
		return JSON.stringify(value ?? {}, null, 2)
	} catch {
		return '{}'
	}
}

export default function PushNotificationsPage() {
	const [rows, setRows] = useState<Row[] | null>(null)
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)

	const [delivery, setDelivery] = useState<'tokens' | 'fcm_topic'>('tokens')
	const [fcmTopic, setFcmTopic] = useState<'all' | 'consumers' | 'artists' | 'djs'>('all')
	const [tokenTopic, setTokenTopic] = useState<
		'all' | 'likes' | 'comments' | 'new_song' | 'trending' | 'live_battles' | 'marketing' | 'system' | 'collaborations'
	>('all')
	const [targetCountry, setTargetCountry] = useState('')
	const [targetRole, setTargetRole] = useState<'' | 'consumers' | 'artists' | 'djs'>('')
	const [targetUserUid, setTargetUserUid] = useState('')
	const [title, setTitle] = useState('')
	const [body, setBody] = useState('')
	const [dataText, setDataText] = useState('')

	useEffect(() => {
		let cancelled = false
		async function load() {
			setError(null)
			const res = await fetch('/api/admin/notifications/push', { method: 'GET' })
			const json = (await res.json().catch(() => null)) as ApiList | null
			if (cancelled) return
			if (!json) return setError(`Request failed (status ${res.status}).`)
			if (!res.ok || 'error' in json) return setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
			setRows(json.messages)
		}
		void load()
		return () => {
			cancelled = true
		}
	}, [])

	const hasAny = useMemo(() => (rows?.length ?? 0) > 0, [rows])

	async function create(sendNow: boolean) {
		setOk(null)
		setError(null)
		const text = body.trim()
		if (!text) {
			setError('Body is required.')
			return
		}

		let data: Record<string, unknown> = {}
		if (dataText.trim()) {
			try {
				data = JSON.parse(dataText) as Record<string, unknown>
			} catch {
				setError('Data JSON is invalid.')
				return
			}
		}

		setBusy(true)
		try {
			const res = await fetch('/api/admin/notifications/push', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					title: title.trim() || null,
					body: text,
					delivery,
					topic: delivery === 'tokens' ? 'tokens_all' : fcmTopic,
					token_topic: delivery === 'tokens' ? tokenTopic : null,
					target_country_code: delivery === 'tokens' ? targetCountry.trim().toLowerCase() || null : null,
					target_role: delivery === 'tokens' ? (targetRole || null) : null,
					target_user_uid: delivery === 'tokens' ? targetUserUid.trim() || null : null,
					data,
					send_now: sendNow,
				}),
			})
			const json = (await res.json().catch(() => null)) as ApiRow | null
			if (!json) return setError(`Request failed (status ${res.status}).`)
			if (!res.ok || 'error' in json) return setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
			setRows((prev) => [json.message, ...(prev ?? [])])
			setTitle('')
			setBody('')
			setDataText('')
			setTargetUserUid('')
			setOk(sendNow ? 'Sent.' : 'Draft created.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Request failed.')
		} finally {
			setBusy(false)
		}
	}

	async function sendNow(id: string) {
		setOk(null)
		setError(null)
		setBusy(true)
		try {
			const res = await fetch('/api/admin/notifications/push', {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'send_now', id }),
			})
			const json = (await res.json().catch(() => null)) as ApiRow | null
			if (!json) return setError(`Request failed (status ${res.status}).`)
			if (!res.ok || 'error' in json) return setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
			setRows((prev) => (prev ? prev.map((r) => (r.id === id ? json.message : r)) : prev))
			setOk('Sent.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Send failed.')
		} finally {
			setBusy(false)
		}
	}

	async function archive(id: string) {
		setOk(null)
		setError(null)
		setBusy(true)
		try {
			const res = await fetch('/api/admin/notifications/push', {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'archive', id }),
			})
			const json = (await res.json().catch(() => null)) as ApiRow | null
			if (!json) return setError(`Request failed (status ${res.status}).`)
			if (!res.ok || 'error' in json) return setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
			setRows((prev) => (prev ? prev.map((r) => (r.id === id ? json.message : r)) : prev))
			setOk('Archived.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Update failed.')
		} finally {
			setBusy(false)
		}
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Push Notifications</h1>
					<p className="mt-1 text-sm text-gray-400">Create and send FCM pushes to a topic (all/consumers/artists/djs).</p>
				</div>
				<Link href="/admin/notifications" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			{error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}
			{ok ? <div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">{ok}</div> : null}

			<div className="grid gap-6 md:grid-cols-2">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">New push</h2>
					<div className="mt-4 grid gap-3">
						<div>
							<label className="text-xs text-gray-400">Delivery</label>
							<select
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={delivery}
								onChange={(e) => setDelivery(e.target.value as any)}
							>
								<option value="tokens">Device tokens (recommended)</option>
								<option value="fcm_topic">FCM topic</option>
							</select>
							<p className="mt-2 text-xs text-gray-500">Device tokens enables country/role targeting and opt-in topics (e.g. marketing).</p>
						</div>

						{delivery === 'tokens' ? (
							<>
								<div>
									<label className="text-xs text-gray-400">Topic</label>
									<select
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={tokenTopic}
										onChange={(e) => setTokenTopic(e.target.value as any)}
									>
										<option value="all">all</option>
										<option value="likes">likes</option>
										<option value="comments">comments</option>
										<option value="new_song">new_song</option>
										<option value="trending">trending</option>
										<option value="live_battles">live_battles</option>
										<option value="marketing">marketing (opt-in)</option>
										<option value="system">system (opt-out not recommended)</option>
										<option value="collaborations">collaborations (opt-in)</option>
									</select>
									<p className="mt-2 text-xs text-gray-500">Matches consumer app registration: token is eligible if its stored topics contain this value.</p>
								</div>

								<div>
									<label className="text-xs text-gray-400">Country (optional)</label>
									<input
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={targetCountry}
										onChange={(e) => setTargetCountry(e.target.value)}
										placeholder="gh"
									/>
								</div>

								<div>
									<label className="text-xs text-gray-400">Role (optional)</label>
									<select
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={targetRole}
										onChange={(e) => setTargetRole(e.target.value as any)}
									>
										<option value="">Any</option>
										<option value="consumers">consumers</option>
										<option value="artists">artists</option>
										<option value="djs">djs</option>
									</select>
								</div>

								<div>
									<label className="text-xs text-gray-400">User UID (optional)</label>
									<input
										className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										value={targetUserUid}
										onChange={(e) => setTargetUserUid(e.target.value)}
										placeholder="firebase uid (for owner-only pushes)"
									/>
									<p className="mt-2 text-xs text-gray-500">If set, sends only to devices registered for this Firebase UID.</p>
								</div>
							</>
						) : (
							<div>
								<label className="text-xs text-gray-400">FCM topic</label>
								<select
									className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
									value={fcmTopic}
									onChange={(e) => setFcmTopic(e.target.value as any)}
								>
									<option value="all">all</option>
									<option value="consumers">consumers</option>
									<option value="artists">artists</option>
									<option value="djs">djs</option>
								</select>
							</div>
						)}

						<div>
							<label className="text-xs text-gray-400">Title (optional)</label>
							<input
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={title}
								onChange={(e) => setTitle(e.target.value)}
								placeholder="WeAfrica Music"
							/>
						</div>

						<div>
							<label className="text-xs text-gray-400">Body</label>
							<textarea
								rows={5}
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={body}
								onChange={(e) => setBody(e.target.value)}
								placeholder="New drops are live. Open the app to listen."
							/>
						</div>

						<div>
							<label className="text-xs text-gray-400">Data JSON (optional)</label>
							<textarea
								rows={6}
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 font-mono text-xs outline-none focus:border-white/20"
								value={dataText}
								onChange={(e) => setDataText(e.target.value)}
								placeholder={prettyJson({ type: 'like_update', screen: 'song_detail', entity_id: 'song_uuid_123', notification_id: 'auto' })}
							/>
							<p className="mt-2 text-xs text-gray-500">FCM requires string values; objects will be JSON-stringified. If missing, notification_id is auto-set to the message id.</p>
						</div>

						<div className="flex flex-wrap items-center gap-2">
							<button
								type="button"
								onClick={() => create(false)}
								disabled={busy}
								className="inline-flex h-10 items-center rounded-xl border border-white/10 bg-black/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60"
							>
								Create draft
							</button>
							<button
								type="button"
								onClick={() => create(true)}
								disabled={busy}
								className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
							>
								{busy ? 'Working…' : 'Send now'}
							</button>
						</div>
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Recent</h2>
					<div className="mt-4 space-y-3">
						{hasAny ? (
							(rows ?? []).map((r) => (
								<div key={r.id} className="rounded-xl border border-white/10 bg-black/10 p-4">
									<div className="flex items-start justify-between gap-4">
										<div>
											<p className="text-sm font-semibold">{r.title ?? 'Push notification'}</p>
											<p className="mt-1 text-xs text-gray-400">
												Topic: {r.topic}
												{r.delivery ? ` • Delivery: ${r.delivery}` : ''}
												{r.token_topic ? ` • Token topic: ${r.token_topic}` : ''}
												{r.target_country_code ? ` • Country: ${r.target_country_code}` : ''}
												{r.target_role ? ` • Role: ${r.target_role}` : ''}
												{r.target_user_uid ? ` • User: ${r.target_user_uid}` : ''}
												 • Status: {r.status}
												{r.sent_at ? ` • Sent: ${new Date(r.sent_at).toLocaleString()}` : ''}
										</p>
										{r.error ? <p className="mt-2 text-xs text-red-300">Error: {r.error}</p> : null}
									</div>
									<div className="flex items-center gap-2">
										{r.status === 'draft' || r.status === 'failed' ? (
											<button
												type="button"
												onClick={() => sendNow(r.id)}
												disabled={busy}
												className="h-9 rounded-xl bg-white px-3 text-xs font-medium text-black hover:bg-white/90 disabled:opacity-60"
											>
												Send
											</button>
										) : null}
										{r.status !== 'archived' ? (
											<button
												type="button"
												onClick={() => archive(r.id)}
												disabled={busy}
												className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5 disabled:opacity-60"
											>
												Archive
											</button>
										) : null}
									</div>
								</div>
								<p className="mt-3 whitespace-pre-wrap text-sm text-gray-200">{r.body}</p>
								<div className="mt-3 text-xs text-gray-500">Created: {new Date(r.created_at).toLocaleString()}</div>
							</div>
							))
						) : (
							<p className="text-sm text-gray-400">No pushes yet.</p>
						)}
					</div>
				</div>
			</div>

			<div className="flex flex-wrap gap-2">
				<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to Overview
				</Link>
				<Link href="/admin/health" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					System Health
				</Link>
			</div>
		</div>
	)
}
