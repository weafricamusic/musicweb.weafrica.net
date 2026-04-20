import { ReactNode } from 'react'

export function DashboardShell({ title, children }: { title: string; children: ReactNode }) {
	return (
		<div className="space-y-6">
			<h1 className="text-xl font-semibold">{title}</h1>
			<div>{children}</div>
		</div>
	)
}
