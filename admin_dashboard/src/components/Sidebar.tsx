"use client"

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useState } from 'react'
import { LogoutButton } from '@/components/LogoutButton'

type SidebarItem = {
	href: string
	label: string
}

export function Sidebar({ items }: { items: SidebarItem[] }) {
	const pathname = usePathname()
	const [open, setOpen] = useState(false)

	return (
		<aside className="w-full border-b border-black/[.08] bg-white p-4 dark:border-white/[.145] dark:bg-black md:w-64 md:border-b-0 md:border-r">
			<div className="flex items-center justify-between md:hidden">
				<p className="text-sm font-medium text-zinc-700 dark:text-zinc-200">Menu</p>
				<button
					type="button"
					onClick={() => setOpen((v) => !v)}
					className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm dark:border-white/[.145]"
				>
					{open ? 'Close' : 'Open'}
				</button>
			</div>

			<nav className={open ? 'mt-3 block' : 'hidden md:block'}>
				<ul className="flex flex-col gap-2">
					{items.map((item) => {
						const isActive = pathname === item.href || pathname.startsWith(item.href + '/')
						return (
							<li key={item.href}>
								<Link
									href={item.href}
									className={
										'inline-flex h-10 w-full items-center rounded-xl px-3 text-sm transition ' +
										(isActive
											? 'bg-black/[.06] text-black dark:bg-white/[.10] dark:text-white'
											: 'text-zinc-700 hover:bg-black/[.04] dark:text-zinc-200 dark:hover:bg-white/[.08]')
									}
									onClick={() => setOpen(false)}
								>
									{item.label}
								</Link>
							</li>
						)
					})}
				</ul>

				<div className="mt-4 border-t border-black/[.08] pt-4 dark:border-white/[.145]">
					<LogoutButton />
				</div>
			</nav>
		</aside>
	)
}
