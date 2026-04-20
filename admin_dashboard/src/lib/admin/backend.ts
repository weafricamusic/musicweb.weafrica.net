import 'server-only'

import { cache } from 'react'

import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { verifyFirebaseSessionCookieRaw } from '@/lib/firebase/session'

function normalizeBaseUrl(raw: string | undefined): string {
	const trimmed = (raw ?? '').trim()
	if (!trimmed) {
		if (process.env.NODE_ENV === 'production') {
			throw new Error('Missing ADMIN_BACKEND_BASE_URL. Set it to your Nest admin API origin, e.g. https://api.example.com')
		}
		return 'http://127.0.0.1:3000'
	}

	if (/^https?:\/\//i.test(trimmed)) return trimmed.replace(/\/$/, '')
	return `https://${trimmed.replace(/\/$/, '')}`
}

function getFirebaseApiKey(): string {
	const apiKey = (process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? '').trim()
	if (!apiKey) {
		throw new Error('Missing NEXT_PUBLIC_FIREBASE_API_KEY for admin backend token exchange')
	}
	return apiKey
}

const mintAdminBackendIdToken = cache(async (): Promise<string> => {
	const decoded = await verifyFirebaseSessionCookieRaw()
	if (!decoded?.uid) {
		throw new Error('Missing Firebase admin session')
	}

	const auth = getFirebaseAdminAuth()
	const customToken = await auth.createCustomToken(decoded.uid)
	const apiKey = getFirebaseApiKey()

	const response = await fetch(
		`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
		{
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ token: customToken, returnSecureToken: true }),
			cache: 'no-store',
		},
	)

	const json = (await response.json().catch(() => null)) as { idToken?: string; error?: { message?: string } } | null
	if (!response.ok || !json?.idToken) {
		throw new Error(json?.error?.message || `Admin backend token exchange failed (${response.status})`)
	}

	return json.idToken
})

export async function adminBackendFetchJson<T>(pathname: string, init?: RequestInit): Promise<T> {
	const baseUrl = normalizeBaseUrl(process.env.ADMIN_BACKEND_BASE_URL)
	const idToken = await mintAdminBackendIdToken()
	const url = `${baseUrl}${pathname.startsWith('/') ? pathname : `/${pathname}`}`

	const response = await fetch(url, {
		...init,
		headers: {
			accept: 'application/json',
			authorization: `Bearer ${idToken}`,
			...(init?.headers ?? {}),
		},
		cache: 'no-store',
	})

	const text = await response.text()
	let body: unknown = null
	try {
		body = text ? JSON.parse(text) : null
	} catch {
		body = { raw: text }
	}

	if (!response.ok) {
		const message = typeof body === 'object' && body && 'message' in body ? String((body as { message?: unknown }).message) : `Request failed (${response.status})`
		throw new Error(message)
	}

	return body as T
}
