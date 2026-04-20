import * as dotenv from 'dotenv'

dotenv.config({ path: '.env.local' })

async function main() {
	const { getFirebaseAdminAuth } = await import(new URL('../lib/firebase/admin.ts', import.meta.url).href)
	const adminAuth = getFirebaseAdminAuth()

	const { users } = await adminAuth.listUsers(1)
	console.log('Firebase Admin is working. Sample users:', users.map((u) => ({ uid: u.uid, email: u.email })))
}

main().catch((err) => {
	console.error('Firebase Admin error:', err)
	process.exit(1)
})
