export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET() {
	return Response.json({
		ok: true,
		base: '/api/admin',
		endpoints: [
			'/users',
			'/artists',
			'/djs',
			'/verification',
			'/subscriptions',
			'/payments',
			'/coins',
			'/payouts',
			'/tracks',
			'/videos',
			'/moderation',
			'/live',
			'/battles',
			'/growth',
			'/notifications',
			'/analytics',
			'/features',
			'/settings',
			'/audit-logs',
		],
	})
}
