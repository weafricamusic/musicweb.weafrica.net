import Link from 'next/link'

export function Navbar({ title }: { title: string }) {
	return (
		<header className="flex h-14 items-center justify-between border-b border-black/[.08] bg-white px-4 dark:border-white/[.145] dark:bg-black">
			<div className="flex items-center gap-3">
				<Link href="/dashboard" className="text-sm font-semibold">
					{title}
				</Link>
			</div>
		</header>
	)
}
