import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type Row = {
	user_id: string
	role: string
	reports_count: number
	last_action: string | null
	last_action_at: string | null
	status: string
}

type Person = { id: string; name?: string | null; stage_name?: string | null; display_name?: string | null }

function displayName(p: Person): string {
	return (p.stage_name ?? p.display_name ?? p.name ?? p.id) as string
}

export default async function ReportedUsersPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for moderation users" />
	let rows: Row[] = []
	let errorMsg: string | null = null

	try {
		const { data, error } = await supabase.rpc('moderation_reported_users_overview')
		if (error) errorMsg = error.message
		rows = ((data ?? []) as any[]).map((r) => ({
			user_id: String(r.user_id),
			role: String(r.role ?? 'user'),
			reports_count: Number(r.reports_count ?? 0),
			last_action: r.last_action ? String(r.last_action) : null,
			last_action_at: r.last_action_at ? String(r.last_action_at) : null,
			status: String(r.status ?? 'active'),
		}))
	} catch {
		errorMsg = 'Missing moderation RPC. Apply the moderation migration.'
		rows = []
	}

	const artistIds = rows.filter((r) => r.role === 'artist').map((r) => r.user_id)
	const djIds = rows.filter((r) => r.role === 'dj').map((r) => r.user_id)

	let artistsById = new Map<string, Person>()
	let djsById = new Map<string, Person>()
	try {
		if (artistIds.length) {
			const { data } = await supabase.from('artists').select('id,name,stage_name,display_name').in('id', artistIds)
			artistsById = new Map(((data ?? []) as any[]).map((a) => [String(a.id), a as Person]))
		}
	} catch {
		artistsById = new Map()
	}
	try {
		if (djIds.length) {
			const { data } = await supabase.from('djs').select('id,name,stage_name,display_name').in('id', djIds)
			djsById = new Map(((data ?? []) as any[]).map((d) => [String(d.id), d as Person]))
		}
	} catch {
		djsById = new Map()
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Reported Users</h1>
						<p className="mt-1 text-sm text-gray-400">Violation history and escalation view.</p>
					</div>
					<Link href="/admin/moderation" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>
				{errorMsg ? <p className="mt-4 text-sm text-red-400">{errorMsg}</p> : null}
			</div>

			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<table className="w-full text-sm">
					<thead className="bg-black/20 text-xs text-gray-400">
						<tr>
							<th className="px-4 py-3 text-left">User</th>
							<th className="px-4 py-3 text-left">Role</th>
							<th className="px-4 py-3 text-left">Reports</th>
							<th className="px-4 py-3 text-left">Last Action</th>
							<th className="px-4 py-3 text-left">Status</th>
							<th className="px-4 py-3 text-right">View</th>
						</tr>
					</thead>
					<tbody className="divide-y divide-white/10">
						{rows.length ? (
							rows.map((r) => {
								const name =
									r.role === 'artist'
										? displayName(artistsById.get(r.user_id) ?? { id: r.user_id })
									: r.role === 'dj'
										? displayName(djsById.get(r.user_id) ?? { id: r.user_id })
									: r.user_id

								return (
									<tr key={`${r.role}:${r.user_id}`} className="hover:bg-white/5">
										<td className="px-4 py-3">
											<p className="font-medium">{name}</p>
											<p className="mt-1 text-xs text-gray-400 break-all">{r.user_id}</p>
										</td>
										<td className="px-4 py-3">{r.role}</td>
										<td className="px-4 py-3">{String(r.reports_count)}</td>
										<td className="px-4 py-3">
											{r.last_action ? (
												<div>
													<p>{r.last_action}</p>
													{r.last_action_at ? <p className="text-xs text-gray-400">{new Date(r.last_action_at).toLocaleString()}</p> : null}
												</div>
											) : (
												'—'
											)}
										</td>
										<td className="px-4 py-3">
											<span className={`rounded-full border px-2 py-1 text-xs ${r.status === 'blocked' ? 'border-red-500/30 bg-red-500/10 text-red-100' : 'border-white/10 bg-black/20'}`}>
												{r.status}
											</span>
										</td>
										<td className="px-4 py-3 text-right">
											<Link
												href={`/admin/moderation/reports?owner_id=${encodeURIComponent(r.user_id)}`}
												className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
											>
												Reports
											</Link>
										</td>
									</tr>
								)
							})
						) : (
							<tr>
								<td className="px-4 py-6 text-sm text-gray-400" colSpan={6}>
									No reported users yet.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
