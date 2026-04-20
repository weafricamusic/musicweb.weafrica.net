'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

export function LogoutButton({ redirectTo = '/auth/login' }: { redirectTo?: string } = {}) {
	const router = useRouter()
	const [loading, setLoading] = useState(false)

	async function onLogout() {
		setLoading(true)
		try {
			await fetch('/api/auth/session', { method: 'DELETE' })
			router.push(redirectTo)
		} finally {
			setLoading(false)
		}
	}

	return (
		<button
			onClick={onLogout}
			disabled={loading}
			className="h-10 rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145] disabled:opacity-60"
		>
			{loading ? 'Signing out…' : 'Sign out'}
		</button>
	)
}
