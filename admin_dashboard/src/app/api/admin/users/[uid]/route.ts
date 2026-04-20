import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { tryKickAgoraChannel } from '@/lib/agora/channel-management'
import type { SupabaseClient } from '@supabase/supabase-js'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

type PatchBody =
	| { action: 'set_disabled'; disabled: boolean; reason?: string }
	| { action: 'set_role'; role: 'consumer' | 'artist' | 'dj' }
	| { action: 'set_status'; status: 'pending' | 'active' | 'suspended' | 'banned'; reason?: string }
	| { action: 'reset_password' }

function normalizeSupabaseCreatorStatus(status: string | null | undefined): 'pending' | 'active' | 'blocked' {
	const v = String(status ?? '').trim().toLowerCase()
	if (v === 'active') return 'active'
	if (v === 'pending') return 'pending'
	return 'blocked'
}

async function upsertConsumerProfile(supabase: SupabaseClient, input: { uid: string; email: string | null; name: string | null }) {
	try {
		await supabase
			.from('users')
			.upsert(
				{
					firebase_uid: input.uid,
					email: input.email,
					username: null,
				},
				{ onConflict: 'firebase_uid' },
			)
	} catch {
		// ignore
	}
}

async function upsertArtistProfile(
	supabase: SupabaseClient,
	input: { uid: string; email: string | null; name: string | null; status: 'pending' | 'active' | 'blocked' },
) {
	try {
		await supabase
			.from('artists')
			.upsert(
				{
					firebase_uid: input.uid,
					email: input.email,
					stage_name: input.name,
					status: input.status,
					can_upload: input.status === 'active',
					can_go_live: input.status === 'active',
				},
				{ onConflict: 'firebase_uid' },
			)
	} catch {
		// ignore
	}
}

async function upsertDjProfile(
	supabase: SupabaseClient,
	input: { uid: string; email: string | null; name: string | null; status: 'pending' | 'active' | 'blocked' },
) {
	try {
		await supabase
			.from('djs')
			.upsert(
				{
					firebase_uid: input.uid,
					email: input.email,
					dj_name: input.name,
					status: input.status,
					can_go_live: input.status === 'active',
				},
				{ onConflict: 'firebase_uid' },
			)
	} catch {
		// ignore
	}
}

