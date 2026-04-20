import { initializeApp, getApps } from 'firebase/app'
import { getAuth, type Auth } from 'firebase/auth'

let cachedAuth: Auth | null = null

function envTrim(value: string | undefined) {
	// Normalize common copy/paste mistakes from env dashboards:
	// - wrapping quotes
	// - trailing/leading whitespace and accidental newlines
	return (value ?? '')
		.trim()
		.replace(/^['"]|['"]$/g, '')
		.replace(/\\[rn]/g, '')
		.replace(/\s+/g, '')
}

export function getFirebaseAuth(): Auth {
	if (cachedAuth) return cachedAuth

	// IMPORTANT: in client bundles, Next.js only exposes NEXT_PUBLIC_* env vars
	// when accessed via static property reads (not process.env[dynamicKey]).
	const apiKey = envTrim(process.env.NEXT_PUBLIC_FIREBASE_API_KEY)
	const authDomain = envTrim(process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN)
	const projectId = envTrim(process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID)
	const storageBucket = envTrim(process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET)
	const messagingSenderId = envTrim(process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID)
	const appId = envTrim(process.env.NEXT_PUBLIC_FIREBASE_APP_ID)

	const missing: string[] = []
	if (!apiKey) missing.push('NEXT_PUBLIC_FIREBASE_API_KEY')
	if (!authDomain) missing.push('NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN')
	if (!projectId) missing.push('NEXT_PUBLIC_FIREBASE_PROJECT_ID')
	if (missing.length) {
		throw new Error(
			`Missing Firebase env vars: ${missing.join(
				', ',
			)}. Set them in local .env.local (copy from .env.example) and restart \`npm run dev\`, or set them in Vercel Environment Variables (Preview/Production) and redeploy.`,
		)
	}

	const firebaseConfig = {
		apiKey,
		authDomain,
		projectId,
		storageBucket: storageBucket || undefined,
		messagingSenderId: messagingSenderId || undefined,
		appId: appId || undefined,
	}

	const app = getApps().length ? getApps()[0]! : initializeApp(firebaseConfig)
	cachedAuth = getAuth(app)
	return cachedAuth
}
