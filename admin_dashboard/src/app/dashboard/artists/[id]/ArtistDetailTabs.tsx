'use client'

import { useMemo, useState } from 'react'
import { ArtistDetailActions } from './ArtistDetailActions'

type ContentRow = Record<string, unknown> & {
	id?: string | number
	created_at?: string | null
	title?: string | null
	name?: string | null
	status?: string | null
}

export type ArtistDetailModel = Record<string, unknown> & {
	id: string
	created_at?: string | null
	name?: string | null
	email?: string | null
	phone?: string | null
	stage_name?: string | null
	full_name?: string | null
	bio?: string | null
	status?: string | null
	approved?: boolean | null
	blocked?: boolean | null
	verified?: boolean | null
	can_upload_songs?: boolean | null
	can_upload_videos?: boolean | null
	can_go_live?: boolean | null
}

type TabId = 'profile' | 'content' | 'performance' | 'earnings' | 'permissions' | 'actions'

function formatDate(value: unknown): string {
	if (typeof value !== 'string' || !value) return '—'
	const d = new Date(value)
	return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString()
}

function getTitle(r: ContentRow): string {
	return String(r.title ?? r.name ?? r.id ?? '—')
}

function getStatus(r: ContentRow): string {
	const s = String(r.status ?? '').trim()
	return s || '—'
}

function badge(text: string, tone: 'zinc' | 'emerald' | 'red' | 'sky' = 'zinc') {
	const cls =
		tone === 'emerald'
			? 'bg-emerald-50 text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300'
			: tone === 'red'
				? 'bg-red-50 text-red-700 dark:bg-red-900/20 dark:text-red-300'
				: tone === 'sky'
					? 'bg-sky-50 text-sky-700 dark:bg-sky-900/20 dark:text-sky-300'
					: 'bg-black/[.04] text-zinc-700 dark:bg-white/[.06] dark:text-zinc-200'
	return <span className={`rounded-full px-2 py-1 text-xs ${cls}`}>{text}</span>
}

export function ArtistDetailTabs(props: { artist: ArtistDetailModel; songs: ContentRow[]; videos: ContentRow[] }) {
	const { artist, songs, videos } = props
	const [tab, setTab] = useState<TabId>('profile')

	const canEditPermissions = useMemo(() => {
		return (
			typeof artist.can_upload_songs === 'boolean' ||
			typeof artist.can_upload_videos === 'boolean' ||
			typeof artist.can_go_live === 'boolean'
		)
	}, [artist.can_upload_songs, artist.can_upload_videos, artist.can_go_live])

	return (
		<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
			<div className="flex flex-wrap gap-2">
				{([
					['profile', 'Profile'],
					['content', 'Content'],
					['performance', 'Performance'],
					['earnings', 'Earnings'],
					['permissions', 'Permissions'],
					['actions', 'Actions'],
				] as Array<[TabId, string]>).map(([id, label]) => (
					<button
						key={id}
						type="button"
						onClick={() => setTab(id)}
						className={`h-9 rounded-xl border px-3 text-sm dark:border-white/[.145] ${
							tab === id
								? 'border-black/30 bg-black/[.04] dark:border-white/30 dark:bg-white/[.06]'
								: 'border-black/[.08] bg-transparent'
						}`}
					>
						{label}
					</button>
				))}
			</div>

			{tab === 'profile' ? (
				<div className="mt-6 grid gap-3 text-sm md:grid-cols-2">
					<div>
						<p className="text-zinc-600 dark:text-zinc-400">Full name</p>
						<p className="mt-1">{String(artist.full_name ?? '—')}</p>
					</div>
					<div>
						<p className="text-zinc-600 dark:text-zinc-400">Stage name</p>
						<p className="mt-1">{String(artist.stage_name ?? artist.name ?? '—')}</p>
					</div>
					<div>
						<p className="text-zinc-600 dark:text-zinc-400">Email</p>
						<p className="mt-1">{String(artist.email ?? '—')}</p>
					</div>
					<div>
						<p className="text-zinc-600 dark:text-zinc-400">Phone</p>
						<p className="mt-1">{String(artist.phone ?? '—')}</p>
					</div>
					<div className="md:col-span-2">
						<p className="text-zinc-600 dark:text-zinc-400">Bio</p>
						<p className="mt-1 whitespace-pre-wrap">{String((artist.bio as any) ?? '—')}</p>
					</div>
				</div>
			) : null}

			{tab === 'content' ? (
				<div className="mt-6 grid gap-6 lg:grid-cols-2">
					<div>
						<div className="flex items-center justify-between">
							<h3 className="text-base font-semibold">Songs</h3>
							{badge(String(songs.length), 'zinc')}
						</div>
						<div className="mt-3 overflow-auto">
							<table className="w-full min-w-[420px] border-separate border-spacing-0 text-left text-sm">
								<thead>
									<tr className="text-zinc-600 dark:text-zinc-400">
										<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Title</th>
										<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Status</th>
										<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Created</th>
									</tr>
								</thead>
								<tbody>
									{songs.length ? (
										songs.map((s) => (
											<tr key={String(s.id ?? getTitle(s))}>
												<td className="border-b border-black/[.08] py-3 pr-4 dark:border-white/[.145]">{getTitle(s)}</td>
												<td className="border-b border-black/[.08] py-3 pr-4 dark:border-white/[.145]">{getStatus(s)}</td>
												<td className="border-b border-black/[.08] py-3 pr-4 text-xs text-zinc-600 dark:border-white/[.145] dark:text-zinc-400">
													{formatDate(s.created_at)}
												</td>
											</tr>
										))
									) : (
										<tr>
											<td colSpan={3} className="py-6 text-sm text-zinc-600 dark:text-zinc-400">
												No songs found.
											</td>
										</tr>
									)}
								</tbody>
							</table>
						</div>
					</div>

					<div>
						<div className="flex items-center justify-between">
							<h3 className="text-base font-semibold">Videos</h3>
							{badge(String(videos.length), 'zinc')}
						</div>
						<div className="mt-3 overflow-auto">
							<table className="w-full min-w-[420px] border-separate border-spacing-0 text-left text-sm">
								<thead>
									<tr className="text-zinc-600 dark:text-zinc-400">
										<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Title</th>
										<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Status</th>
										<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Created</th>
									</tr>
								</thead>
								<tbody>
									{videos.length ? (
										videos.map((v) => (
											<tr key={String(v.id ?? getTitle(v))}>
												<td className="border-b border-black/[.08] py-3 pr-4 dark:border-white/[.145]">{getTitle(v)}</td>
												<td className="border-b border-black/[.08] py-3 pr-4 dark:border-white/[.145]">{getStatus(v)}</td>
												<td className="border-b border-black/[.08] py-3 pr-4 text-xs text-zinc-600 dark:border-white/[.145] dark:text-zinc-400">
													{formatDate(v.created_at)}
												</td>
											</tr>
										))
									) : (
										<tr>
											<td colSpan={3} className="py-6 text-sm text-zinc-600 dark:text-zinc-400">
												No videos found.
											</td>
										</tr>
									)}
								</tbody>
							</table>
						</div>
					</div>
				</div>
			) : null}

			{tab === 'performance' ? (
				<div className="mt-6 grid gap-3 text-sm md:grid-cols-3">
					<div className="rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
						<p className="text-zinc-600 dark:text-zinc-400">Total streams</p>
						<p className="mt-1 text-lg font-semibold">—</p>
					</div>
					<div className="rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
						<p className="text-zinc-600 dark:text-zinc-400">Likes</p>
						<p className="mt-1 text-lg font-semibold">—</p>
					</div>
					<div className="rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
						<p className="text-zinc-600 dark:text-zinc-400">Followers</p>
						<p className="mt-1 text-lg font-semibold">—</p>
					</div>
					<p className="md:col-span-3 text-xs text-zinc-600 dark:text-zinc-400">Analytics metrics are not enabled for this workspace.</p>
				</div>
			) : null}

			{tab === 'earnings' ? (
				<div className="mt-6">
					<p className="text-sm text-zinc-600 dark:text-zinc-400">
						Earnings are read-only in phase 1. Hook this up when the wallet/coins tables are available.
					</p>
				</div>
			) : null}

			{tab === 'permissions' ? (
				<PermissionsPanel artist={artist} canEdit={canEditPermissions} />
			) : null}

			{tab === 'actions' ? (
				<div className="mt-6">
					<ArtistDetailActions
						id={artist.id}
						name={String(artist.name ?? artist.stage_name ?? artist.id)}
						status={String(artist.status ?? '')}
						verified={artist.verified === true}
					/>
				</div>
			) : null}
		</div>
	)
}

