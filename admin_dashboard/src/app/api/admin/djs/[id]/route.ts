import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryKickAgoraChannel } from '@/lib/agora/channel-management'
import type { SupabaseClient } from '@supabase/supabase-js'

export const runtime = 'nodejs'

type PatchBody =
	| { action: 'set_approved'; approved: boolean; reason?: string }
	| { action: 'set_status'; status: 'pending' | 'active' | 'blocked'; reason?: string }

async function tryLogAdminAction(
	supabase: SupabaseClient,
	input: {
		actor_uid: string
		actor_email: string | null
		action: string
		entity: string
		entity_id: string
		meta?: Record<string, unknown>
	},
) {
	try {
		await supabase.from('admin_activity').insert({
			actor_uid: input.actor_uid,
			action: input.action,
			entity: input.entity,
			entity_id: input.entity_id,
			meta: input.meta ?? {},
		})
	} catch {
		// best-effort: table may not exist yet
	}

	try {
		await supabase.from('admin_logs').insert({
			admin_email: input.actor_email,
			action: input.action,
			target_type: 'dj',
			target_id: input.entity_id,
			reason: (input.meta as any)?.reason ?? null,
			meta: input.meta ?? {},
		})
	} catch {
		// best-effort
	}
}

async function tryEndLiveStreamsForHost(
	supabase: SupabaseClient,
	input: { host_type: 'artist' | 'dj'; host_id: string; admin_email: string | null; reason?: string },
) {
	try {
		// Real-time enforcement (best-effort): kick active channel(s) in Agora.
		try {
			const { data: live } = await supabase
				.from('live_streams')
				.select('id,channel_name')
				.eq('status', 'live')
				.eq('host_type', input.host_type)
				.eq('host_id', input.host_id)
				.limit(50)
			if (live?.length) {
				await Promise.all(
					live.map((s) => {
						const cname = String((s as any).channel_name ?? '').trim()
						return cname ? tryKickAgoraChannel({ channelName: cname, seconds: 600 }) : Promise.resolve(null)
					}),
				)
			}
		} catch {
			// ignore
		}

		const now = new Date().toISOString()
		await supabase
			.from('live_streams')
			.update({
				status: 'ended',
				ended_at: now,
				ended_by_email: input.admin_email,
				ended_reason: input.reason ?? null,
				updated_at: now,
			})
			.eq('status', 'live')
			.eq('host_type', input.host_type)
			.eq('host_id', input.host_id)
	} catch {
		// best-effort
	}
}

async function trySetFirebaseDisabled(firebaseUid: string, disabled: boolean) {
	try {
		const auth = getFirebaseAdminAuth()
		await auth.updateUser(firebaseUid, { disabled })
		if (disabled) {
			await auth.revokeRefreshTokens(firebaseUid)
		}
	} catch {
		// best-effort
	}
}

