import { NextResponse } from 'next/server'
import type { DecodedIdToken } from 'firebase-admin/auth'
import { randomUUID } from 'crypto'
import type { SupabaseClient } from '@supabase/supabase-js'

import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { isAdminEmailAllowed } from '@/lib/admin/allowlist'
import { compressMediaBestEffort } from '@/lib/media/transcode'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function getBearerToken(req: Request): string | null {
	const raw = req.headers.get('authorization') || req.headers.get('Authorization')
	if (!raw) return null
	const m = raw.match(/^Bearer\s+(.+)$/i)
	return m ? m[1]!.trim() : null
}

function normalizeBucket(raw: unknown): string | null {
	const v = String(raw ?? '').trim()
	if (!v) return null
	// Conservative bucket name validation.
	if (!/^[a-z0-9][a-z0-9-_.]{0,62}$/i.test(v)) return null
	return v
}

function normalizePrefix(raw: unknown): string {
	const v = String(raw ?? '').trim()
	if (!v) return ''
	// Keep it path-safe; strip leading/trailing slashes.
	const cleaned = v
		.replace(/\\/g, '/')
		.replace(/\.{2,}/g, '.')
		.replace(/[^a-zA-Z0-9/_\-\.]/g, '')
		.replace(/^\/+/, '')
		.replace(/\/+$/, '')
	return cleaned
}

function getFileExt(name: string, mimeType: string): string {
	const lower = String(name || '').toLowerCase()
	const idx = lower.lastIndexOf('.')
	const ext = idx >= 0 ? lower.slice(idx + 1) : ''
	const clean = ext.replace(/[^a-z0-9]/g, '').slice(0, 8)
	if (clean) return clean

	const mt = String(mimeType || '').toLowerCase()
	if (mt === 'image/jpeg') return 'jpg'
	if (mt === 'image/png') return 'png'
	if (mt === 'image/webp') return 'webp'
	if (mt === 'audio/mpeg') return 'mp3'
	if (mt === 'audio/mp3') return 'mp3'
	if (mt === 'audio/wav') return 'wav'
	if (mt === 'audio/x-wav') return 'wav'
	if (mt === 'audio/aac') return 'aac'
	if (mt === 'audio/mp4') return 'm4a'
	return 'bin'
}

type Role = 'admin' | 'artist' | 'dj'

async function resolveUploaderRole(supabase: SupabaseClient, decoded: DecodedIdToken): Promise<Role | null> {
	const email = (decoded.email ?? '').trim().toLowerCase()
	if (email && isAdminEmailAllowed(email)) return 'admin'

	// Best-effort DB checks. Tables vary across projects; treat schema-missing as non-fatal.
	const uid = decoded.uid

	// Artists
	try {
		const { data, error } = await supabase
			.from('artists')
			.select('id,approved,status,blocked')
			.eq('firebase_uid', uid)
			.limit(1)
			.maybeSingle<any>()
		if (!error && data) {
			const blocked = data.blocked === true || String(data.status ?? '').toLowerCase() === 'blocked'
			if (blocked) return null
			return 'artist'
		}
	} catch {
		// ignore
	}

	// DJs
	try {
		const { data, error } = await supabase
			.from('djs')
			.select('id,approved,status,blocked')
			.eq('firebase_uid', uid)
			.limit(1)
			.maybeSingle<any>()
		if (!error && data) {
			const blocked = data.blocked === true || String(data.status ?? '').toLowerCase() === 'blocked'
			if (blocked) return null
			return 'dj'
		}
	} catch {
		// ignore
	}

	return null
}

export async function POST(req: Request) {
	const idToken = getBearerToken(req)
	if (!idToken) return json({ ok: false, error: 'Missing Authorization: Bearer <firebase_id_token>' }, { status: 401 })

	let decoded: DecodedIdToken
	try {
		const auth = getFirebaseAdminAuth()
		decoded = await auth.verifyIdToken(idToken)
	} catch {
		return json({ ok: false, error: 'Invalid auth token' }, { status: 401 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 500 })

	const form = await req.formData().catch(() => null)
	if (!form) return json({ ok: false, error: 'Invalid multipart form' }, { status: 400 })

	const file = form.get('file')
	if (!(file instanceof File)) return json({ ok: false, error: 'Missing file' }, { status: 400 })

	const bucket = normalizeBucket(form.get('bucket'))
	if (!bucket) return json({ ok: false, error: 'Missing/invalid bucket' }, { status: 400 })

	const prefix = normalizePrefix(form.get('prefix'))
	const maxBytes = Number(process.env.UPLOAD_MAX_BYTES ?? '') || 100 * 1024 * 1024
	if (file.size > maxBytes) return json({ ok: false, error: `File too large (max ${maxBytes} bytes)` }, { status: 413 })

	const role = await resolveUploaderRole(supabase, decoded)
	if (!role) return json({ ok: false, error: 'Forbidden (not an artist/dj/admin)' }, { status: 403 })

	let bytes: Buffer
	try {
		bytes = Buffer.from(await file.arrayBuffer())
	} catch {
		return json({ ok: false, error: 'Failed to read upload' }, { status: 400 })
	}

	const compressed = await compressMediaBestEffort({ bytes, contentType: file.type, filename: file.name })
	if (compressed.transcoded) {
		bytes = compressed.bytes
	}

	const ext = compressed.transcoded && compressed.ext ? compressed.ext : getFileExt(file.name, file.type)
	const basePath = `${role}/${encodeURIComponent(decoded.uid)}/${Date.now()}-${randomUUID()}.${ext}`
	const objectPath = prefix ? `${prefix}/${basePath}` : basePath

	const uploadRes = await supabase.storage.from(bucket).upload(objectPath, bytes, {
		contentType: (compressed.transcoded ? compressed.contentType : file.type) || 'application/octet-stream',
		upsert: false,
	})

	if (uploadRes.error) {
		return json({ ok: false, error: `Storage upload failed: ${uploadRes.error.message}` }, { status: 500 })
	}

	const publicUrl = supabase.storage.from(bucket).getPublicUrl(objectPath)?.data?.publicUrl ?? null
	let signedUrl: string | null = null
	try {
		const { data } = await supabase.storage.from(bucket).createSignedUrl(objectPath, 60 * 60)
		signedUrl = data?.signedUrl ?? null
	} catch {
		signedUrl = null
	}

	return json({
		ok: true,
		bucket,
		path: objectPath,
		public_url: publicUrl,
		signed_url: signedUrl,
	})
}
