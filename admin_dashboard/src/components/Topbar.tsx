import { LogoutButton } from '@/components/LogoutButton'

export function Topbar({ userEmail }: { userEmail: string }) {
	return (
		<header className="sticky top-0 z-10 border-b border-black/[.08] bg-zinc-50/80 px-6 py-4 backdrop-blur dark:border-white/[.145] dark:bg-black/60">
			<div className="flex items-center justify-between gap-4">
				<div className="min-w-0">
					<p className="truncate text-xs text-zinc-600 dark:text-zinc-400">Signed in as {userEmail}</p>
				</div>
				<LogoutButton />
			</div>
		</header>
	)
}
