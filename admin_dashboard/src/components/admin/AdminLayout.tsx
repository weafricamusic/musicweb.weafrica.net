import type { ReactNode } from 'react'
import Sidebar from '@/components/admin/Sidebar'
import TopBar from '@/components/admin/TopBar'

export function AdminLayout({ children }: { children: ReactNode }) {
	return (
		<div className="min-h-screen bg-black text-zinc-100">
			<TopBar />
			<div className="mx-auto flex max-w-6xl flex-col md:flex-row">
				<Sidebar />
				<main className="flex-1 p-6">{children}</main>
			</div>
		</div>
	)
}