async function tryEndLiveStreamsForFirebaseUid(
	supabase: SupabaseClient,
	uid: string,
	input: { admin_email: string | null; reason?: string },
) {
	try {
		// Real-time enforcement (best-effort): kick active channel(s) in Agora.
		try {
			const { data: live } = await supabase
				.from('live_streams')
				.select('id,channel_name')
				.eq('status', 'live')
				.eq('host_firebase_uid', uid)
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
			.eq('host_firebase_uid', uid)
	} catch {
		// ignore
	}
}

export async function DELETE() {
	return NextResponse.json({ error: 'Users cannot be deleted. Block instead.' }, { status: 405 })
}

export async function PATCH(req: Request, ctx: { params: Promise<{ uid: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try { assertPermission(adminCtx, 'can_manage_users') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

	const { uid } = await ctx.params
	if (!uid) return NextResponse.json({ error: 'Missing uid' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') {
		return NextResponse.json({ error: 'Invalid body' }, { status: 400 })
	}

	const supabaseAdmin = tryCreateSupabaseAdminClient()
	if (!supabaseAdmin) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for admin user actions (no anon fallback).' },
			{ status: 500 },
		)
	}

	try {
		const auth = getFirebaseAdminAuth()
		const userRecord = await auth.getUser(uid)
		const email = userRecord.email ?? null
		const name = (userRecord.displayName ?? '').trim() || null
		const currentClaims = (userRecord.customClaims ?? {}) as Record<string, unknown>
		const beforeState = {
			email,
			disabled: userRecord.disabled,
			claims: currentClaims,
		}

		if (body.action === 'set_disabled') {
			await auth.updateUser(uid, { disabled: !!body.disabled })
			if (body.disabled) {
				// Instant effect: invalidate existing sessions/tokens.
				await auth.revokeRefreshTokens(uid)
			}

			// Best-effort sync: use canonical `status` field if present.
			try {
				await supabaseAdmin
					.from('users')
					.update({ status: body.disabled ? 'blocked' : 'active' })
					.eq('firebase_uid', uid)
			} catch {
				// ignore
			}

			if (body.disabled) {
				try {
					assertPermission(adminCtx, 'can_stop_streams')
					await tryEndLiveStreamsForFirebaseUid(supabaseAdmin, uid, {
						admin_email: adminCtx.admin.email,
						reason: body.reason,
					})
				} catch {
					// skip if no permission
				}
			}

			await logAdminAction({
				ctx: adminCtx,
				action: 'user.set_disabled',
				target_type: 'user',
				target_id: uid,
				before_state: beforeState,
				after_state: { disabled: !!body.disabled },
				meta: { reason: body.reason ?? null },
				req,
			})

			return NextResponse.json({ ok: true })
		}

		if (body.action === 'set_role') {
			const role = body.role
			// Always revoke tokens so claims/dashboard switches apply immediately.
			await auth.revokeRefreshTokens(uid)
			// Ensure user isn't stuck disabled when changing roles.
			await auth.updateUser(uid, { disabled: false })

			const nextClaims = {
				...currentClaims,
				app_role: role,
				app_status: role === 'consumer' ? 'active' : 'pending',
			}
			await auth.setCustomUserClaims(uid, nextClaims)

			// Mirror role in Supabase by ensuring the appropriate profile row exists.
			if (role === 'consumer') {
				await upsertConsumerProfile(supabaseAdmin, { uid, email, name })
				// Best-effort: disable creator capability on old role rows (if they exist)
				await supabaseAdmin.from('artists').update({ status: 'blocked', can_upload: false, can_go_live: false }).eq('firebase_uid', uid)
				await supabaseAdmin.from('djs').update({ status: 'blocked', can_go_live: false }).eq('firebase_uid', uid)
			}
			if (role === 'artist') {
				await upsertArtistProfile(supabaseAdmin, { uid, email, name, status: 'pending' })
				await supabaseAdmin.from('djs').update({ status: 'blocked', can_go_live: false }).eq('firebase_uid', uid)
			}
			if (role === 'dj') {
				await upsertDjProfile(supabaseAdmin, { uid, email, name, status: 'pending' })
				await supabaseAdmin.from('artists').update({ status: 'blocked', can_upload: false, can_go_live: false }).eq('firebase_uid', uid)
			}

			await logAdminAction({
				ctx: adminCtx,
				action: 'user.set_role',
				target_type: 'user',
				target_id: uid,
				before_state: beforeState,
				after_state: { role },
				meta: { role },
				req,
			})

			return NextResponse.json({ ok: true, role })
		}

		if (body.action === 'set_status') {
			const status = body.status
			const reason = (body.reason ?? '').trim() || null
			const disabled = status === 'suspended' || status === 'banned'

			await auth.updateUser(uid, { disabled })
			await auth.revokeRefreshTokens(uid)

			const nextClaims = {
				...currentClaims,
				app_status: status,
			}
			await auth.setCustomUserClaims(uid, nextClaims)

			// Sync into Supabase status fields where available.
			const supaStatus = disabled ? 'blocked' : 'active'
			try {
				await supabaseAdmin.from('users').update({ status: supaStatus }).eq('firebase_uid', uid)
			} catch {
				// ignore
			}
			// creators
			try {
				const artistStatus = normalizeSupabaseCreatorStatus(status === 'pending' ? 'pending' : supaStatus)
				await supabaseAdmin
					.from('artists')
					.update({
						status: artistStatus,
						can_upload: artistStatus === 'active',
						can_go_live: artistStatus === 'active',
					})
					.eq('firebase_uid', uid)
			} catch {
				// ignore
			}
			try {
				const djStatus = normalizeSupabaseCreatorStatus(status === 'pending' ? 'pending' : supaStatus)
				await supabaseAdmin
					.from('djs')
					.update({
						status: djStatus,
						can_go_live: djStatus === 'active',
					})
					.eq('firebase_uid', uid)
			} catch {
				// ignore
			}

			if (disabled) {
				try {
					assertPermission(adminCtx, 'can_stop_streams')
					await tryEndLiveStreamsForFirebaseUid(supabaseAdmin, uid, {
						admin_email: adminCtx.admin.email,
						reason: reason ?? undefined,
					})
				} catch {
					// ignore
				}
			}

			await logAdminAction({
				ctx: adminCtx,
				action: 'user.set_status',
				target_type: 'user',
				target_id: uid,
				before_state: beforeState,
				after_state: { status, disabled },
				meta: { status, reason },
				req,
			})

			return NextResponse.json({ ok: true, status, disabled })
		}

		if (body.action === 'reset_password') {
			const u = await auth.getUser(uid)
			const email = u.email
			if (!email) return NextResponse.json({ error: 'User has no email' }, { status: 400 })
			const link = await auth.generatePasswordResetLink(email)
			return NextResponse.json({ ok: true, link })
		}

		return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
	} catch (err) {
		console.error('Failed to patch Firebase user:', err)
		return NextResponse.json(
			{ error: err instanceof Error ? err.message : 'Failed to update user' },
			{ status: 500 },
		)
	}
}
