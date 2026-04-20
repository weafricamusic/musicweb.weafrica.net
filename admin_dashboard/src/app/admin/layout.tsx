import Sidebar from "@/components/admin/Sidebar"
import TopBar from "@/components/admin/TopBar"
import AdminDrawerEffects from '@/components/admin/AdminDrawerEffects'
import { getAdminContext } from "@/lib/admin/session"
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { getSupabaseServerEnvDebug } from '@/lib/supabase/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import Link from 'next/link'
import { redirect } from "next/navigation"

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export default async function AdminLayout({
	children,
}: {
	children: React.ReactNode
}) {
	const firebaseUser = await verifyFirebaseSessionCookie()
	if (!firebaseUser) redirect('/auth/login')

	const ctx = await getAdminContext()
	if (!ctx) {
		const supabaseEnv = getSupabaseServerEnvDebug()
		const supabase = tryCreateSupabaseAdminClient()
		const normalizedEmail = (firebaseUser.email ?? '').trim().toLowerCase()

		if (!supabase) {
			return (
				<div className="flex min-h-screen items-center justify-center bg-[#0e1117] px-6 text-white">
					<div className="w-full max-w-lg rounded-2xl border border-white/10 bg-white/5 p-6">
						<h1 className="text-xl font-semibold">Service role required</h1>
						<p className="mt-2 text-sm text-gray-300">
							Set <code className="rounded bg-black/30 px-1">SUPABASE_SERVICE_ROLE_KEY</code> (server-only) and reload.
						</p>
						<div className="mt-4 rounded-xl border border-white/10 bg-black/20 p-4 text-sm text-gray-200">
							<div className="font-medium">Diagnostics</div>
							<div className="mt-2 space-y-1 text-gray-300">
								<div>
									<span className="text-gray-400">Supabase project:</span> {supabaseEnv.urlHost}
								</div>
								<div>
									<span className="text-gray-400">Server key mode:</span> {supabaseEnv.keyMode}
								</div>
								<div>
									<span className="text-gray-400">Lookup email:</span> {normalizedEmail || '—'}
								</div>
							</div>
						</div>
						<div className="mt-4 flex gap-3">
							<a href="/auth/login" className="rounded-xl border border-white/10 bg-white/5 px-4 py-2 text-sm hover:bg-white/10">
								Back to login
							</a>
							{process.env.NODE_ENV === 'production' ? null : (
								<a href="/api/admin/supabase-env-debug" className="rounded-xl border border-white/10 bg-white/5 px-4 py-2 text-sm hover:bg-white/10">
									Env debug
								</a>
							)}
						</div>
					</div>
				</div>
			)
		}

		const { data: adminProbe, error: adminProbeError } = normalizedEmail
			? await supabase
					.from('admins_with_permissions')
					.select('email,status,role')
					.eq('email', normalizedEmail)
					.limit(1)
					.maybeSingle()
			: { data: null, error: null }

		return (
			<div className="flex min-h-screen items-center justify-center bg-[#0e1117] px-6 text-white">
				<div className="w-full max-w-lg rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-xl font-semibold">Admin access not configured</h1>
					<p className="mt-2 text-sm text-gray-300">
						You are signed in as <span className="font-medium">{firebaseUser.email ?? firebaseUser.uid}</span>, but this account is not
						 registered as an admin in Supabase.
					</p>
					<div className="mt-4 rounded-xl border border-white/10 bg-black/20 p-4 text-sm text-gray-200">
						<div className="font-medium">Diagnostics</div>
						<div className="mt-2 space-y-1 text-gray-300">
							<div>
								<span className="text-gray-400">Supabase project:</span> {supabaseEnv.urlHost}
							</div>
							<div>
								<span className="text-gray-400">Server key mode:</span> {supabaseEnv.keyMode}
							</div>
							<div>
								<span className="text-gray-400">Lookup email:</span> {normalizedEmail || '—'}
							</div>
							<div>
								<span className="text-gray-400">Admin row:</span>{' '}
								{adminProbe ? `${adminProbe.email} (${adminProbe.role}, ${adminProbe.status})` : 'Not found (or blocked by RLS)'}
							</div>
							{adminProbeError ? (
								<div className="text-red-300">
									<span className="text-gray-400">Supabase error:</span>{' '}
									{adminProbeError.code ? `${adminProbeError.code}: ` : ''}
									{adminProbeError.message}
								</div>
							) : null}
						</div>
					</div>
					<div className="mt-4 rounded-xl border border-white/10 bg-black/20 p-4 text-sm text-gray-200">
						<div className="font-medium">Fix</div>
						<ol className="mt-2 list-decimal space-y-1 pl-5 text-gray-300">
							<li>Preferred: promote your Firebase UID in <code className="rounded bg-black/30 px-1">public.profiles</code> with <code className="rounded bg-black/30 px-1">is_admin=true</code> and a valid <code className="rounded bg-black/30 px-1">admin_role</code>.</li>
							<li>Alternative: apply the admin RBAC migrations in your Supabase project (tables/view: <code className="rounded bg-black/30 px-1">public.admins</code>, <code className="rounded bg-black/30 px-1">public.admin_role_permissions</code>, <code className="rounded bg-black/30 px-1">public.admins_with_permissions</code>).</li>
							<li>Then: insert your email into <code className="rounded bg-black/30 px-1">public.admins</code> with <code className="rounded bg-black/30 px-1">status=&apos;active&apos;</code> and a valid <code className="rounded bg-black/30 px-1">role</code>.</li>
							<li>Confirm your Vercel env vars include <code className="rounded bg-black/30 px-1">SUPABASE_SERVICE_ROLE_KEY</code> for server reads under RLS.</li>
						</ol>
					</div>
					<div className="mt-4 flex gap-3">
						<Link href="/auth/login" className="rounded-xl border border-white/10 bg-white/5 px-4 py-2 text-sm hover:bg-white/10">
							Back to login
						</Link>
						<Link href="/admin/dashboard" className="rounded-xl bg-white px-4 py-2 text-sm font-medium text-black hover:bg-white/90">
							Reload
						</Link>
					</div>
				</div>
			</div>
		)
	}

	return (
		<div className="h-screen bg-zinc-950 text-white">
			<AdminDrawerEffects />
			<input id="admin-nav" type="checkbox" className="peer sr-only" />

			{/* Mobile overlay (tap outside to close) */}
			<label
				htmlFor="admin-nav"
				className="fixed inset-0 z-40 bg-black/60 opacity-0 pointer-events-none transition-opacity peer-checked:opacity-100 peer-checked:pointer-events-auto md:hidden"
				aria-label="Close navigation"
			/>

			{/* Sidebar: fixed on desktop, drawer on mobile */}
			<div className="fixed inset-y-0 left-0 z-50 w-64 -translate-x-full transition-transform peer-checked:translate-x-0 md:translate-x-0">
				<Sidebar />
			</div>

			{/* Main area */}
			<div className="flex h-screen flex-col md:pl-64">
				<TopBar />
				<main className="flex-1 p-4 md:p-6 overflow-y-auto overflow-x-auto">
					{children}
				</main>
			</div>
		</div>
	)
}
