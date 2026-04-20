import { NextResponse } from 'next/server'

export const runtime = 'nodejs'

function normalizeEnvOptional(key: string): string | null {
	const v = process.env[key]
	if (!v) return null
	const t = v.trim().replace(/^['"]|['"]$/g, '')
	return t ? t : null
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET(req: Request) {
	const url = new URL(req.url)
	const txRef = url.searchParams.get('tx_ref')
	const status = url.searchParams.get('status')
	const format = url.searchParams.get('format')
	const accept = req.headers.get('accept') || ''
	const redirect = normalizeEnvOptional('PAYCHANGU_SUCCESS_REDIRECT_URL')
	if (redirect) {
		const u = new URL(redirect)
		if (txRef) u.searchParams.set('tx_ref', txRef)
		if (status) u.searchParams.set('status', status)
		return NextResponse.redirect(u.toString(), { status: 302 })
	}

	// Default UX: redirect to a simple success page unless the caller explicitly wants JSON.
	const wantsJson = format === 'json' || accept.includes('application/json')
	if (wantsJson) return json({ ok: true, tx_ref: txRef, status })

	const u = new URL('/paychangu/success', url.origin)
	if (txRef) u.searchParams.set('tx_ref', txRef)
	if (status) u.searchParams.set('status', status)
	return NextResponse.redirect(u.toString(), { status: 302 })
}

export async function POST(req: Request) {
	// Some flows POST to callback_url; respond 200 so PayChangu considers it received.
	const raw = await req.text().catch(() => '')
	let data: any = null
	try {
		data = raw ? JSON.parse(raw) : null
	} catch {
		data = { raw }
	}
	return json({ ok: true, received: data })
}
