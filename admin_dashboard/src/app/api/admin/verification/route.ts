import { json, requireAdmin } from '../_utils'

export const runtime = 'nodejs'

export async function GET() {
	const { res } = await requireAdmin()
	if (res) return res
	return json({
		ok: true,
		endpoints: {
			artists: '/api/admin/verification/artists?bucket=pending|approved|rejected',
			djs: '/api/admin/verification/djs?bucket=pending|approved|rejected',
		},
	})
}