async function tryGetFirebaseUidForDj(supabase: SupabaseClient, id: string): Promise<string | null> {
	try {
		const { data } = await supabase.from('djs').select('firebase_uid').eq('id', id).maybeSingle()
		const uid = (data as { firebase_uid?: unknown } | null)?.firebase_uid
		return typeof uid === 'string' && uid.trim() ? uid.trim() : null
	} catch {
		return null
	}
}

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(adminCtx, 'can_manage_djs')
	} catch (e: any) {
		return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
	}

	const { id } = await ctx.params
	if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for admin actions (no anon fallback).' },
			{ status: 500 },
		)
	}
	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') {
		return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
	}

	// Primary model: status in {pending,active,blocked}
	if (body.action === 'set_status') {
		const target = body.status
		const reason = (body.reason ?? '').trim() || null
		const firebaseUid = await tryGetFirebaseUidForDj(supabase, id)
		let update: Record<string, unknown> = { status: target }
		if (target === 'active') update = { status: 'active', approved: true, blocked: false, can_go_live: true }
		if (target === 'pending') update = { status: 'pending', approved: false, blocked: false, can_go_live: false }
		if (target === 'blocked') update = { status: 'blocked', approved: false, blocked: true, can_go_live: false }

		// Try the full update first (covers projects that have status/blocked columns).
		let { error } = await supabase.from('djs').update(update).eq('id', id)
		if (error) {
			// Fallback 0: schema without can_go_live
			const { can_go_live: _ignored, ...noGoLive } = update
			;({ error } = await supabase.from('djs').update(noGoLive).eq('id', id))
		}
		if (error) {
			// Fallback 1: approved-only schema.
			if (target === 'active') ({ error } = await supabase.from('djs').update({ approved: true }).eq('id', id))
			else if (target === 'pending') ({ error } = await supabase.from('djs').update({ approved: false }).eq('id', id))
			else {
				// blocked: best-effort block
				;({ error } = await supabase.from('djs').update({ approved: false }).eq('id', id))
			}
		}

		if (error) return NextResponse.json({ error: error.message }, { status: 500 })
		if (firebaseUid) {
			if (target === 'blocked') await trySetFirebaseDisabled(firebaseUid, true)
			else await trySetFirebaseDisabled(firebaseUid, false)
		}
		if (target !== 'active') {
			// Only require stop-streams permission if there are active live streams to end.
			try {
				const { data: live } = await supabase
					.from('live_streams')
					.select('id')
					.eq('status', 'live')
					.eq('host_type', 'dj')
					.eq('host_id', id)
					.limit(1)
				if (live?.length) {
					assertPermission(adminCtx, 'can_stop_streams')
				}
			} catch {
				return NextResponse.json({ error: 'Forbidden: cannot stop streams' }, { status: 403 })
			}
			await tryEndLiveStreamsForHost(supabase, {
				host_type: 'dj',
				host_id: id,
				admin_email: adminCtx.admin.email,
				reason: reason ?? `dj status => ${target}`,
			})
		}
		await tryLogAdminAction(supabase, {
			actor_uid: adminCtx.firebase.uid,
			actor_email: adminCtx.admin.email,
			action: 'dj.set_status',
			entity: 'djs',
			entity_id: id,
			meta: { status: target, reason },
		})
		return NextResponse.json({ ok: true })
	}

	// Backwards-compatible: old boolean approval
	if (body.action === 'set_approved') {
		const reason = (body.reason ?? '').trim() || null
		const { error } = await supabase
			.from('djs')
			.update({ approved: body.approved, status: body.approved ? 'active' : 'pending', can_go_live: !!body.approved })
			.eq('id', id)
		if (error) {
			const fallback = await supabase.from('djs').update({ approved: body.approved }).eq('id', id)
			if (fallback.error) return NextResponse.json({ error: fallback.error.message }, { status: 500 })
		}
		await tryLogAdminAction(supabase, {
			actor_uid: adminCtx.firebase.uid,
			actor_email: adminCtx.admin.email,
			action: 'dj.set_approved',
			entity: 'djs',
			entity_id: id,
			meta: { approved: body.approved, reason },
		})
		return NextResponse.json({ ok: true })
	}

	return NextResponse.json({ error: 'Unknown action' }, { status: 400 })

}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(adminCtx, 'can_manage_djs')
	} catch {
		return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
	}

	const { id } = await ctx.params
	if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for admin actions (no anon fallback).' },
			{ status: 500 },
		)
	}

	let firebaseUid: string | null = null
	let userId: string | null = null
	try {
		const { data } = await supabase.from('djs').select('firebase_uid,user_id').eq('id', id).maybeSingle()
		firebaseUid = (data as any)?.firebase_uid ? String((data as any).firebase_uid) : null
		userId = (data as any)?.user_id ? String((data as any).user_id) : null
	} catch {
		// ignore
	}

	await tryEndLiveStreamsForHost(supabase, { host_type: 'dj', host_id: id, admin_email: adminCtx.admin.email, reason: 'dj deleted' })

	// Best-effort delete DJ record.
	const { error } = await supabase.from('djs').delete().eq('id', id)
	if (error) return NextResponse.json({ error: error.message }, { status: 500 })

	if (firebaseUid) await trySetFirebaseDisabled(firebaseUid, true)

	await tryLogAdminAction(supabase, {
		actor_uid: adminCtx.firebase.uid,
		actor_email: adminCtx.admin.email,
		action: 'dj.delete',
		entity: 'djs',
		entity_id: id,
		meta: { firebase_uid: firebaseUid, user_id: userId },
	})

	return NextResponse.json({ ok: true })
}
