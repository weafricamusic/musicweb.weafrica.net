import type { NextRequest } from 'next/server'
import { GET as promotionsGET } from '../promotions/route'

export const runtime = 'nodejs'

// Back-compat alias for consumer builds that call /api/promotion.
export async function GET(req: NextRequest) {
	return promotionsGET(req)
}
