import Link from 'next/link'

export function StatCard(props: { title: string; value: string; sub?: string; href?: string }) {
	const inner = (
		<div className="rounded-2xl border border-black/[.08] bg-white p-5 transition hover:bg-black/[.02] dark:border-white/[.145] dark:bg-black dark:hover:bg-white/[.04]">
			<p className="text-sm text-zinc-600 dark:text-zinc-400">{props.title}</p>
			<p className="mt-2 text-2xl font-semibold">{props.value}</p>
			{props.sub ? <p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">{props.sub}</p> : null}
		</div>
	)
	return props.href ? <Link href={props.href}>{inner}</Link> : inner
}
