function isPlainRecord(value: unknown): value is Record<string, unknown> {
	return value != null && typeof value === 'object' && !Array.isArray(value)
}

export function mergeRecordsDeep<T extends Record<string, unknown>>(
	base: T | null | undefined,
	override: Record<string, unknown> | null | undefined,
): T | Record<string, unknown> | undefined {
	if (!isPlainRecord(base) && !isPlainRecord(override)) return undefined
	if (!isPlainRecord(base)) return override ? { ...override } : undefined
	if (!isPlainRecord(override)) return { ...base }

	const merged: Record<string, unknown> = { ...base }
	for (const [key, value] of Object.entries(override)) {
		const current = merged[key]
		merged[key] = isPlainRecord(current) && isPlainRecord(value)
			? mergeRecordsDeep(current, value)
			: value
	}

	return merged
}