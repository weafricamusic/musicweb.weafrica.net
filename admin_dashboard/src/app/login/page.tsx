'use client'
import { useState } from 'react'
import { signInWithEmailAndPassword, signOut } from 'firebase/auth'
import { getFirebaseAuth } from '@/lib/firebase/client'

export default function LoginPage() {
	const [email, setEmail] = useState('')
	const [password, setPassword] = useState('')
	const [error, setError] = useState<string | null>(null)
	const [loading, setLoading] = useState(false)

	async function onSubmit(e: React.FormEvent) {
		e.preventDefault()
		setError(null)
		setLoading(true)
		try {
			const cred = await signInWithEmailAndPassword(getFirebaseAuth(), email.trim(), password)
			const idToken = await cred.user.getIdToken()
			const res = await fetch('/api/auth/session', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ idToken }),
			})
			if (!res.ok) {
				try {
					await signOut(getFirebaseAuth())
				} catch {
					// ignore
				}
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to create session')
			}
			let nextPath = ''
			try {
				nextPath = new URLSearchParams(window.location.search).get('next') ?? ''
			} catch {
				nextPath = ''
			}
			nextPath = nextPath.trim()
			const legacyMap: Record<string, string> = {
				'/dashboard': '/admin/dashboard',
				'/dashboard/users': '/admin/users',
				'/dashboard/artists': '/admin/artists',
				'/dashboard/djs': '/admin/djs',
				'/dashboard/live': '/admin/live-streams',
				'/dashboard/moderation': '/admin/moderation',
				'/dashboard/finance': '/admin/payments',
			}
			let target = nextPath && nextPath.startsWith('/') ? nextPath : '/admin/dashboard'
			target = legacyMap[target] ?? target
			if (target.startsWith('/dashboard')) target = '/admin/dashboard'
			window.location.assign(target)
		} catch (err) {
			const message = err instanceof Error ? err.message : 'Login failed'
			if (message.toLowerCase().includes('auth/api-key-not-valid')) {
				setError(
					'Firebase API key not valid. Check Vercel env vars: NEXT_PUBLIC_FIREBASE_API_KEY, NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN, NEXT_PUBLIC_FIREBASE_PROJECT_ID. Make sure they are set for the same environment (Production vs Preview) and redeploy after changes.',
				)
			} else {
				setError(message)
			}
		} finally {
			setLoading(false)
		}
	}

	return (
		<div className="flex min-h-screen items-center justify-center bg-zinc-50 px-6 dark:bg-black">
			<div className="w-full max-w-sm rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
				<h1 className="text-xl font-semibold">Admin login</h1>
				<p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
					Use an approved admin account. Artist, DJ, and consumer sign-ins are disabled in this deployment.
				</p>
				<form className="mt-6 flex flex-col gap-4" onSubmit={onSubmit}>
					<label className="flex flex-col gap-2 text-sm">
						<span className="text-zinc-600 dark:text-zinc-400">Email</span>
						<input
							type="email"
							autoComplete="email"
							required
							value={email}
							onChange={(e) => setEmail(e.target.value)}
							className="h-11 rounded-xl border border-black/[.08] bg-transparent px-3 outline-none dark:border-white/[.145]"
						/>
					</label>
					<label className="flex flex-col gap-2 text-sm">
						<span className="text-zinc-600 dark:text-zinc-400">Password</span>
						<input
							type="password"
							autoComplete="current-password"
							required
							value={password}
							onChange={(e) => setPassword(e.target.value)}
							className="h-11 rounded-xl border border-black/[.08] bg-transparent px-3 outline-none dark:border-white/[.145]"
						/>
					</label>
					{error ? <p className="text-sm text-red-600 dark:text-red-400">{error}</p> : null}
					<button
						type="submit"
						disabled={loading}
						className="mt-2 h-11 rounded-xl bg-foreground text-background disabled:opacity-60"
					>
						{loading ? 'Signing in…' : 'Sign in'}
					</button>
				</form>
			</div>
		</div>
	)
}