function PermissionsPanel(props: { artist: ArtistDetailModel; canEdit: boolean }) {
	const { artist, canEdit } = props
	const [saving, setSaving] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)

	async function patch(body: unknown) {
		const res = await fetch(`/api/admin/artists/${encodeURIComponent(artist.id)}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body),
		})
		if (res.ok) return
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Request failed')
	}

	async function toggle(key: 'can_upload_songs' | 'can_upload_videos' | 'can_go_live', value: boolean) {
		setError(null)
		setSaving(key)
		try {
			await patch({ action: 'set_permissions', [key]: value })
			// soft refresh
			window.location.reload()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update permissions')
		} finally {
			setSaving(null)
		}
	}

	return (
		<div className="mt-6">
			<h3 className="text-base font-semibold">Permissions</h3>
			<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Control what this artist can do.</p>
			{!canEdit ? (
				<p className="mt-3 text-xs text-zinc-600 dark:text-zinc-400">
					Permissions columns not found on this artist record (expected: can_upload_songs, can_upload_videos, can_go_live).
				</p>
			) : null}
			{error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}

			<div className="mt-4 grid gap-3 text-sm md:grid-cols-3">
				<Toggle
					label="Upload songs"
					value={artist.can_upload_songs === true}
					disabled={typeof artist.can_upload_songs !== 'boolean' || saving !== null}
					onChange={(v) => toggle('can_upload_songs', v)}
				/>
				<Toggle
					label="Upload videos"
					value={artist.can_upload_videos === true}
					disabled={typeof artist.can_upload_videos !== 'boolean' || saving !== null}
					onChange={(v) => toggle('can_upload_videos', v)}
				/>
				<Toggle
					label="Go live"
					value={artist.can_go_live === true}
					disabled={typeof artist.can_go_live !== 'boolean' || saving !== null}
					onChange={(v) => toggle('can_go_live', v)}
				/>
			</div>
		</div>
	)
}

function Toggle(props: { label: string; value: boolean; disabled: boolean; onChange: (next: boolean) => void }) {
	const { label, value, disabled, onChange } = props
	return (
		<div className="rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
			<div className="flex items-center justify-between gap-3">
				<div>
					<p className="font-medium">{label}</p>
					<p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">{value ? 'Enabled' : 'Disabled'}</p>
				</div>
				<button
					type="button"
					disabled={disabled}
					onClick={() => onChange(!value)}
					className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
				>
					{value ? 'Disable' : 'Enable'}
				</button>
			</div>
		</div>
	)
}
