import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase/server'

export const runtime = 'nodejs'

function normalizeLookupValue(value: string): string {
	return value
		.trim()
		.toLowerCase()
		.replace(/\s+/g, '-')
		.replace(/_+/g, '-')
		.replace(/-+/g, '-')
}

function mapLegalAlias(input: string): { slug?: string; doc_key?: string } {
	const v = normalizeLookupValue(input)

	// Copyright policy aliases
	if (v === 'copyright-policy' || v === 'copyright') {
		return { doc_key: 'copyright_takedown_policy' }
	}
	if (v === 'copyright-policy-v1') {
		return { doc_key: 'copyright_takedown_policy' }
	}
	if (v === 'copyright-and-takedown-policy') {
		return { doc_key: 'copyright_takedown_policy' }
	}

	// Content policy aliases
	if (v === 'content-policy' || v === 'community-policy') {
		return { doc_key: 'content_community_policy' }
	}

	// ToS aliases
	if (v === 'artist-terms' || v === 'artist-tos' || v === 'tos-artist') {
		return { doc_key: 'artist_tos' }
	}

	return {}
}

function normalizeOptional(value: string | null): string | undefined {
	const v = (value ?? '').toString().trim()
	return v.length ? v : undefined
}

export async function GET(req: Request) {
	const url = new URL(req.url)
	let slug = normalizeOptional(url.searchParams.get('slug'))
	let doc_key = normalizeOptional(url.searchParams.get('doc_key'))
	const audience = normalizeOptional(url.searchParams.get('audience'))
	const language = normalizeOptional(url.searchParams.get('language'))
	const version = normalizeOptional(url.searchParams.get('version'))

	if (!slug && !doc_key) {
		return NextResponse.json({ error: 'Missing slug or doc_key' }, { status: 400 })
	}

	// If clients pass an alias slug/doc_key, map it before querying.
	const aliasSource = slug ?? doc_key
	if (aliasSource) {
		const mapped = mapLegalAlias(aliasSource)
		slug = slug ?? mapped.slug
		doc_key = doc_key ?? mapped.doc_key
	}

	const supabase = createSupabaseServerClient()

	let q = supabase
		.from('current_legal_documents')
		.select('doc_key,slug,audience,language,title,version,content,content_markdown,effective_at,published,meta,updated_at')

	if (slug && doc_key) {
		q = q.or(`slug.eq.${slug},doc_key.eq.${doc_key}`)
	} else if (slug) {
		q = q.eq('slug', slug)
	} else if (doc_key) {
		q = q.eq('doc_key', doc_key)
	}

	if (audience) q = q.eq('audience', audience)
	if (language) q = q.eq('language', language)
	if (version) q = q.eq('version', version)

	let { data, error } = await q.limit(1).maybeSingle()

	if (!data && !error && (slug || doc_key)) {
		// Second chance: if they provided a slug and it didn't match, try alias mapping.
		const mapped = mapLegalAlias(slug ?? doc_key ?? '')
		if (mapped.doc_key && mapped.doc_key !== doc_key) {
			const retry = await supabase
				.from('current_legal_documents')
				.select('doc_key,slug,audience,language,title,version,content,content_markdown,effective_at,published,meta,updated_at')
				.eq('doc_key', mapped.doc_key)
				.limit(1)
				.maybeSingle()
			data = retry.data as any
			error = retry.error
		}
	}

	if (error) {
		return NextResponse.json(
			{ error: 'Supabase error', code: error.code, message: error.message },
			{ status: 500 },
		)
	}

	if (!data) return NextResponse.json({ error: 'Legal document not found' }, { status: 404 })

	return NextResponse.json({ document: data })
}
