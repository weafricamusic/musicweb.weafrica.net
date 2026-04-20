import Link from 'next/link'
import { redirect } from 'next/navigation'

import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { DashboardShell } from '@/components/DashboardShell'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { UserDetailActions } from './UserDetailActions'

export const runtime = 'nodejs'

export default async function UserDetailPage({ params }: { params: Promise<{ uid: string }> }) {
	const sessionUser = await verifyFirebaseSessionCookie()
	if (!sessionUser) redirect('/auth/login')

	const { uid } = await params
	if (!uid) redirect('/dashboard/users')

	let row:
		| {
			uid: string
			email: string | null
			displayName: string | null
			phone: string | null
			avatarUrl: string | null
			disabled: boolean
			region: string
			createdAt: string | null
			lastSignInTime: string | null
			adminActivity: Array<{ created_at?: string | null; action?: string | null; meta?: any }>
		 }
		| null = null
	let loadError: string | null = null

	try {
		const u = await getFirebaseAdminAuth().getUser(uid)
		const photoURL = (u.photoURL ?? null) as string | null
		const supabase = createSupabaseServerClient()
		let profile: any | null = null
		try {
			const { data } = await supabase
				.from('users')
				.select('*')
				.or(`firebase_uid.eq.${uid},uid.eq.${uid},id.eq.${uid}`)
				.maybeSingle()
			profile = data ?? null
		} catch {
			profile = null
		}

		let adminActivity: Array<{ created_at?: string | null; action?: string | null; meta?: any }> = []
		try {
			const { data, error } = await supabase
				.from('admin_logs')
				.select('created_at,action,meta')
				.eq('target_type', 'user')
				.eq('target_id', uid)
				.order('created_at', { ascending: false })
				.limit(5)
			if (error) throw error
			adminActivity = (data ?? []) as any
		} catch {
			try {
				const { data } = await supabase
					.from('admin_activity')
					.select('created_at,action,meta')
					.eq('entity', 'users')
					.eq('entity_id', uid)
					.order('created_at', { ascending: false })
					.limit(5)
				adminActivity = (data ?? []) as any
			} catch {
				adminActivity = []
			}
		}

		const avatarUrl =
			(profile?.avatar_url ?? profile?.photo_url ?? profile?.profile_image_url ?? photoURL ?? null) as string | null
		const phone = (profile?.phone ?? u.phoneNumber ?? null) as string | null
		const regionRaw = (profile?.region ?? profile?.country ?? 'MW') as string
		const region = regionRaw.toUpperCase() === 'MALAWI' ? 'MW' : regionRaw.toUpperCase()

		row = {
			uid: u.uid,
			email: u.email ?? null,
			displayName: u.displayName ?? null,
			phone,
			avatarUrl,
			disabled: u.disabled,
			region,
			createdAt: u.metadata.creationTime ?? null,
			lastSignInTime: u.metadata.lastSignInTime ?? null,
			adminActivity,
		}
	} catch (e) {
		loadError = e instanceof Error ? e.message : 'Failed to load user'
	}

	if (loadError || !row) {
		return (
			<DashboardShell title="User">
				<p className="text-sm text-red-600 dark:text-red-400">Error loading user: {loadError ?? 'Unknown error'}</p>
			</DashboardShell>
		)
	}

	return (
		<DashboardShell title="User">
			<div className="grid gap-6">
				<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
					<div className="flex items-start justify-between gap-4">
						<div>
							<p className="text-sm text-zinc-600 dark:text-zinc-400">User</p>
							<div className="mt-1 flex items-center gap-3">
								{row.avatarUrl ? (
									<img
										alt=""
										src={row.avatarUrl ?? undefined}
										className="h-10 w-10 rounded-full border border-black/[.08] object-cover dark:border-white/[.145]"
									/>
								) : null}
								<h2 className="text-lg font-semibold">{row.displayName ?? row.email ?? row.uid}</h2>
								{row.disabled ? (
									<span className="rounded-full bg-red-50 px-2 py-1 text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300">
										Blocked
									</span>
								) : (
									<span className="rounded-full bg-emerald-50 px-2 py-1 text-xs text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300">
										Active
									</span>
								)}
							</div>
							<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">UID: {row.uid}</p>
						</div>
						<Link
							href="/dashboard/users"
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
						>
							Back
						</Link>
					</div>

					<div className="mt-6 grid gap-6">
						<div>
							<h3 className="text-base font-semibold">Profile</h3>
							<div className="mt-3 grid gap-3 text-sm md:grid-cols-2">
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Email</p>
							<p className="mt-1">{row.email ?? '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Phone</p>
							<p className="mt-1">{row.phone ?? '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Region</p>
							<p className="mt-1">{row.region}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Created</p>
							<p className="mt-1">{row.createdAt ?? '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Last sign-in</p>
							<p className="mt-1">{row.lastSignInTime ?? '—'}</p>
						</div>
						</div>
					</div>

						<div>
							<h3 className="text-base font-semibold">Activity</h3>
							<div className="mt-3 grid gap-3 text-sm md:grid-cols-3">
								<div className="rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
									<p className="text-zinc-600 dark:text-zinc-400">Liked songs</p>
									<p className="mt-1 text-lg font-semibold">—</p>
								</div>
								<div className="rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
									<p className="text-zinc-600 dark:text-zinc-400">Followed artists</p>
									<p className="mt-1 text-lg font-semibold">—</p>
								</div>
								<div className="rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
									<p className="text-zinc-600 dark:text-zinc-400">Comments</p>
									<p className="mt-1 text-lg font-semibold">—</p>
								</div>
								<p className="md:col-span-3 text-xs text-zinc-600 dark:text-zinc-400">Analytics metrics are not enabled for this workspace.</p>
							</div>
						</div>

						<div>
							<h3 className="text-base font-semibold">Restrictions</h3>
							<div className="mt-3 grid gap-3 text-sm md:grid-cols-2">
								<div>
									<p className="text-zinc-600 dark:text-zinc-400">Blocked</p>
									<p className="mt-1">{row.disabled ? 'Yes' : 'No'}</p>
								</div>
								<div>
									<p className="text-zinc-600 dark:text-zinc-400">Recent actions</p>
									<p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">
										{row.adminActivity.length ? '' : 'No recent actions found.'}
									</p>
								</div>
								{row.adminActivity.length ? (
									<div className="md:col-span-2 mt-2 overflow-auto">
										<table className="w-full min-w-[520px] border-separate border-spacing-0 text-left text-sm">
											<thead>
												<tr className="text-zinc-600 dark:text-zinc-400">
													<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">When</th>
													<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Action</th>
													<th className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]">Meta</th>
												</tr>
											</thead>
											<tbody>
												{row.adminActivity.map((a, idx) => (
													<tr key={idx}>
														<td className="border-b border-black/[.08] py-3 pr-4 text-xs text-zinc-600 dark:border-white/[.145] dark:text-zinc-400">
														{a.created_at ? new Date(String(a.created_at)).toLocaleString() : '—'}
													</td>
													<td className="border-b border-black/[.08] py-3 pr-4 dark:border-white/[.145]">
														{String(a.action ?? '—')}
													</td>
													<td className="border-b border-black/[.08] py-3 pr-4 text-xs text-zinc-600 dark:border-white/[.145] dark:text-zinc-400">
														{a.meta ? JSON.stringify(a.meta) : '—'}
													</td>
												</tr>
												))}
											</tbody>
										</table>
									</div>
								) : null}
							</div>
						</div>
					</div>
				</div>

				<UserDetailActions uid={row.uid} email={row.email} initialDisabled={row.disabled} />
			</div>
		</DashboardShell>
	)
}
