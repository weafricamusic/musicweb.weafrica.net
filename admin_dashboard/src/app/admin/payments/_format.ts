export function formatMWK(value: number | string | null | undefined): string {
	const n = typeof value === 'string' ? Number(value) : typeof value === 'number' ? value : 0
	const safe = Number.isFinite(n) ? n : 0
	// Malawi currency first
	return new Intl.NumberFormat('en-MW', {
		style: 'currency',
		currency: 'MWK',
		maximumFractionDigits: 0,
	}).format(safe)
}

export function formatInt(value: number | string | null | undefined): string {
	const n = typeof value === 'string' ? Number(value) : typeof value === 'number' ? value : 0
	const safe = Number.isFinite(n) ? n : 0
	return new Intl.NumberFormat('en-MW', { maximumFractionDigits: 0 }).format(safe)
}
