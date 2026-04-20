import * as dotenv from 'dotenv'

dotenv.config({ path: '.env.local' })

const identifier = process.argv[2]
const role = (process.argv[3] ?? 'admin') as 'admin' | 'super_admin'

if (!identifier) {
	console.error('Usage: npx ts-node firebase/seed-admin.ts <uid|email> [admin|super_admin]')
	process.exit(1)
}

if (role !== 'admin' && role !== 'super_admin') {
	console.error('Role must be admin or super_admin')
	process.exit(1)
}

async function main() {
	const { getFirebaseAdminAuth } = await import(new URL('../lib/firebase/admin.ts', import.meta.url).href)
	const firebaseAdminAuth = getFirebaseAdminAuth()
	const uid = identifier.includes('@')
		? (await firebaseAdminAuth.getUserByEmail(identifier)).uid
		: identifier

	await firebaseAdminAuth.setCustomUserClaims(uid, { admin_role: role })
	console.log(`Set Firebase custom claim: uid=${uid} admin_role=${role}`)
	console.log('Note: user must re-login (or refresh token) to receive updated claims.')
}

main().catch((err) => {
	console.error('Error:', err)
	process.exit(1)
})
