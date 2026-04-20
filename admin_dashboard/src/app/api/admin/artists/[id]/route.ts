import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryKickAgoraChannel } from '@/lib/agora/channel-management'
import type { SupabaseClient } from '@supabase/supabase-js'

export const runtime = 'nodejs'

type PatchBody =
	| { action: 'set_status'; status: 'pending' | 'active' | 'blocked'; reason?: string }
	| { action: 'set_verified'; verified: boolean; reason?: string }
	| { action: 'set_permissions'; can_upload_songs?: boolean; can_upload_videos?: boolean; can_go_live?: boolean; reason?: string }
	| { action: 'reset_access'; reason?: string }
	| { action: 'set_approved'; approved: boolean; reason?: string }

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
			target_type: 'artist',
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
		// Force sign-out everywhere ASAP (important for "suspend => cannot log in/upload").
		if (disabled) {
			await auth.revokeRefreshTokens(firebaseUid)
		}
	} catch {
		// best-effort: some projects may not store firebase_uid or Firebase Admin may be misconfigured
	}
}

async function tryGetFirebaseUidForArtist(supabase: SupabaseClient, id: string): Promise<string | null> {
	try {
		const { data } = await supabase.from('artists').select('firebase_uid').eq('id', id).maybeSingle()
		const uid = (data as { firebase_uid?: unknown } | null)?.firebase_uid
		return typeof uid === 'string' && uid.trim() ? uid.trim() : null
	} catch {
		return null
	}
}

async function updateArtistWithFallback(
	supabase: SupabaseClient,
	id: string,
	attempts: Array<Record<string, unknown>>,
): Promise<{ error: any | null }> {
	let lastError: any = null
	for (const patch of attempts) {
		const { error } = await supabase.from('artists').update(patch).eq('id', id)
		if (!error) return { error: null }
		lastError = error
	}
	return { error: lastError }
}

