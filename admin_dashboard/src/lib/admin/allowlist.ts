import 'server-only'

function splitCsv(value: string): string[] {
	return value
		.split(',')
		.map((s) => s.trim().toLowerCase())
		.filter(Boolean)
}

export function getAdminEmailAllowlist(): string[] {
	const raw = process.env.ADMIN_EMAILS
	if (!raw) return []
	return splitCsv(raw)
}

export function isAdminEmailAllowed(email: string | null | undefined): boolean {
	if (!email) return false
	const allowlist = getAdminEmailAllowlist()
	if (!allowlist.length) return false
	return allowlist.includes(email.trim().toLowerCase())
}

export function assertAdminAllowlistConfigured() {
	const allowlist = getAdminEmailAllowlist()
	if (!allowlist.length) {
		throw new Error('ADMIN_EMAILS is not configured. Set a comma-separated allowlist of admin emails.')
	}
}
