import Link from 'next/link'
import { redirect } from 'next/navigation'

import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { DashboardShell } from '@/components/DashboardShell'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { DjDetailActions } from './DjDetailActions'

export const runtime = 'nodejs'

type DjRow = {
	id: string
	dj_name: string | null
	approved?: boolean | null
	created_at?: string | null
	status?: string | null
	blocked?: boolean | null
	email?: string | null
	phone?: string | null
	region?: string | null
	country?: string | null
	avatar_url?: string | null
	photo_url?: string | null
	profile_image_url?: string | null
}

type DjStatus = 'pending' | 'active' | 'blocked'

function normalizeStatus(dj: DjRow): DjStatus {
	const raw = (dj.status ?? '').toLowerCase().trim()
	if (raw === 'blocked') return 'blocked'
	if (raw === 'active' || raw === 'approved') return 'active'
	if (raw === 'pending') return 'pending'
	if (dj.blocked === true) return 'blocked'
	if (dj.approved === true) return 'active'
	return 'pending'
}

function getAvatarUrl(dj: DjRow): string | null {
	return dj.avatar_url ?? dj.photo_url ?? dj.profile_image_url ?? null
}

function getRegion(dj: DjRow): string {
	const r = (dj.region ?? dj.country ?? 'MW') as string
	return r.toUpperCase() === 'MALAWI' ? 'MW' : r.toUpperCase()
}

export default async function DjDetailPage({ params }: { params: Promise<{ id: string }> }) {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const { id } = await params
	if (!id) redirect('/dashboard/djs')

	const supabase = createSupabaseServerClient()
	const { data: dj, error } = await supabase
		.from('djs')
		.select('*')
		.eq('id', id)
		.maybeSingle<DjRow>()

	if (error || !dj) {
		return (
			<DashboardShell title="DJ">
				<p className="text-sm text-red-600 dark:text-red-400">Error loading DJ: {error?.message ?? 'Not found'}</p>
			</DashboardShell>
		)
	}

	const name = dj.dj_name ?? dj.id
	const status = normalizeStatus(dj)

	return (
		<DashboardShell title="DJ">
			<div className="grid gap-6">
				<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
					<div className="flex items-start justify-between gap-4">
						<div>
							<p className="text-sm text-zinc-600 dark:text-zinc-400">DJ</p>
							<div className="mt-2 flex items-center gap-3">
								{getAvatarUrl(dj) ? (
									<img
										alt=""
										src={getAvatarUrl(dj) ?? undefined}
										className="h-12 w-12 rounded-full border border-black/[.08] object-cover dark:border-white/[.145]"
									/>
								) : (
									<div className="h-12 w-12 rounded-full border border-black/[.08] bg-black/[.04] dark:border-white/[.145] dark:bg-white/[.06]" />
								)}
								<div>
									<h2 className="text-lg font-semibold">{name}</h2>
									<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">ID: {dj.id}</p>
								</div>
							</div>
						</div>
						<Link
							href="/dashboard/djs"
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
						>
							Back
						</Link>
					</div>

					<div className="mt-4 grid gap-3 text-sm md:grid-cols-2">
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Status</p>
							<p className="mt-1">{status === 'active' ? 'Active' : status === 'blocked' ? 'Blocked' : 'Pending'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Region</p>
							<p className="mt-1">{getRegion(dj)}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Email</p>
							<p className="mt-1">{dj.email ?? '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Phone</p>
							<p className="mt-1">{dj.phone ?? '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Joined</p>
							<p className="mt-1">{dj.created_at ? new Date(dj.created_at).toLocaleString() : '—'}</p>
						</div>
					</div>
				</div>

				<div className="rounded-2xl border border-black/[.08] bg-white p-2 dark:border-white/[.145] dark:bg-black">
					<div className="flex flex-wrap gap-2 p-2 text-sm">
						<span className="rounded-xl bg-black/[.04] px-3 py-2 text-zinc-700 dark:bg-white/[.06] dark:text-zinc-200">
							Profile
						</span>
						<span className="rounded-xl px-3 py-2 text-zinc-600 dark:text-zinc-400">Content (soon)</span>
						<span className="rounded-xl px-3 py-2 text-zinc-600 dark:text-zinc-400">Performance (soon)</span>
						<span className="rounded-xl px-3 py-2 text-zinc-600 dark:text-zinc-400">Permissions (soon)</span>
						<span className="rounded-xl px-3 py-2 text-zinc-600 dark:text-zinc-400">Actions</span>
					</div>
				</div>

				<DjDetailActions id={dj.id} name={name} initialStatus={status} />
			</div>
		</DashboardShell>
	)
}