async function tryUpdateArtistPermissionFlags(
	supabase: SupabaseClient,
	id: string,
	patches: Array<Record<string, unknown>>,
): Promise<void> {
	for (const patch of patches) {
		const { error } = await supabase.from('artists').update(patch).eq('id', id)
		if (error) {
			// best-effort: column(s) may not exist yet
		}
	}
}

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try { assertPermission(adminCtx, 'can_manage_artists') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

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
		const firebaseUid = await tryGetFirebaseUidForArtist(supabase, id)
		const approved = target === 'active'
		const blocked = target === 'blocked'

		// Update core status fields first so approval works even if optional permission columns differ by schema.
		const { error } = await updateArtistWithFallback(supabase, id, [
			{ status: target, approved, blocked },
			{ status: target, approved },
			{ approved },
		])
		if (error) return NextResponse.json({ error: error.message }, { status: 500 })

		// Best-effort: sync common permission flags if present.
		await tryUpdateArtistPermissionFlags(supabase, id, [
			{ can_upload: approved },
			{ can_upload_songs: approved },
			{ can_upload_videos: approved },
			{ can_go_live: approved },
		])

		// Enforce auth-level access (best-effort) so "suspend" blocks login/upload immediately.
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
					.eq('host_type', 'artist')
					.eq('host_id', id)
					.limit(1)
				if (live?.length) {
					assertPermission(adminCtx, 'can_stop_streams')
				}
			} catch {
				return NextResponse.json({ error: 'Forbidden: cannot stop streams' }, { status: 403 })
			}
			await tryEndLiveStreamsForHost(supabase, {
				host_type: 'artist',
				host_id: id,
				admin_email: adminCtx.admin.email,
				reason: reason ?? `artist status => ${target}`,
			})
		}
		await tryLogAdminAction(supabase, {
			actor_uid: adminCtx.firebase.uid,
			actor_email: adminCtx.admin.email,
			action: 'artist.set_status',
			entity: 'artists',
			entity_id: id,
			meta: { status: target, reason },
		})
		return NextResponse.json({ ok: true })
	}

	if (body.action === 'set_verified') {
		const reason = (body.reason ?? '').trim() || null
		const { error } = await supabase.from('artists').update({ verified: body.verified }).eq('id', id)
		if (error) return NextResponse.json({ error: error.message }, { status: 500 })
		await tryLogAdminAction(supabase, {
			actor_uid: adminCtx.firebase.uid,
			actor_email: adminCtx.admin.email,
			action: 'artist.set_verified',
			entity: 'artists',
			entity_id: id,
			meta: { verified: body.verified, reason },
		})
		return NextResponse.json({ ok: true })
	}

	if (body.action === 'set_permissions') {
		const reason = (body.reason ?? '').trim() || null
		const update: Record<string, unknown> = {}
		if (typeof body.can_upload_songs === 'boolean') update.can_upload_songs = body.can_upload_songs
		if (typeof body.can_upload_videos === 'boolean') update.can_upload_videos = body.can_upload_videos
		if (typeof body.can_go_live === 'boolean') update.can_go_live = body.can_go_live
		if (!Object.keys(update).length) return NextResponse.json({ error: 'No permission fields provided' }, { status: 400 })

		const { error } = await supabase.from('artists').update(update).eq('id', id)
		if (error) return NextResponse.json({ error: error.message }, { status: 500 })
		await tryLogAdminAction(supabase, {
			actor_uid: adminCtx.firebase.uid,
			actor_email: adminCtx.admin.email,
			action: 'artist.set_permissions',
			entity: 'artists',
			entity_id: id,
			meta: { ...update, reason },
		})
		return NextResponse.json({ ok: true })
	}

	if (body.action === 'reset_access') {
		const reason = (body.reason ?? '').trim() || null
		const firebaseUid = await tryGetFirebaseUidForArtist(supabase, id)
		// Best-effort reset: unblocked, not verified, back to pending.
		// Apply core fields first, then re-enable common permission flags if present.
		const { error } = await updateArtistWithFallback(supabase, id, [
			{ status: 'pending', approved: false, blocked: false, verified: false },
			{ status: 'pending', approved: false, blocked: false },
			{ status: 'pending', approved: false },
			{ approved: false },
		])
		if (error) return NextResponse.json({ error: error.message }, { status: 500 })

		await tryUpdateArtistPermissionFlags(supabase, id, [
			{ can_upload: true },
			{ can_upload_songs: true },
			{ can_upload_videos: true },
			{ can_go_live: true },
		])
		if (firebaseUid) await trySetFirebaseDisabled(firebaseUid, false)
		await tryLogAdminAction(supabase, {
			actor_uid: adminCtx.firebase.uid,
			actor_email: adminCtx.admin.email,
			action: 'artist.reset_access',
			entity: 'artists',
			entity_id: id,
			meta: { reason },
		})
		return NextResponse.json({ ok: true })
	}

	// Backwards-compatible
	if (body.action === 'set_approved') {
		const reason = (body.reason ?? '').trim() || null
		const { error } = await supabase
			.from('artists')
			.update({ approved: body.approved, status: body.approved ? 'active' : 'pending' })
			.eq('id', id)
		if (error) {
			const fallback = await supabase.from('artists').update({ approved: body.approved }).eq('id', id)
			if (fallback.error) return NextResponse.json({ error: fallback.error.message }, { status: 500 })
		}
		await tryLogAdminAction(supabase, {
			actor_uid: adminCtx.firebase.uid,
			actor_email: adminCtx.admin.email,
			action: 'artist.set_approved',
			entity: 'artists',
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
		assertPermission(adminCtx, 'can_manage_artists')
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
		const { data } = await supabase.from('artists').select('firebase_uid,user_id').eq('id', id).maybeSingle()
		firebaseUid = (data as any)?.firebase_uid ? String((data as any).firebase_uid) : null
		userId = (data as any)?.user_id ? String((data as any).user_id) : null
	} catch {
		// ignore
	}

	// End any live streams first.
	await tryEndLiveStreamsForHost(supabase, { host_type: 'artist', host_id: id, admin_email: adminCtx.admin.email, reason: 'artist deleted' })

	// Best-effort delete content.
	try {
		if (firebaseUid) {
			await supabase.from('songs').delete().eq('firebase_uid', firebaseUid)
			await supabase.from('videos').delete().eq('firebase_uid', firebaseUid)
		} else if (userId) {
			await supabase.from('songs').delete().eq('user_id', userId)
			await supabase.from('videos').delete().eq('user_id', userId)
		} else {
			await supabase.from('songs').delete().eq('artist_id', id)
		}
	} catch {
		// ignore
	}

	// Delete artist record.
	const { error } = await supabase.from('artists').delete().eq('id', id)
	if (error) return NextResponse.json({ error: error.message }, { status: 500 })

	if (firebaseUid) await trySetFirebaseDisabled(firebaseUid, true)

	await tryLogAdminAction(supabase, {
		actor_uid: adminCtx.firebase.uid,
		actor_email: adminCtx.admin.email,
		action: 'artist.delete',
		entity: 'artists',
		entity_id: id,
		meta: { firebase_uid: firebaseUid, user_id: userId },
	})

	return NextResponse.json({ ok: true })
}
