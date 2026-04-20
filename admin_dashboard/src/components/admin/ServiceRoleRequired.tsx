import Link from 'next/link'
import { getSupabaseServerEnvDebug } from '@/lib/supabase/server'

export default function ServiceRoleRequired(props: {
	title?: string
	description?: string
	suggestDebugEndpoint?: boolean
}) {
	const title = props.title ?? 'Service role required'
	const description =
		props.description ??
		'Set SUPABASE_SERVICE_ROLE_KEY (server-only) and restart/redeploy. Admin pages and admin APIs bypass RLS via the service role key. Local dev helper (repo root): npm run admin:setup:supabase -- --service-from-clipboard'

	const env = (() => {
		try {
			return getSupabaseServerEnvDebug()
		} catch {
			return null
		}
	})()

	return (
		<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
			<div className="font-semibold">{title}</div>
			<p className="mt-1">{description}</p>
			{env && process.env.NODE_ENV !== 'production' ? (
				<p className="mt-2 text-xs text-amber-200/90">
					Env check: urlHost={env.urlHost} keyMode={env.keyMode} refMismatch={String(env.refMismatch)}
				</p>
			) : null}
			{props.suggestDebugEndpoint === false || process.env.NODE_ENV === 'production' ? null : (
				<p className="mt-2 text-xs text-amber-200/90">
					Debug endpoint:{' '}
					<Link className="underline" href="/api/admin/supabase-env-debug">
						/api/admin/supabase-env-debug
					</Link>
				</p>
			)}
		</div>
	)
}
