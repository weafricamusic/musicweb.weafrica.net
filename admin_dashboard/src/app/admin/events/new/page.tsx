'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'

type Status = 'draft' | 'published' | 'cancelled'

type EventRow = {
	id: string
	status: Status
}

type ApiCreate = { ok: true; data: EventRow } | { ok: false; error: string }

function localInputToIso(value: string): string | null {
	const v = value.trim()
	if (!v) return null
	const d = new Date(v)
	return Number.isNaN(d.getTime()) ? null : d.toISOString()
}

export default function NewEventPage() {
	const router = useRouter()
	const [busy, setBusy] = useState(false)
	const [uploadBusy, setUploadBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [coverPreview, setCoverPreview] = useState<string | null>(null)

	const [title, setTitle] = useState('')
	const [description, setDescription] = useState('')
	const [coverImageUrl, setCoverImageUrl] = useState('')
	const [venueName, setVenueName] = useState('')
	const [venueAddress, setVenueAddress] = useState('')
	const [city, setCity] = useState('')
	const [countryCode, setCountryCode] = useState('')
	const [startsAt, setStartsAt] = useState('')
	const [endsAt, setEndsAt] = useState('')
	const [timezone, setTimezone] = useState('UTC')
	const [status, setStatus] = useState<Status>('draft')

	async function uploadCover(file: File) {
		setError(null)
		setUploadBusy(true)
		try {
			const prevUrl = coverPreview
			if (prevUrl) URL.revokeObjectURL(prevUrl)
			setCoverPreview(URL.createObjectURL(file))

			const form = new FormData()
			form.set('file', file)
			const res = await fetch('/api/admin/events/cover/upload', { method: 'POST', body: form })
			const json = (await res.json().catch(() => null)) as
				| { ok: true; public_url: string | null; signed_url: string | null }
				| { ok?: false; error?: unknown }
				| null

			if (!json) {
				setError(`Upload failed (status ${res.status}).`)
				return
			}
			if (!res.ok || (json as any).ok === false) {
				setError(String((json as any).error ?? `Upload failed (status ${res.status}).`))
				return
			}

			const url = (json as any).public_url || (json as any).signed_url || ''
			setCoverImageUrl(String(url || ''))
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Upload failed.')
		} finally {
			setUploadBusy(false)
		}
	}

	function clearCover() {
		setCoverImageUrl('')
		if (coverPreview) URL.revokeObjectURL(coverPreview)
		setCoverPreview(null)
	}

	async function submit() {
		setError(null)
		const t = title.trim()
		if (!t) {
			setError('Title is required.')
			return
		}

		const startIso = localInputToIso(startsAt)
		const endIso = localInputToIso(endsAt)
		if (!startIso) {
			setError('Valid starts_at date/time is required.')
			return
		}
		if (endsAt && !endIso) {
			setError('Invalid ends_at date/time.')
			return
		}

		if (endIso) {
			const start = new Date(startIso)
			const end = new Date(endIso)
			if (end.getTime() < start.getTime()) {
				setError('Ends at must be after starts at.')
				return
			}
		}

		setBusy(true)
		try {
			const res = await fetch('/api/admin/events', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					title: t,
					description: description.trim() || null,
					cover_image_url: coverImageUrl.trim(),
					venue_name: venueName.trim() || null,
					venue_address: venueAddress.trim() || null,
					city: city.trim() || null,
					country_code: countryCode.trim() || null,
					starts_at: startIso,
					ends_at: endIso,
					timezone: timezone.trim() || 'UTC',
					status,
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

			router.push(`/admin/events/${encodeURIComponent(json.data.id)}`)
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
					<h1 className="text-2xl font-bold">New event</h1>
					<p className="mt-1 text-sm text-gray-400">Create an event before defining ticket types.</p>
				</div>
				<Link href="/admin/events" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
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
							placeholder="WeAfrica Live Showcase"
						/>
					</div>

					<div className="md:col-span-2">
						<label className="text-xs text-gray-400">Description</label>
						<textarea
							rows={4}
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={description}
							onChange={(e) => setDescription(e.target.value)}
							placeholder="Details about the event"
						/>
					</div>

					<div className="md:col-span-2">
						<label className="text-xs text-gray-400">Cover image</label>
						<div className="mt-1 flex items-center gap-3">
							<input
								type="file"
								accept="image/png,image/jpeg,image/webp"
								disabled={busy || uploadBusy}
								onChange={(e) => {
									const f = e.target.files?.[0]
									if (f) void uploadCover(f)
									e.currentTarget.value = ''
								}}
								className="block w-full text-sm text-gray-200 file:mr-4 file:rounded-xl file:border-0 file:bg-white file:px-4 file:py-2 file:text-sm file:font-medium file:text-black hover:file:bg-white/90"
							/>
							{coverImageUrl ? (
								<button
									type="button"
									onClick={clearCover}
									disabled={busy || uploadBusy}
									className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60"
								>
									Remove
								</button>
							) : null}
						</div>
						{uploadBusy ? <div className="mt-2 text-xs text-gray-400">Uploading…</div> : null}
						{coverPreview ? (
							<img src={coverPreview} alt="Cover preview" className="mt-3 h-40 w-full rounded-xl object-cover border border-white/10" />
						) : null}
					</div>

					<div>
						<label className="text-xs text-gray-400">Venue name</label>
						<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={venueName} onChange={(e) => setVenueName(e.target.value)} />
					</div>
					<div>
						<label className="text-xs text-gray-400">Venue address</label>
						<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={venueAddress} onChange={(e) => setVenueAddress(e.target.value)} />
					</div>
					<div>
						<label className="text-xs text-gray-400">City</label>
						<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={city} onChange={(e) => setCity(e.target.value)} />
					</div>
					<div>
						<label className="text-xs text-gray-400">Country code</label>
						<input
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm uppercase outline-none focus:border-white/20"
							value={countryCode}
							onChange={(e) => setCountryCode(e.target.value)}
							placeholder="MW"
						/>
					</div>

					<div>
						<label className="text-xs text-gray-400">Starts at</label>
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

					<div>
						<label className="text-xs text-gray-400">Timezone</label>
						<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={timezone} onChange={(e) => setTimezone(e.target.value)} />
					</div>
					<div>
						<label className="text-xs text-gray-400">Status</label>
						<select
							className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
							value={status}
							onChange={(e) => setStatus(e.target.value as Status)}
						>
							<option value="draft">draft</option>
							<option value="published">published</option>
							<option value="cancelled">cancelled</option>
						</select>
					</div>

					<div className="md:col-span-2 flex items-center justify-end gap-3">
						<button
							type="button"
							onClick={submit}
							disabled={busy || uploadBusy}
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
