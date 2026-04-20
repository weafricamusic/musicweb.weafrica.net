import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { jwtVerify } from 'jose'

const FIREBASE_SESSION_COOKIE = 'firebase_session'
const ADMIN_GUARD_COOKIE = 'admin_guard'
const DISABLED_CREATOR_API_MESSAGE = 'Creator endpoints are disabled in this admin dashboard deployment.'

function parseAllowedOrigins(value: string | undefined): string[] {
	if (!value) return []
	return value
		.split(',')
		.map((s) => s.trim())
		.filter(Boolean)
}

function isOriginAllowed(origin: string, allowedOrigins: string[]): boolean {
	if (allowedOrigins.includes('*')) return true
	return allowedOrigins.includes(origin)
}

function getCorsHeaders(req: NextRequest): Record<string, string> | null {
	const origin = req.headers.get('origin')
	const allowedOrigins = parseAllowedOrigins(process.env.CORS_ALLOW_ORIGINS)

	if (!origin || allowedOrigins.length === 0) return null
	if (!isOriginAllowed(origin, allowedOrigins)) return null

	const allowCredentials = process.env.CORS_ALLOW_CREDENTIALS === 'true'
	const requestHeaders = req.headers.get('access-control-request-headers')

	const corsHeaders: Record<string, string> = {
		'Access-Control-Allow-Origin': allowedOrigins.includes('*') && !allowCredentials ? '*' : origin,
		'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
		'Access-Control-Allow-Headers': requestHeaders ?? 'Content-Type, Authorization',
		'Access-Control-Max-Age': '86400',
		Vary: 'Origin',
	}

	if (allowCredentials) {
		corsHeaders['Access-Control-Allow-Credentials'] = 'true'
	}

	return corsHeaders
}

function applyCorsHeaders(res: NextResponse, corsHeaders: Record<string, string> | null) {
	if (!corsHeaders) return
	for (const [key, value] of Object.entries(corsHeaders)) {
		res.headers.set(key, value)
	}
}

function getGuardSecret(): Uint8Array | null {
	const raw = process.env.ADMIN_GUARD_SECRET
	if (!raw) return null
	const value = raw.trim().replace(/^['"]|['"]$/g, '')
	if (!value) return null
	return new TextEncoder().encode(value)
}

function isPublicPath(pathname: string): boolean {
	return (
		pathname === '/auth/login' ||
		pathname === '/login' ||
		pathname.startsWith('/api/auth') ||
		pathname.startsWith('/_next') ||
		pathname.startsWith('/favicon')
	)
}

function isApiPath(pathname: string): boolean {
	return pathname === '/api' || pathname.startsWith('/api/')
}

function isDisabledCreatorApiPath(pathname: string): boolean {
	return pathname.startsWith('/api/artist') || pathname.startsWith('/api/dj')
}

function isDisabledCreatorPortalPath(pathname: string): boolean {
	return pathname.startsWith('/artist') || pathname.startsWith('/dj')
}

export default async function (req: NextRequest) {
	const { pathname } = req.nextUrl
	const apiPath = isApiPath(pathname)
	const corsHeaders = apiPath ? getCorsHeaders(req) : null

	if (apiPath && corsHeaders && req.method === 'OPTIONS') {
		return new NextResponse(null, { status: 204, headers: corsHeaders })
	}

	if (isDisabledCreatorApiPath(pathname)) {
		const res = NextResponse.json({ error: DISABLED_CREATOR_API_MESSAGE }, { status: 403 })
		applyCorsHeaders(res, corsHeaders)
		return res
	}

	if (isDisabledCreatorPortalPath(pathname)) {
		const url = req.nextUrl.clone()
		url.pathname = '/auth/login'
		url.searchParams.set('next', '/admin/dashboard')
		return NextResponse.redirect(url)
	}

	if (isPublicPath(pathname)) {
		const res = NextResponse.next()
		applyCorsHeaders(res, corsHeaders)
		return res
	}

	// Protect dashboard routes (and legacy /admin routes that still exist).
	if (pathname.startsWith('/dashboard') || pathname.startsWith('/admin')) {
		const session = req.cookies.get(FIREBASE_SESSION_COOKIE)?.value
		const guard = req.cookies.get(ADMIN_GUARD_COOKIE)?.value
		const secret = getGuardSecret()

		// Fail closed if secret isn't configured; this is admin-only.
		if (!secret) {
			const url = req.nextUrl.clone()
			url.pathname = '/auth/login'
			url.searchParams.set('next', pathname)
			return NextResponse.redirect(url)
		}

		if (!session || !guard) {
			const url = req.nextUrl.clone()
			url.pathname = '/auth/login'
			url.searchParams.set('next', pathname)
			return NextResponse.redirect(url)
		}

		try {
			const { payload } = await jwtVerify(guard, secret, { algorithms: ['HS256'] })
			if (payload.admin !== true) throw new Error('Not admin')
			if (!payload.email) throw new Error('Missing email')
		} catch {
			const url = req.nextUrl.clone()
			url.pathname = '/auth/login'
			url.searchParams.set('next', pathname)
			return NextResponse.redirect(url)
		}
	}

	// Lightweight rate limiting for admin APIs: 100 requests per 5 minutes per IP per route.
	if (pathname.startsWith('/api/admin/')) {
		const ip = req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || null
		const routeKey = `${ip ?? 'unknown'}:${pathname}`
		const now = Date.now()
		const windowMs = 5 * 60 * 1000
		const maxReq = 100

		// Use a global in-memory store. For production, prefer Redis.
		// @ts-expect-error - global cache (not part of lib typings)
		globalThis.__ADMIN_RATE__ = globalThis.__ADMIN_RATE__ || new Map<string, { c: number; w: number }>()
		// @ts-expect-error - global cache (not part of lib typings)
		const store: Map<string, { c: number; w: number }> = globalThis.__ADMIN_RATE__
		const bucket = store.get(routeKey)
		if (!bucket || now - bucket.w > windowMs) {
			store.set(routeKey, { c: 1, w: now })
		} else if (bucket.c >= maxReq) {
			const res = NextResponse.json({ error: 'Too many requests' }, { status: 429 })
			applyCorsHeaders(res, corsHeaders)
			return res
		} else {
			bucket.c += 1
		}
	}

	const res = NextResponse.next()
	applyCorsHeaders(res, corsHeaders)
	return res
}

export const config = {
	matcher: ['/api/:path*', '/dashboard/:path*', '/admin/:path*', '/artist/:path*', '/dj/:path*'],
}
