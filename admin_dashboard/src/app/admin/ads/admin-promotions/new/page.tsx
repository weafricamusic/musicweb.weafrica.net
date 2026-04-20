'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

const PROMOTION_TYPES = [
	{ value: 'artist', label: 'Artist' },
	{ value: 'dj', label: 'DJ' },
	{ value: 'battle', label: 'Battle' },
	{ value: 'event', label: 'Event' },
	{ value: 'ride', label: 'WeAfrica Ride' },
]

const SURFACES = [
	{ value: 'home_banner', label: 'Home Banner' },
	{ value: 'discover', label: 'Discover' },
	{ value: 'feed', label: 'Feed' },
	{ value: 'live_battle', label: 'Live Battle' },
	{ value: 'events', label: 'Events Section' },
]

const AFRICAN_COUNTRIES = [
	{ code: 'MW', name: 'Malawi' },
	{ code: 'NG', name: 'Nigeria' },
	{ code: 'ZA', name: 'South Africa' },
	{ code: 'KE', name: 'Kenya' },
	{ code: 'GH', name: 'Ghana' },
	{ code: 'TZ', name: 'Tanzania' },
	{ code: 'UG', name: 'Uganda' },
	{ code: 'ZW', name: 'Zimbabwe' },
	{ code: 'ZM', name: 'Zambia' },
	{ code: 'ET', name: 'Ethiopia' },
]

