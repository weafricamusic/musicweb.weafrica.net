'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import type { ReactNode } from 'react'

export default function NavItem({
  label,
  href,
  className,
  icon,
}: {
  label: string
  href: string
  className?: string
  icon?: ReactNode
}) {
  const pathname = usePathname()
  const active = pathname === href || (href !== '/admin/dashboard' && pathname.startsWith(href))

	function closeDrawerIfOpen() {
		const el = document.getElementById('admin-nav') as HTMLInputElement | null
		if (el) el.checked = false
	}

  return (
    <Link
      href={href}
      className={
        'flex items-center gap-2 rounded-lg px-4 py-2 text-[13px] transition ' +
        (active ? 'bg-white/15 text-white' : 'text-zinc-200 hover:bg-white/10') +
        (className ? ` ${className}` : '')
      }
      aria-current={active ? 'page' : undefined}
		onClick={closeDrawerIfOpen}
    >
			{icon ? <span className={active ? 'text-white' : 'text-zinc-400'}>{icon}</span> : null}
      <span className="truncate">{label}</span>
    </Link>
  )
}
