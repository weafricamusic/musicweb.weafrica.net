import type { ReactNode } from 'react'

export default function StatsCard(props: {
	title: string
	value: ReactNode
	hint?: string
}) {
	return (
		<div className="rounded-xl border border-zinc-800 bg-zinc-900/40 p-4 shadow-sm">
			<span className="text-sm text-zinc-400">{props.title}</span>
			<div className="mt-1 text-2xl font-semibold tracking-tight">{props.value}</div>
			{props.hint ? <div className="mt-1 text-xs text-zinc-400">{props.hint}</div> : null}
		</div>
	)
}
