import type { NextRequest } from 'next/server'
import { GET as verificationGet } from '../verification/djs/route'

export const runtime = 'nodejs'

// Alias: admin DJs listing is currently served by /api/admin/verification/djs.
export async function GET(req: NextRequest) {
	return verificationGet(req)
}
