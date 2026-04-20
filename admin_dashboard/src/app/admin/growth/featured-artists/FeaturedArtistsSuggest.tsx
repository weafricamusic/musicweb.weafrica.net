'use client'

import { useCallback, useMemo, useState } from 'react'

type Suggestion = {
	artist_id: string
	label: string
	reason: string
	priority: number
	country_code: string | null
}

type Props = {
	addFeaturedAction: (formData: FormData) => Promise<void>
	defaultCountryCode?: string
}

export default function FeaturedArtistsSuggest({ addFeaturedAction, defaultCountryCode }: Props) {
	const [countryCode, setCountryCode] = useState<string>(defaultCountryCode ?? '')
	const [limit, setLimit] = useState<number>(10)
	const [useAi, setUseAi] = useState<boolean>(false)
	const [loading, setLoading] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [suggestions, setSuggestions] = useState<Suggestion[]>([])
	const [provider, setProvider] = useState<string>('free-heuristic')
	const [warning, setWarning] = useState<string | null>(null)

	const canFetch = useMemo(() => !loading, [loading])

	const fetchSuggestions = useCallback(async () => {
		if (!canFetch) return
		setLoading(true)
		setError(null)
		setWarning(null)
		try {
			const params = new URLSearchParams()
			params.set('limit', String(Math.max(1, Math.min(50, Number(limit) || 10))))
			const cc = (countryCode ?? '').trim().toUpperCase()
			if (cc) params.set('country_code', cc)
			if (useAi) params.set('provider', 'huggingface')
			const res = await fetch(`/api/admin/growth/featured-artists/suggest?${params.toString()}`, {
				method: 'GET',
				headers: { 'accept': 'application/json' },
				cache: 'no-store',
			})
			const data = (await res.json().catch(() => null)) as any
			if (!res.ok) throw new Error(String(data?.error ?? `Request failed (${res.status})`))
			setProvider(String(data?.provider ?? 'free-heuristic'))
			setWarning(typeof data?.warning === 'string' && data.warning ? data.warning : null)
			const list = Array.isArray(data?.suggestions) ? (data.suggestions as Suggestion[]) : []
			setSuggestions(list)
		} catch (e) {
			setSuggestions([])
			setProvider('free-heuristic')
			setError(e instanceof Error ? e.message : 'Failed to fetch suggestions')
		} finally {
			setLoading(false)
		}
	}, [canFetch, countryCode, limit, useAi])

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
				<div>
					<h2 className="text-base font-semibold">Auto-suggest Featured Artists (free)</h2>
					<p className="mt-1 text-xs text-gray-400">
						Provider: <span className="font-mono text-gray-300">{provider}</span>. You can still edit country & priority before adding.
					</p>
					<p className="mt-1 text-xs text-gray-500">
						Tip: enable “AI” to rerank using Hugging Face (requires server env vars). If not configured, it will fall back automatically.
					</p>
				</div>
				<div className="flex flex-wrap items-center justify-end gap-2">
					<label className="inline-flex h-10 items-center gap-2 rounded-xl border border-white/10 bg-black/10 px-3 text-xs text-gray-300">
						<input
							type="checkbox"
							checked={useAi}
							onChange={(e) => setUseAi(e.target.checked)}
							className="h-4 w-4"
						/>
						Use AI
					</label>
					<input
						value={countryCode}
						onChange={(e) => setCountryCode(e.target.value)}
						placeholder="Country (MW)"
						className="h-10 w-28 rounded-xl border border-white/10 bg-black/20 px-3 text-sm uppercase outline-none placeholder:text-gray-500 focus:border-white/20"
					/>
					<input
						value={String(limit)}
						onChange={(e) => setLimit(Number(e.target.value) || 10)}
						placeholder="Limit"
						type="number"
						min={1}
						max={50}
						className="h-10 w-24 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none placeholder:text-gray-500 focus:border-white/20"
					/>
					<button
						onClick={fetchSuggestions}
						disabled={loading}
						className="inline-flex h-10 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-sm hover:bg-white/10 disabled:opacity-60"
					>
						{loading ? 'Loading…' : 'Suggest'}
					</button>
				</div>
			</div>

			{error ? (
				<div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error}</div>
			) : null}

			{warning ? (
				<div className="mt-4 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-100">{warning}</div>
			) : null}

			{suggestions.length ? (
				<div className="mt-4 overflow-auto">
					<div className="min-w-[900px]">
						<div className="grid grid-cols-12 gap-3 border-b border-white/10 pb-2 text-xs text-gray-400">
							<div className="col-span-4">Artist</div>
							<div className="col-span-3">Reason</div>
							<div className="col-span-2">Country</div>
							<div className="col-span-1">Priority</div>
							<div className="col-span-2 text-right">Action</div>
						</div>

						{suggestions.map((s) => (
							<div key={s.artist_id} className="grid grid-cols-12 gap-3 border-b border-white/5 py-3 text-sm">
								<div className="col-span-4">
									<div className="font-medium">{s.label}</div>
									<div className="mt-1 font-mono text-[11px] text-gray-500">{s.artist_id}</div>
								</div>
								<div className="col-span-3 text-xs text-gray-400">{s.reason}</div>
								<div className="col-span-2">
									<span className="text-gray-300">{s.country_code ?? '—'}</span>
								</div>
								<div className="col-span-1">
									<span className="text-gray-300">{s.priority}</span>
								</div>
								<div className="col-span-2 flex justify-end">
									<form action={addFeaturedAction} className="flex items-center gap-2">
										<input type="hidden" name="artist_id" value={s.artist_id} />
										<input type="hidden" name="country_code" value={s.country_code ?? ''} />
										<input type="hidden" name="priority" value={String(s.priority ?? 0)} />
										<button className="inline-flex h-9 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-xs hover:bg-white/10">
											Add
										</button>
									</form>
								</div>
							</div>
						))}
					</div>
				</div>
			) : (
				<p className="mt-4 text-sm text-gray-400">No suggestions yet. Click “Suggest”.</p>
			)}
		</div>
	)
}
