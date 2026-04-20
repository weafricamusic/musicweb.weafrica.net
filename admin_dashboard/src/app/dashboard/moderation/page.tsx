import { redirect } from 'next/navigation'

export const runtime = 'nodejs'

export default function ModerationPage() {
	// Legacy module lives under /admin/moderation for now.
	redirect('/admin/moderation')
}
