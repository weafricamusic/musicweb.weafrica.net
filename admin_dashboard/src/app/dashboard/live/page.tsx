import { redirect } from 'next/navigation'

export const runtime = 'nodejs'

export default function LivePage() {
	// Legacy module lives under /admin/live-streams for now.
	redirect('/admin/live-streams')
}
