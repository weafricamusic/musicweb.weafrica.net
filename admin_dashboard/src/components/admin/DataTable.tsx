'use client'

import { ReactNode, useEffect, useMemo, useState } from 'react'

type SortDir = 'asc' | 'desc'

export type DataTableColumn<Row> = {
	/** Unique id for sorting */
	id: string
	header: string
	/** Value used for sorting/searching if render isn't provided */
	accessor?: keyof Row
	/** Custom cell renderer */
	render?: (row: Row) => ReactNode
	/** Custom sort value */
	sortValue?: (row: Row) => string | number | boolean | Date | null | undefined
	/** Include in global search */
	searchable?: boolean
	/** Optional className for <td> */
	className?: string
}

export type DataTableFilter<Row> = {
	id: string
	label: string
	options: Array<{ value: string; label: string }>
	getValue: (row: Row) => string
}

function toSortablePrimitive(value: unknown): string | number {
	if (value == null) return ''
	if (value instanceof Date) return value.getTime()
	if (typeof value === 'number') return value
	if (typeof value === 'boolean') return value ? 1 : 0
	return String(value).toLowerCase()
}

export function DataTable<Row>(props: {
	rows: Row[]
	columns: Array<DataTableColumn<Row>>
	rowIdKey: keyof Row
	searchPlaceholder?: string
	filters?: Array<DataTableFilter<Row>>
	emptyMessage?: string
	pageSize?: number
	initialSort?: { columnId: string; dir: SortDir } | null
}) {
	const { rows, columns, rowIdKey, searchPlaceholder, filters, emptyMessage, pageSize = 25, initialSort = null } = props
	const [query, setQuery] = useState('')
	const [activeFilters, setActiveFilters] = useState<Record<string, string>>({})
	const [sort, setSort] = useState<{ columnId: string; dir: SortDir } | null>(initialSort)
	const [page, setPage] = useState(1)

	const searchableColumns = useMemo(
		() => columns.filter((c) => c.searchable !== false),
		[columns],
	)

	const filtered = useMemo(() => {
		const q = query.trim().toLowerCase()
		return rows.filter((row) => {
			if (filters?.length) {
				for (const f of filters) {
					const selected = activeFilters[f.id]
					if (!selected) continue
					if (f.getValue(row) !== selected) return false
				}
			}

			if (!q) return true
			const haystack = searchableColumns
				.map((c) => {
					if (c.accessor) {
						const v = row[c.accessor]
						return v == null ? '' : String(v)
					}
					return ''
				})
				.join(' | ')
				.toLowerCase()
			return haystack.includes(q)
		})
	}, [rows, query, filters, activeFilters, searchableColumns])

	useEffect(() => {
		function resetToFirstPage() {
			setPage(1)
		}
		resetToFirstPage()
	}, [query, activeFilters])

	const sorted = useMemo(() => {
		if (!sort) return filtered
		const col = columns.find((c) => c.id === sort.columnId)
		if (!col) return filtered
		const dirMult = sort.dir === 'asc' ? 1 : -1
		return [...filtered].sort((a, b) => {
			const av = col.sortValue
				? col.sortValue(a)
				: col.accessor
					? (a[col.accessor] as unknown)
					: undefined
			const bv = col.sortValue
				? col.sortValue(b)
				: col.accessor
					? (b[col.accessor] as unknown)
					: undefined
			const ap = toSortablePrimitive(av)
			const bp = toSortablePrimitive(bv)
			if (ap < bp) return -1 * dirMult
			if (ap > bp) return 1 * dirMult
			return 0
		})
	}, [filtered, sort, columns])

	const totalRows = sorted.length
	const totalPages = Math.max(1, Math.ceil(totalRows / pageSize))
	const currentPage = Math.min(page, totalPages)
	const startIndex = (currentPage - 1) * pageSize
	const endIndexExclusive = Math.min(startIndex + pageSize, totalRows)
	const paged = useMemo(() => sorted.slice(startIndex, endIndexExclusive), [sorted, startIndex, endIndexExclusive])

	function toggleSort(columnId: string) {
		setSort((prev) => {
			if (!prev || prev.columnId !== columnId) return { columnId, dir: 'asc' }
			return { columnId, dir: prev.dir === 'asc' ? 'desc' : 'asc' }
		})
	}

	return (
		<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
			<div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
				<div className="flex-1">
					<label className="block text-sm text-zinc-600 dark:text-zinc-400">Search</label>
					<input
						value={query}
						onChange={(e) => setQuery(e.target.value)}
						placeholder={searchPlaceholder ?? 'Search…'}
						className="mt-1 h-10 w-full rounded-xl border border-black/[.08] bg-transparent px-3 text-sm outline-none focus:ring-2 focus:ring-black/10 dark:border-white/[.145] dark:focus:ring-white/10"
					/>
				</div>

				{filters?.length ? (
					<div className="flex flex-wrap gap-3">
						{filters.map((f) => (
							<div key={f.id}>
								<label className="block text-sm text-zinc-600 dark:text-zinc-400">{f.label}</label>
								<select
									value={activeFilters[f.id] ?? ''}
									onChange={(e) => setActiveFilters((s) => ({ ...s, [f.id]: e.target.value }))}
									className="mt-1 h-10 rounded-xl border border-black/[.08] bg-transparent px-3 text-sm dark:border-white/[.145]"
								>
									<option value="">All</option>
									{f.options.map((o) => (
										<option key={o.value} value={o.value}>
											{o.label}
										</option>
									))}
								</select>
							</div>
						))}
					</div>
				) : null}
			</div>

			<div className="mt-4 overflow-auto">
				<table className="w-full min-w-[820px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-zinc-600 dark:text-zinc-400">
							{columns.map((c) => {
								const isSorted = sort?.columnId === c.id
								const label = isSorted ? `${c.header} (${sort?.dir})` : c.header
								return (
									<th
										key={c.id}
										className="border-b border-black/[.08] py-3 pr-4 font-medium dark:border-white/[.145]"
									>
										<button
											type="button"
											onClick={() => toggleSort(c.id)}
											className="inline-flex items-center gap-2 hover:text-black dark:hover:text-white"
											title="Sort"
										>
											<span>{label}</span>
											{isSorted ? <span className="text-xs">{sort?.dir === 'asc' ? '▲' : '▼'}</span> : null}
										</button>
									</th>
								)
							})}
						</tr>
					</thead>
					<tbody>
						{paged.length ? (
							paged.map((row) => (
								<tr key={String(row[rowIdKey])}>
									{columns.map((c) => {
										const content = c.render
											? c.render(row)
											: c.accessor
												? ((row[c.accessor] as unknown) ?? '—')
												: '—'
										return (
											<td
												key={c.id}
												className={`border-b border-black/[.08] py-3 pr-4 align-top dark:border-white/[.145] ${
													c.className ?? ''
												}`}
											>
												{content as any}
											</td>
										)
									})}
								</tr>
							))
						) : (
							<tr>
								<td className="py-6 text-sm text-zinc-600 dark:text-zinc-400" colSpan={columns.length}>
									{emptyMessage ?? 'No results.'}
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>

			{totalRows > pageSize ? (
				<div className="mt-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
					<p className="text-xs text-zinc-600 dark:text-zinc-400">
						Showing {startIndex + 1}-{endIndexExclusive} of {totalRows}
					</p>
					<div className="flex items-center gap-2">
						<button
							type="button"
							disabled={currentPage <= 1}
							onClick={() => setPage((p) => Math.max(1, p - 1))}
							className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
						>
							Prev
						</button>
						<span className="text-xs text-zinc-600 dark:text-zinc-400">
							Page {currentPage} / {totalPages}
						</span>
						<button
							type="button"
							disabled={currentPage >= totalPages}
							onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
							className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
						>
							Next
						</button>
					</div>
				</div>
			) : null}
		</div>
	)
}
