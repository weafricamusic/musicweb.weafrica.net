import * as dotenv from 'dotenv'

dotenv.config({ path: '.env.local' })

const email = process.argv[2]
const password = process.argv[3]
const role = (process.argv[4] ?? 'super_admin') as 'admin' | 'super_admin'

if (!email || !password) {
	console.error('Usage: npx ts-node --esm firebase/bootstrap-admin.ts <email> <password> [admin|super_admin]')
	process.exit(1)
}

if (role !== 'admin' && role !== 'super_admin') {
	console.error('Role must be admin or super_admin')
	process.exit(1)
}

if (password.length < 6) {
	console.error('Password must be at least 6 characters (Firebase Auth requirement).')
	process.exit(1)
}

async function main() {
	const { getFirebaseAdminAuth } = await import(new URL('../lib/firebase/admin.ts', import.meta.url).href)
	const adminAuth = getFirebaseAdminAuth()

	function isFirebaseAuthError(err: unknown): err is { errorInfo?: { code?: string } } {
		return typeof err === 'object' && err !== null && 'errorInfo' in err
	}

	let user
	try {
		user = await adminAuth.getUserByEmail(email)
	} catch (err: unknown) {
		if (isFirebaseAuthError(err) && err.errorInfo?.code === 'auth/user-not-found') {
			user = await adminAuth.createUser({ email, password })
		} else {
			throw err
		}
	}

	await adminAuth.setCustomUserClaims(user.uid, { admin_role: role })
	console.log(`Bootstrap complete: email=${email} uid=${user.uid} admin_role=${role}`)
	console.log('Next: sign in at /login with this email/password, then open /dashboard.')
}

main().catch((err) => {
	console.error('Error:', err)
	process.exit(1)
})
