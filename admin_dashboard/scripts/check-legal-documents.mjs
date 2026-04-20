import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'

dotenv.config({ path: '.env.local' })

function getEnv(name) {
	const raw = process.env[name]
	if (!raw) return null
	const trimmed = String(raw)
		.trim()
		.replace(/^['"]|['"]$/g, '')
		.replace(/\r/g, '')
		.replace(/\n/g, '')
	return trimmed.length ? trimmed : null
}

function isMissingTableError(err) {
	const msg = String(err?.message ?? '')
	const code = String(err?.code ?? '')
	return code === '42P01' || code === 'PGRST205' || /schema cache|could not find|does not exist/i.test(msg)
}

async function main() {
	const url = getEnv('NEXT_PUBLIC_SUPABASE_URL') ?? getEnv('SUPABASE_URL')
	const anonKey = getEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY')
	if (!url || !anonKey) {
		console.error('Missing env vars. Need NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local')
		process.exit(1)
	}

	const supabase = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })

	console.log('Checking public legal documents (anon read)...')
	let res = await supabase
		.from('current_legal_documents')
		.select('doc_key,slug,audience,title,version,content')
		.limit(50)

	// If the view is missing, fall back to the base table.
	if (res.error && isMissingTableError(res.error)) {
		res = await supabase.from('legal_documents').select('doc_key,slug,audience,title,version,content,published,effective_at').limit(200)
	}

	const { data, error } = res
	if (error) {
		if (isMissingTableError(error)) {
			console.log('✗ legal documents: MISSING (apply migrations)')
			process.exit(2)
		}
		console.log(`✗ legal documents: ERROR: ${error.message}`)
		process.exit(3)
	}

	const rows = data ?? []
	console.log(`✓ legal documents: OK (rows=${rows.length})`)

	const required = [
		{ doc_key: 'artist_tos', slug: 'artist-terms-of-service', version: '1' },
		{ doc_key: 'content_community_policy', slug: 'content-community-policy', version: '1' },
		{ doc_key: 'copyright_takedown_policy', slug: 'copyright-takedown-policy', version: '1' },
	]

	for (const r of required) {
		const found = rows.find((row) => String(row.doc_key ?? '') === r.doc_key && String(row.version ?? '') === r.version)
		if (!found) {
			console.log(`✗ missing required doc: ${r.doc_key} v${r.version}`)
			process.exit(4)
		}
		// slug is best-effort (older schemas may not have it)
		if (Object.prototype.hasOwnProperty.call(found, 'slug')) {
			const slug = String(found.slug ?? '')
			if (slug && slug !== r.slug) console.log(`! slug mismatch for ${r.doc_key}: got=${slug} expected=${r.slug}`)
		}
		console.log(`✓ required doc present: ${r.doc_key} v${r.version}`)
	}
}

main().catch((err) => {
	console.error(err)
	process.exit(1)
})
