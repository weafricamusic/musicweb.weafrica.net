import dotenv from 'dotenv'
import { readFileSync, existsSync } from 'node:fs'
import { isAbsolute, resolve } from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { cert, getApps, initializeApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'

// Mirror Next.js local dev behavior: read .env.local if present.
dotenv.config({ path: '.env.local', override: true })

function envValue(value) {
	if (!value) return null
	const trimmed = String(value).trim()
	if (!trimmed) return null
	// Some UIs wrap values in quotes. Strip one pair.
	return trimmed.replace(/^['"]|['"]$/g, '').trim() || null
}

function getEnv(name) {
	return envValue(process.env[name])
}

function getArg(flag) {
	const argv = process.argv.slice(2)
	const eq = argv.find((a) => a.startsWith(`${flag}=`))
	if (eq) return eq.slice(flag.length + 1)
	const i = argv.indexOf(flag)
	if (i >= 0) return argv[i + 1] ?? ''
	return ''
}

function hasFlag(flag) {
	const argv = process.argv.slice(2)
	return argv.includes(flag) || argv.some((a) => a.startsWith(`${flag}=`))
}

function parseIntArg(value, fallback) {
	const n = Number.parseInt(String(value ?? '').trim(), 10)
	return Number.isFinite(n) ? n : fallback
}

function jsonOut(data) {
	console.log(JSON.stringify(data, null, 2))
}

function looksLikeJson(value) {
	const t = String(value || '').trim()
	return t.startsWith('{') || t.startsWith('[')
}

function normalizeServiceAccount(sa) {
	if (!sa || typeof sa !== 'object') throw new Error('Firebase service account must be a JSON object')
	// Fix common env-var escaping: "\\n" instead of real newlines.
	if (typeof sa.private_key === 'string' && sa.private_key.includes('\\n')) {
		sa.private_key = sa.private_key.replace(/\\n/g, '\n')
	}
	if (typeof sa.privateKey === 'string' && sa.privateKey.includes('\\n')) {
		sa.privateKey = sa.privateKey.replace(/\\n/g, '\n')
	}
	return sa
}

function looksLikeServiceAccountObject(value) {
	if (!value || typeof value !== 'object') return false
	return (
		(typeof value.client_email === 'string' || typeof value.clientEmail === 'string') &&
		(typeof value.private_key === 'string' || typeof value.privateKey === 'string')
	)
}

function tryParseJsonServiceAccount(value) {
	try {
		const parsed = JSON.parse(String(value))
		if (!looksLikeServiceAccountObject(parsed)) return null
		return normalizeServiceAccount(parsed)
	} catch {
		return null
	}
}

function tryParseBase64JsonServiceAccount(value) {
	const trimmed = String(value || '').trim()
	if (trimmed.length < 64) return null
	if (!/^[A-Za-z0-9+/=_-]+$/.test(trimmed)) return null
	try {
		const decoded = Buffer.from(trimmed, 'base64').toString('utf8').trim()
		if (!looksLikeJson(decoded)) return null
		const parsed = JSON.parse(decoded)
		if (!looksLikeServiceAccountObject(parsed)) return null
		return normalizeServiceAccount(parsed)
	} catch {
		return null
	}
}

function resolvePath(rawPath) {
	if (!rawPath) return null
	const trimmed = String(rawPath).trim()
	if (!trimmed) return null
	return isAbsolute(trimmed) ? trimmed : resolve(process.cwd(), trimmed)
}

function getProjectIdFromEnv() {
	return (
		getEnv('FIREBASE_PROJECT_ID') ||
		getEnv('NEXT_PUBLIC_FIREBASE_PROJECT_ID') ||
		getEnv('GCLOUD_PROJECT') ||
		getEnv('GOOGLE_CLOUD_PROJECT') ||
		null
	)
}

function usingAuthEmulator() {
	return Boolean(getEnv('FIREBASE_AUTH_EMULATOR_HOST'))
}

function readServiceAccountFromEnvOrFile() {
	// Dev ergonomics: if a credential file path is provided, prefer it over JSON/BASE64.
	// This avoids surprises when stale FIREBASE_SERVICE_ACCOUNT_JSON/BASE64 is still exported in the shell.
	if (process.env.NODE_ENV !== 'production') {
		const rawPathOrInline = getEnv('FIREBASE_SERVICE_ACCOUNT_PATH') || getEnv('GOOGLE_APPLICATION_CREDENTIALS')
		if (rawPathOrInline) {
			// Detect common mistakes: JSON/base64 pasted into *_PATH.
			if (looksLikeJson(rawPathOrInline)) {
				const parsed = tryParseJsonServiceAccount(rawPathOrInline)
				if (parsed) return parsed
			} else {
				const parsedB64 = tryParseBase64JsonServiceAccount(rawPathOrInline)
				if (parsedB64) return parsedB64
			}

			const resolvedPath = resolvePath(rawPathOrInline)
			if (resolvedPath && existsSync(resolvedPath)) {
				const raw = readFileSync(resolvedPath, 'utf8')
				const parsed = JSON.parse(raw)
				if (!looksLikeServiceAccountObject(parsed)) {
					throw new Error('Service account JSON file is missing client_email/private_key')
				}
				return normalizeServiceAccount(parsed)
			}
		}
	}

	const json = getEnv('FIREBASE_SERVICE_ACCOUNT_JSON')
	if (json) {
		const parsed = tryParseJsonServiceAccount(json)
		if (!parsed) throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is set but not valid service account JSON')
		return parsed
	}

	const b64 = getEnv('FIREBASE_SERVICE_ACCOUNT_BASE64')
	if (b64) {
		const parsed = tryParseBase64JsonServiceAccount(b64)
		if (!parsed) throw new Error('FIREBASE_SERVICE_ACCOUNT_BASE64 is set but not valid base64-encoded service account JSON')
		return parsed
	}

	const rawPathOrInline = getEnv('FIREBASE_SERVICE_ACCOUNT_PATH') || getEnv('GOOGLE_APPLICATION_CREDENTIALS')
	if (rawPathOrInline) {
		if (looksLikeJson(rawPathOrInline)) {
			const parsed = tryParseJsonServiceAccount(rawPathOrInline)
			if (parsed) return parsed
			throw new Error(
				'FIREBASE_SERVICE_ACCOUNT_PATH/GOOGLE_APPLICATION_CREDENTIALS looks like JSON but is not valid. Use FIREBASE_SERVICE_ACCOUNT_JSON (single-line) or FIREBASE_SERVICE_ACCOUNT_BASE64 instead.',
			)
		}
		const parsedB64 = tryParseBase64JsonServiceAccount(rawPathOrInline)
		if (parsedB64) return parsedB64

		const resolvedPath = resolvePath(rawPathOrInline)
		if (resolvedPath && existsSync(resolvedPath)) {
			const raw = readFileSync(resolvedPath, 'utf8')
			const parsed = JSON.parse(raw)
			if (!looksLikeServiceAccountObject(parsed)) {
				throw new Error('Service account JSON file is missing client_email/private_key')
			}
			return normalizeServiceAccount(parsed)
		}
	}

	// Local dev fallback: if you have firebase-service-account.json in the repo root,
	// allow it without requiring env var wiring.
	if (process.env.NODE_ENV !== 'production') {
		const defaultPath = resolve(process.cwd(), 'firebase-service-account.json')
		if (existsSync(defaultPath)) {
			const raw = readFileSync(defaultPath, 'utf8')
			const parsed = JSON.parse(raw)
			if (!looksLikeServiceAccountObject(parsed)) {
				throw new Error('firebase-service-account.json is missing client_email/private_key')
			}
			return normalizeServiceAccount(parsed)
		}
	}

	return null
}

function getFirebaseAdminAuthOrThrow() {
	if (getApps().length) return getAuth(getApps()[0])

	if (usingAuthEmulator()) {
		const projectId = getProjectIdFromEnv()
		if (!projectId) {
			throw new Error(
				'Missing Firebase project id while using Auth Emulator. Set FIREBASE_PROJECT_ID (recommended) or NEXT_PUBLIC_FIREBASE_PROJECT_ID.',
			)
		}
		return getAuth(initializeApp({ projectId }))
	}

	const sa = readServiceAccountFromEnvOrFile()
	if (!sa) {
		throw new Error(
			'Missing Firebase Admin credentials. Set one of: FIREBASE_SERVICE_ACCOUNT_PATH (or GOOGLE_APPLICATION_CREDENTIALS), FIREBASE_SERVICE_ACCOUNT_JSON, FIREBASE_SERVICE_ACCOUNT_BASE64.',
		)
	}

	return getAuth(initializeApp({ credential: cert(sa) }))
}

function buildEndsAtIso(years) {
	const ms = Number(years) * 365 * 24 * 60 * 60 * 1000
	return new Date(Date.now() + ms).toISOString()
}

function inferArtistStageName(email) {
	const local = String(email || '').split('@')[0] || 'Artist'
	return local.replace(/\./g, ' ').replace(/\b\w/g, (m) => m.toUpperCase())
}

function inferDjName(email) {
	const local = String(email || '').split('@')[0] || 'DJ'
	return local.replace(/\./g, ' ').replace(/\b\w/g, (m) => m.toUpperCase())
}

async function ensureFirebaseUser(auth, args) {
	const email = String(args.email || '').trim()
	if (!email) throw new Error('Missing email')

	try {
		const user = await auth.getUserByEmail(email)
		return { ok: true, uid: user.uid, email, created: false }
	} catch (e) {
		const code = String(e?.code || '')
		if (!code.includes('user-not-found')) throw e
		if (args.dryRun) return { ok: true, uid: null, email, created: false, would_create: true }
		const password = String(args.password || '').trim()
		if (!password) {
			return {
				ok: false,
				email,
				error:
					`Firebase user ${email} not found, and no password provided. Set TEST_ACCOUNT_PASSWORD or pass --password to create it.`,
			}
		}

		const user = await auth.createUser({
			email,
			password,
			emailVerified: true,
			displayName: args.displayName || undefined,
		})
		return { ok: true, uid: user.uid, email, created: true }
	}
}

async function ensureFirebaseSubscriptionClaims(auth, args) {
	const uid = String(args.uid || '').trim()
	if (!uid) return { ok: false, error: 'Missing uid' }
	if (args.dryRun) return { ok: true, would_set: true }

	const payload = {
		sub_plan: String(args.planId || 'free'),
		sub_status: 'active',
	}
	if (args.endsAtIso) payload.sub_ends_at = String(args.endsAtIso)

	const user = await auth.getUser(uid)
	const current = user.customClaims || {}
	const next = { ...current, ...payload }
	if (!args.endsAtIso && 'sub_ends_at' in next) delete next.sub_ends_at
	await auth.setCustomUserClaims(uid, next)
	return { ok: true, set: true }
}

async function ensureCreatorRow(supabase, args) {
	const table = args.table
	const uid = String(args.uid || '').trim()
	if (!uid) return { ok: false, error: 'Missing uid' }

	const selectId = await supabase.from(table).select('id').eq('firebase_uid', uid).maybeSingle()
	if (selectId.error) {
		return { ok: false, error: selectId.error.message, code: selectId.error.code ?? null }
	}

	const existingId = selectId.data?.id ? String(selectId.data.id) : null
	if (args.dryRun) {
		return {
			ok: true,
			dry_run: true,
			would_update: Boolean(existingId),
			match: { id: existingId, firebase_uid: uid },
		}
	}

	const base = args.payload

	const attempts = Array.isArray(args.attempts) && args.attempts.length ? args.attempts : [base]
	let lastError = null
	for (const payload of attempts) {
		if (existingId) {
			const { data, error } = await supabase.from(table).update(payload).eq('id', existingId).select('*').maybeSingle()
			if (!error) return { ok: true, mode: 'update', row: data }
			lastError = error
		} else {
			const { data, error } = await supabase.from(table).insert(payload).select('*').maybeSingle()
			if (!error) return { ok: true, mode: 'insert', row: data }
			lastError = error
		}
	}
	return { ok: false, error: lastError?.message ?? 'Failed to write creator row', code: lastError?.code ?? null }
}

async function ensureAdminRow(supabase, args) {
	const email = String(args.email || '').trim()
	const uid = String(args.uid || '').trim()
	if (!email) return { ok: false, error: 'Missing email' }
	if (!uid) return { ok: false, error: 'Missing uid' }

	if (args.dryRun) return { ok: true, would_upsert: true }

	const base = {
		email,
		uid,
		role: 'super_admin',
		status: 'active',
		last_login_at: new Date().toISOString(),
	}

	const attempts = [
		base,
		(() => {
			const { last_login_at: _a, ...rest } = base
			return rest
		})(),
		(() => {
			const { uid: _u, last_login_at: _a, ...rest } = base
			return rest
		})(),
	]

	let lastError = null
	for (const payload of attempts) {
		const { data, error } = await supabase
			.from('admins')
			.upsert(payload, { onConflict: 'email' })
			.select('email,uid,role,status')
			.maybeSingle()
		if (!error) return { ok: true, admin: data ?? null }
		lastError = error
	}

	return { ok: false, error: lastError?.message ?? 'Failed to upsert admins row', code: lastError?.code ?? null }
}

async function ensureFullSubscription(supabase, args) {
	const uid = String(args.uid || '').trim()
	if (!uid) return { ok: false, error: 'Missing uid' }

	const planId = String(args.planId || '').trim()
	if (!planId) return { ok: false, error: 'Missing planId' }

	const endsAtIso = args.endsAtIso ? String(args.endsAtIso) : null
	const nowIso = new Date().toISOString()

	// Validate plan exists (helps catch missing migrations).
	const planCheck = await supabase.from('subscription_plans').select('plan_id').eq('plan_id', planId).maybeSingle()
	if (planCheck.error) {
		return { ok: false, error: planCheck.error.message, code: planCheck.error.code ?? null }
	}
	if (!planCheck.data) {
		return { ok: false, error: `subscription_plans missing plan_id=${planId}. Apply DB migrations first.` }
	}

	const existing = await supabase
		.from('user_subscriptions')
		.select('id,plan_id,status,ends_at,created_at')
		.eq('user_id', uid)
		.eq('status', 'active')
		.order('created_at', { ascending: false })
		.limit(1)
		.maybeSingle()

	if (existing.error) {
		return { ok: false, error: existing.error.message, code: existing.error.code ?? null }
	}

	const row = existing.data
	const desiredEndsAt = endsAtIso ? new Date(endsAtIso).getTime() : null
	const currentEndsAt = row?.ends_at ? new Date(String(row.ends_at)).getTime() : null
	const needsUpdate =
		!row ||
		row.plan_id !== planId ||
		(endsAtIso && (!currentEndsAt || (desiredEndsAt && currentEndsAt < desiredEndsAt - 60_000)))

	if (args.dryRun) {
		return {
			ok: true,
			dry_run: true,
			action: row ? (needsUpdate ? 'would_update' : 'noop') : 'would_insert',
			existing: row ?? null,
			desired: { plan_id: planId, ends_at: endsAtIso },
		}
	}

	if (row && !needsUpdate) {
		return { ok: true, action: 'noop', existing: row }
	}

	// Ensure no other actives (handles legacy duplicates before unique index).
	await supabase
		.from('user_subscriptions')
		.update({ status: 'replaced', updated_at: nowIso })
		.eq('user_id', uid)
		.eq('status', 'active')

	const insertPayload = {
		user_id: uid,
		plan_id: planId,
		status: 'active',
		started_at: nowIso,
		ends_at: endsAtIso,
		auto_renew: true,
		country_code: String(args.countryCode || 'MW'),
		source: String(args.source || 'ensure_test_accounts'),
		created_at: nowIso,
		updated_at: nowIso,
		meta: { seeded_by: 'scripts/ensure-test-accounts.mjs', reason: 'full_access_test' },
	}

	const inserted = await supabase.from('user_subscriptions').insert(insertPayload).select('id,plan_id,status,ends_at').maybeSingle()
	if (inserted.error) {
		return { ok: false, error: inserted.error.message, code: inserted.error.code ?? null }
	}

	return { ok: true, action: row ? 'replaced_active' : 'inserted', subscription: inserted.data ?? null }
}

function usage() {
	return {
		usage: 'node scripts/ensure-test-accounts.mjs --apply',
		examples: [
			'node scripts/ensure-test-accounts.mjs --dry-run',
			'TEST_ACCOUNT_PASSWORD="ChangeMe123!" node scripts/ensure-test-accounts.mjs --apply',
			'node scripts/ensure-test-accounts.mjs --apply --plan-id platinum --years 10',
		],
		flags: {
			'--apply/--yes': 'Actually write to Firebase + Supabase (default is dry-run).',
			'--dry-run': 'No writes; shows what would happen.',
			'--artist-email': 'Default artist1@weafrica.test',
			'--dj-email': 'Default dj1@weafrica.test',
			'--admin-email': 'Default admin@weafrica.test',
			'--plan-id': 'Default platinum',
			'--years': 'Subscription length (default 10)',
			'--ends-at': 'Explicit ISO timestamp for subscription ends_at',
			'--password': 'Password for creating missing Firebase users (or set TEST_ACCOUNT_PASSWORD)',
		},
	}
}

const artistEmail = (getArg('--artist-email') || getEnv('TEST_ARTIST_EMAIL') || 'artist1@weafrica.test').trim()
const djEmail = (getArg('--dj-email') || getEnv('TEST_DJ_EMAIL') || 'dj1@weafrica.test').trim()
const adminEmail = (getArg('--admin-email') || getEnv('TEST_ADMIN_EMAIL') || 'admin@weafrica.test').trim()

const planId = (getArg('--plan-id') || getEnv('TEST_PLAN_ID') || 'platinum').trim()
const years = parseIntArg(getArg('--years') || getEnv('TEST_SUBSCRIPTION_YEARS'), 10)
const endsAtIso = (getArg('--ends-at') || getEnv('TEST_SUBSCRIPTION_ENDS_AT') || '').trim() || buildEndsAtIso(years)

const password = (getArg('--password') || getEnv('TEST_ACCOUNT_PASSWORD') || '').trim()

const apply = hasFlag('--apply') || hasFlag('--yes')
const dryRun = hasFlag('--dry-run') || !apply

const url = getEnv('NEXT_PUBLIC_SUPABASE_URL')
const serviceRoleKey = getEnv('SUPABASE_SERVICE_ROLE_KEY')

if (!url || !serviceRoleKey) {
	jsonOut({ ok: false, error: 'Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY (set them in .env.local).', ...usage() })
	process.exit(1)
}

let auth
try {
	auth = getFirebaseAdminAuthOrThrow()
} catch (e) {
	jsonOut({ ok: false, error: String(e?.message || e), ...usage() })
	process.exit(1)
}

const supabase = createClient(url, serviceRoleKey, {
	auth: { persistSession: false, autoRefreshToken: false },
})

const warnings = []

const adminEmailsRaw = (getEnv('ADMIN_EMAILS') || '').split(',').map((s) => s.trim()).filter(Boolean)
if (!adminEmailsRaw.includes(adminEmail)) {
	warnings.push(
		`ADMIN_EMAILS does not include ${adminEmail}. Admin login via POST /api/auth/session will be denied until you allowlist it.`,
	)
}
if (!getEnv('ADMIN_GUARD_SECRET')) {
	warnings.push('ADMIN_GUARD_SECRET is not set. Admin session guard cookie cannot be created.')
}

try {
	const accounts = {}

	// 1) Ensure Firebase users exist
	const artistFirebase = await ensureFirebaseUser(auth, {
		email: artistEmail,
		password,
		displayName: inferArtistStageName(artistEmail),
		dryRun,
	})
	const djFirebase = await ensureFirebaseUser(auth, {
		email: djEmail,
		password,
		displayName: inferDjName(djEmail),
		dryRun,
	})
	const adminFirebase = await ensureFirebaseUser(auth, {
		email: adminEmail,
		password,
		displayName: 'WeAfrica Admin',
		dryRun,
	})

	accounts.artist = { email: artistEmail, firebase: artistFirebase }
	accounts.dj = { email: djEmail, firebase: djFirebase }
	accounts.admin = { email: adminEmail, firebase: adminFirebase }

	// If any account is missing uid in dry-run because it doesn't exist, we can’t seed DB rows for it.
	const artistUid = artistFirebase.uid
	const djUid = djFirebase.uid
	const adminUid = adminFirebase.uid

	// 2) Seed subscriptions (platinum)
	if (artistUid) {
		accounts.artist.subscription = await ensureFullSubscription(supabase, {
			uid: artistUid,
			planId,
			endsAtIso,
			countryCode: 'MW',
			source: 'ensure_test_accounts',
			dryRun,
		})
		accounts.artist.firebase_claims = await ensureFirebaseSubscriptionClaims(auth, {
			uid: artistUid,
			planId,
			endsAtIso,
			dryRun,
		})
	}
	if (djUid) {
		accounts.dj.subscription = await ensureFullSubscription(supabase, {
			uid: djUid,
			planId,
			endsAtIso,
			countryCode: 'MW',
			source: 'ensure_test_accounts',
			dryRun,
		})
		accounts.dj.firebase_claims = await ensureFirebaseSubscriptionClaims(auth, {
			uid: djUid,
			planId,
			endsAtIso,
			dryRun,
		})
	}
	if (adminUid) {
		accounts.admin.subscription = await ensureFullSubscription(supabase, {
			uid: adminUid,
			planId,
			endsAtIso,
			countryCode: 'MW',
			source: 'ensure_test_accounts',
			dryRun,
		})
		accounts.admin.firebase_claims = await ensureFirebaseSubscriptionClaims(auth, {
			uid: adminUid,
			planId,
			endsAtIso,
			dryRun,
		})
	}

	// 3) Ensure creator rows exist + active
	if (artistUid) {
		const stageName = inferArtistStageName(artistEmail)
		const base = {
			firebase_uid: artistUid,
			stage_name: stageName,
			email: artistEmail,
			approved: true,
			status: 'active',
			blocked: false,
			verified: true,
			can_upload: true,
			can_go_live: true,
			region: 'MW',
		}
		const attempts = [
			base,
			(() => {
				const { can_upload: _a, can_go_live: _b, ...rest } = base
				return rest
			})(),
			(() => {
				const { verified: _v, can_upload: _a, can_go_live: _b, ...rest } = base
				return rest
			})(),
			(() => {
				const { blocked: _bl, status: _s, verified: _v, can_upload: _a, can_go_live: _b, ...rest } = base
				return rest
			})(),
			(() => {
				const { approved: _ap, blocked: _bl, status: _s, verified: _v, can_upload: _a, can_go_live: _b, ...rest } = base
				return rest
			})(),
		]

		accounts.artist.artist_row = await ensureCreatorRow(supabase, {
			table: 'artists',
			uid: artistUid,
			payload: base,
			attempts,
			dryRun,
		})
	}

	if (djUid) {
		const djName = inferDjName(djEmail)
		const base = {
			firebase_uid: djUid,
			dj_name: djName,
			email: djEmail,
			approved: true,
			status: 'active',
			blocked: false,
			can_go_live: true,
			region: 'MW',
		}
		const attempts = [
			base,
			(() => {
				const { can_go_live: _a, ...rest } = base
				return rest
			})(),
			(() => {
				const { blocked: _bl, status: _s, can_go_live: _c, ...rest } = base
				return rest
			})(),
			(() => {
				const { approved: _ap, blocked: _bl, status: _s, can_go_live: _c, ...rest } = base
				return rest
			})(),
		]

		accounts.dj.dj_row = await ensureCreatorRow(supabase, {
			table: 'djs',
			uid: djUid,
			payload: base,
			attempts,
			dryRun,
		})
	}

	// 4) Ensure admin row exists + super_admin
	if (adminUid) {
		accounts.admin.admin_row = await ensureAdminRow(supabase, {
			email: adminEmail,
			uid: adminUid,
			dryRun,
		})
	}

	jsonOut({
		ok: true,
		dry_run: dryRun,
		plan_id: planId,
		subscription_ends_at: endsAtIso,
		warnings,
		accounts,
	})
} catch (e) {
	jsonOut({ ok: false, error: String(e?.message || e) })
	process.exit(1)
}