export default function CreatePromotionPage() {
	const router = useRouter()
	const [saving, setSaving] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [bannerUploading, setBannerUploading] = useState(false)
	const [bannerUrl, setBannerUrl] = useState('')

	const [form, setForm] = useState({
		promotion_type: 'artist',
		country: 'MW',
		target_id: '',
		title: '',
		description: '',
		surface: 'home_banner',
		start_date: '',
		end_date: '',
		status: 'scheduled',
	})

	function set(field: keyof typeof form, value: string) {
		setForm((prev) => ({ ...prev, [field]: value }))
	}

	async function handleBannerUpload(e: React.ChangeEvent<HTMLInputElement>) {
		const file = e.target.files?.[0]
		if (!file) return
		setBannerUploading(true)
		try {
			const body = new FormData()
			body.append('file', file)
			body.append('bucket', 'promotions')
			body.append('path', `banners/${Date.now()}-${file.name}`)
			const res = await fetch('/api/uploads/storage', { method: 'POST', body })
			if (!res.ok) throw new Error(await res.text())
			const json = await res.json()
			setBannerUrl(json.url ?? json.public_url ?? json.path ?? '')
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Banner upload failed')
		} finally {
			setBannerUploading(false)
		}
	}

	async function handleSubmit(e: React.FormEvent) {
		e.preventDefault()
		setError(null)
		setSaving(true)
		try {
			const payload = {
				...form,
				banner_url: bannerUrl || undefined,
				source_type: 'admin',
				is_active: form.status === 'active',
				// keep legacy field aliases in sync
				starts_at: form.start_date || undefined,
				ends_at: form.end_date || undefined,
			}
			const res = await fetch('/api/admin/promotions', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(payload),
			})
			if (!res.ok) {
				const data = await res.json().catch(() => ({}))
				throw new Error(data?.error ?? `HTTP ${res.status}`)
			}
			router.push('/admin/ads/admin-promotions?ok=1')
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to create promotion')
		} finally {
			setSaving(false)
		}
	}

	return (
		<div className="mx-auto max-w-2xl space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-lg font-semibold text-white">Create Promotion</h1>
				<p className="mt-1 text-sm text-gray-400">
					Define an admin-controlled promotion for artists, DJs, battles, events, or WeAfrica Ride.
				</p>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					{error}
				</div>
			) : null}

			<form onSubmit={handleSubmit} className="space-y-5">
				{/* Promotion Type */}
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5 space-y-4">
					<h2 className="text-sm font-semibold text-white">Promotion Type</h2>
					<div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
						{PROMOTION_TYPES.map((t) => (
							<button
								key={t.value}
								type="button"
								onClick={() => set('promotion_type', t.value)}
								className={`rounded-xl border px-3 py-2 text-sm transition ${
									form.promotion_type === t.value
										? 'border-white bg-white text-black'
										: 'border-white/10 bg-white/5 text-gray-200 hover:bg-white/10'
								}`}
							>
								{t.label}
							</button>
						))}
					</div>
				</div>

				{/* Country + Target */}
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5 space-y-4">
					<h2 className="text-sm font-semibold text-white">Country & Target</h2>
					<div className="grid gap-4 sm:grid-cols-2">
						<div className="space-y-1">
							<label className="text-xs text-gray-400">Country</label>
							<select
								value={form.country}
								onChange={(e) => set('country', e.target.value)}
								className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm text-white"
							>
								{AFRICAN_COUNTRIES.map((c) => (
									<option key={c.code} value={c.code}>
										{c.name}
									</option>
								))}
							</select>
						</div>
						<div className="space-y-1">
							<label className="text-xs text-gray-400">
								Select Content (artist ID / DJ ID / battle ID / event ID)
							</label>
							<input
								type="text"
								value={form.target_id}
								onChange={(e) => set('target_id', e.target.value)}
								placeholder="e.g. artist_uuid or slug"
								className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm text-white placeholder-gray-600"
							/>
						</div>
					</div>
				</div>

				{/* Title + Description */}
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5 space-y-4">
					<h2 className="text-sm font-semibold text-white">Copy</h2>
					<div className="space-y-1">
						<label className="text-xs text-gray-400">Promotion Title</label>
						<input
							type="text"
							required
							value={form.title}
							onChange={(e) => set('title', e.target.value)}
							placeholder="e.g. Trending Artist of the Week"
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm text-white placeholder-gray-600"
						/>
					</div>
					<div className="space-y-1">
						<label className="text-xs text-gray-400">Promotion Description</label>
						<textarea
							rows={3}
							value={form.description}
							onChange={(e) => set('description', e.target.value)}
							placeholder="Short description shown in banner or discover carousel"
							className="w-full rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder-gray-600 resize-none"
						/>
					</div>
				</div>

				{/* Banner */}
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5 space-y-4">
					<h2 className="text-sm font-semibold text-white">Banner Image</h2>
					<div className="space-y-3">
						<label className="block w-full cursor-pointer rounded-xl border border-dashed border-white/20 bg-black/20 px-4 py-6 text-center hover:border-white/40">
							<input
								type="file"
								accept="image/*"
								className="hidden"
								onChange={handleBannerUpload}
								disabled={bannerUploading}
							/>
							{bannerUploading ? (
								<span className="text-sm text-gray-400">Uploading…</span>
							) : bannerUrl ? (
								<span className="text-sm text-emerald-300 break-all">{bannerUrl}</span>
							) : (
								<span className="text-sm text-gray-400">Click to upload banner image (PNG, JPG, WebP)</span>
							)}
						</label>
						<p className="text-xs text-gray-500">Or paste a URL directly:</p>
						<input
							type="url"
							value={bannerUrl}
							onChange={(e) => setBannerUrl(e.target.value)}
							placeholder="https://..."
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm text-white placeholder-gray-600"
						/>
					</div>
				</div>

				{/* Surface */}
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5 space-y-4">
					<h2 className="text-sm font-semibold text-white">Promotion Surface</h2>
					<div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
						{SURFACES.map((s) => (
							<button
								key={s.value}
								type="button"
								onClick={() => set('surface', s.value)}
								className={`rounded-xl border px-3 py-2 text-xs transition ${
									form.surface === s.value
										? 'border-white bg-white text-black'
										: 'border-white/10 bg-white/5 text-gray-200 hover:bg-white/10'
								}`}
							>
								{s.label}
							</button>
						))}
					</div>
				</div>

				{/* Schedule */}
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5 space-y-4">
					<h2 className="text-sm font-semibold text-white">Schedule</h2>
					<div className="grid gap-4 sm:grid-cols-2">
						<div className="space-y-1">
							<label className="text-xs text-gray-400">Start Date</label>
							<input
								type="datetime-local"
								value={form.start_date}
								onChange={(e) => set('start_date', e.target.value)}
								className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm text-white"
							/>
						</div>
						<div className="space-y-1">
							<label className="text-xs text-gray-400">End Date</label>
							<input
								type="datetime-local"
								value={form.end_date}
								onChange={(e) => set('end_date', e.target.value)}
								className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm text-white"
							/>
						</div>
					</div>
					<div className="space-y-1">
						<label className="text-xs text-gray-400">Initial Status</label>
						<select
							value={form.status}
							onChange={(e) => set('status', e.target.value)}
							className="h-10 w-48 rounded-xl border border-white/10 bg-black/30 px-3 text-sm text-white"
						>
							<option value="draft">Draft</option>
							<option value="scheduled">Scheduled</option>
							<option value="active">Active (live now)</option>
						</select>
					</div>
				</div>

				{/* Actions */}
				<div className="flex gap-3">
					<button
						type="button"
						onClick={() => router.back()}
						className="h-10 rounded-xl border border-white/10 px-5 text-sm hover:bg-white/5"
					>
						Cancel
					</button>
					<button
						type="submit"
						disabled={saving || bannerUploading}
						className="h-10 rounded-xl bg-white px-6 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-50"
					>
						{saving ? 'Saving…' : 'Create Promotion'}
					</button>
				</div>
			</form>
		</div>
	)
}
