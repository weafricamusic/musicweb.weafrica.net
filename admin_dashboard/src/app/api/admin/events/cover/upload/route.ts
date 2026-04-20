import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { assertPermission, getAdminContext } from '@/lib/admin/session'
import { logAdminAction } from '@/lib/admin/audit'
import { NextResponse } from 'next/server'
import { randomUUID } from 'crypto'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
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
	return 'jpg'
}

function isAllowedImageType(mimeType: string): boolean {
	const mt = String(mimeType || '').toLowerCase()
	return mt === 'image/jpeg' || mt === 'image/png' || mt === 'image/webp'
}

type UploadOk = {
	ok: true
	bucket: string
	object_path: string
	public_url: string | null
	signed_url: string | null
}

type UploadErr = {
	ok?: false
	error: string
}

export async function POST(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' } satisfies UploadErr, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' } satisfies UploadErr, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' } satisfies UploadErr, { status: 500 })

	const form = await req.formData().catch(() => null)
	if (!form) return json({ ok: false, error: 'Invalid multipart form' } satisfies UploadErr, { status: 400 })

	const file = form.get('file')
	if (!(file instanceof File)) return json({ ok: false, error: 'Missing file' } satisfies UploadErr, { status: 400 })
	if (!isAllowedImageType(file.type)) return json({ ok: false, error: 'Unsupported image type (use JPG/PNG/WebP)' } satisfies UploadErr, { status: 400 })

	const maxBytes = 10 * 1024 * 1024
	if (file.size > maxBytes) return json({ ok: false, error: `File too large (max ${maxBytes} bytes)` } satisfies UploadErr, { status: 413 })

	let bytes: Buffer
	try {
		bytes = Buffer.from(await file.arrayBuffer())
	} catch {
		return json({ ok: false, error: 'Failed to read upload' } satisfies UploadErr, { status: 400 })
	}

	const bucket = (process.env.SUPABASE_EVENT_COVERS_BUCKET ?? '').trim() || 'event-covers'
	const ext = getFileExt(file.name, file.type)
	const objectPath = `events/covers/${Date.now()}-${randomUUID()}.${ext}`

	const uploadRes = await supabase.storage.from(bucket).upload(objectPath, bytes, {
		contentType: file.type || 'image/jpeg',
		upsert: false,
	})

	if (uploadRes.error) {
		return json({ ok: false, error: `Storage upload failed: ${uploadRes.error.message}` } satisfies UploadErr, { status: 500 })
	}

	const publicUrl = supabase.storage.from(bucket).getPublicUrl(objectPath)?.data?.publicUrl ?? null
	let signedUrl: string | null = null
	try {
		const { data } = await supabase.storage.from(bucket).createSignedUrl(objectPath, 60 * 60)
		signedUrl = data?.signedUrl ?? null
	} catch {
		signedUrl = null
	}

	await logAdminAction({
		ctx,
		action: 'events.cover.upload',
		target_type: 'event',
		target_id: objectPath,
		before_state: null,
		after_state: { bucket, object_path: objectPath, public_url: publicUrl },
		meta: { module: 'events', bucket },
		req,
	})

	return json({
		ok: true,
		bucket,
		object_path: objectPath,
		public_url: publicUrl,
		signed_url: signedUrl,
	} satisfies UploadOk)
}
