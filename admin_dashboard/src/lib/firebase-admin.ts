import 'server-only'

import { getFirebaseAdminAuth } from '@/lib/firebase/admin'

// Server-only helper.
// IMPORTANT: do not initialize Firebase Admin at module import time.
// Next.js may evaluate server modules during build/SSR; missing creds would crash builds.
export function getAdminAuth() {
	return getFirebaseAdminAuth()
}
