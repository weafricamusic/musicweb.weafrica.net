import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { contentTypeLabel, reasonLabel, reportStatusLabel } from '../../_types'
import { ReportActionsClient } from './ReportActionsClient'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type ReportRow = {
	id: string
	target_type: string
	target_id: string
	reason: string
	reporter_id: string | null
	description: string | null
	status: string
	created_at: string
	reviewed_at?: string | null
	reviewed_by?: string | null
	details?: Record<string, unknown> | null
}

type ReportDetailPayload = {
	report: ReportRow
	history: Array<Pick<ReportRow, 'id' | 'status' | 'created_at' | 'reason' | 'reviewed_at'>>
}

export default async function ReportDetailPage({ params }: { params: Promise<{ id: string }> }) {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const { id } = await params
	if (!id) redirect('/admin/moderation/reports')

	const payload = await adminBackendFetchJson<ReportDetailPayload | null>(`/admin/reports/${encodeURIComponent(id)}`).catch(() => null)
	const report = payload?.report ?? null
	if (!report) {
		return (
			<div className="space-y-6">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-lg font-semibold">Report</h1>
					<p className="mt-2 text-sm text-red-400">Failed to load report: Not found</p>
					<Link href="/admin/moderation/reports" className="mt-4 inline-flex text-sm underline">
						Back
					</Link>
				</div>
			</div>
		)
	}

	const history = payload?.history ?? []

	// Best-effort content preview
	let previewTitle: string | null = null
	let previewStatus: string | null = null
	let previewLink: string | null = null
	const supabase = tryCreateSupabaseAdminClient()
	try {
		if (supabase && report.target_type === 'song') {
			const { data } = await supabase.from('songs').select('id,title,is_active,approved').eq('id', report.target_id).maybeSingle<any>()
			if (data) {
				previewTitle = String(data.title ?? data.id)
				previewStatus = data.is_active === false ? 'disabled' : data.approved ? 'approved' : 'pending'
			}
		}
		if (supabase && report.target_type === 'video') {
			const { data } = await supabase.from('videos').select('id,title,is_active,approved').eq('id', report.target_id).maybeSingle<any>()
			if (data) {
				previewTitle = String(data.title ?? data.id)
				previewStatus = data.is_active === false ? 'disabled' : data.approved ? 'approved' : 'pending'
			}
		}
		if (supabase && report.target_type === 'live') {
			const { data } = await supabase.from('live_sessions').select('id,channel_id,is_live').eq('id', report.target_id).maybeSingle<any>()
			if (data) {
				previewTitle = String(data.channel_id ?? data.id)
				previewStatus = data.is_live === true ? 'live' : 'ended'
				previewLink = `/admin/live-streams/${String(data.id)}`
			}
		}
	} catch {
		// ignore
	}

	const createdAt = new Date(report.created_at).toLocaleString()
	const canRemove = ['song', 'video', 'event', 'live'].includes(String(report.target_type).toLowerCase())

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Review Report #{report.id}</h1>
						<p className="mt-1 text-sm text-gray-400">{contentTypeLabel(report.target_type)} • {reasonLabel(report.reason)} • {createdAt}</p>
					</div>
					<Link href="/admin/moderation/reports" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>

				<div className="mt-4 grid gap-3 text-sm md:grid-cols-2">
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">Content</p>
						<p className="mt-1 font-medium break-all">{String(report.target_id)}</p>
						<p className="mt-1 text-xs text-gray-400">Preview: {previewTitle ?? '—'} {previewStatus ? `(${previewStatus})` : ''}</p>
						{previewLink ? (
							<Link href={previewLink} className="mt-2 inline-flex text-xs underline">
								Open live stream
							</Link>
						) : null}
					</div>
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">Reporter Message</p>
						<p className="mt-1 break-words">{report.description ? String(report.description) : '—'}</p>
						<p className="mt-2 text-xs text-gray-400">Reported By: {report.reporter_id ? String(report.reporter_id) : '—'}</p>
						<p className="mt-2 text-xs text-gray-400">Status: {reportStatusLabel(report.status)}</p>
						<p className="mt-2 text-xs text-gray-400">Reviewed By: {report.reviewed_by ? String(report.reviewed_by) : '—'}</p>
					</div>
				</div>
			</div>

			<div className="grid gap-6 lg:grid-cols-2">
				<ReportActionsClient reportId={report.id} canRemove={canRemove} isPending={String(report.status).toLowerCase() === 'pending'} />

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h3 className="text-base font-semibold">Report History (same content)</h3>
					<div className="mt-3 space-y-2 text-sm">
						{history.length ? (
							history.map((h) => (
								<div key={h.id} className="rounded-xl border border-white/10 bg-black/20 p-3">
									<p className="text-xs text-gray-400">#{h.id} • {new Date(h.created_at).toLocaleString()}</p>
									<p className="mt-1">{reasonLabel(String(h.reason))} • <span className="text-xs">{reportStatusLabel(String(h.status))}</span></p>
								</div>
							))
						) : (
							<p className="text-sm text-gray-400">No history available.</p>
						)}
					</div>
				</div>
			</div>
		</div>
	)
}
