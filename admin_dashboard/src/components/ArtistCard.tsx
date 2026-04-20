export function ArtistCard({ title, description }: { title: string; description: string }) {
	return (
		<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
			<h2 className="text-base font-semibold">{title}</h2>
			<p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
		</div>
	)
}
