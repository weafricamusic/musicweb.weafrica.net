import type { NextRequest } from 'next/server'
import { GET as verificationGet } from '../verification/artists/route'

export const runtime = 'nodejs'

// Alias: admin artists listing is currently served by /api/admin/verification/artists.
export async function GET(req: NextRequest) {
	return verificationGet(req)
}
