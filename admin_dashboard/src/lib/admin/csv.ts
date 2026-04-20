import 'server-only'

export type CsvValue = string | number | boolean | null | undefined

function escapeCell(value: CsvValue): string {
	if (value == null) return ''
	const raw = typeof value === 'string' ? value : typeof value === 'number' ? String(value) : value ? 'true' : 'false'
	if (raw.includes('"') || raw.includes(',') || raw.includes('\n') || raw.includes('\r')) {
		return `"${raw.replaceAll('"', '""')}"`
	}
	return raw
}

export function toCsv(headers: string[], rows: Array<Record<string, CsvValue>>): string {
	const out: string[] = []
	out.push(headers.map((h) => escapeCell(h)).join(','))
	for (const row of rows) {
		out.push(headers.map((h) => escapeCell(row[h])).join(','))
	}
	return out.join('\n') + '\n'
}
