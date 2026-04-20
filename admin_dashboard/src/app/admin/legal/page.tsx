import { createSupabaseServerClient } from '@/lib/supabase/server'

type LegalDocRow = {
	doc_key: string
	slug: string | null
	audience: string | null
	language: string | null
	title: string | null
	version: string | null
	content: string | null
	content_markdown: string | null
	effective_at: string | null
	published: boolean | null
	updated_at: string | null
}

function previewText(value: string | null | undefined, maxLen = 240): string {
	const text = (value ?? '').toString().trim()
	if (!text) return '—'
	if (text.length <= maxLen) return text
	return text.slice(0, maxLen).trimEnd() + '…'
}

export default async function AdminLegalPage() {
	const supabase = createSupabaseServerClient()

	let rows: LegalDocRow[] = []
	let warning: string | null = null

	const viewQuery = await supabase
		.from('current_legal_documents')
		.select('doc_key,slug,audience,language,title,version,content,content_markdown,effective_at,published,updated_at')
		.order('doc_key', { ascending: true })

	if (viewQuery.error) {
		warning = `Could not query view public.current_legal_documents (${viewQuery.error.code ?? 'error'}: ${viewQuery.error.message}). Falling back to public.legal_documents.`

		const fallback = await supabase
			.from('legal_documents')
			.select('doc_key,slug,audience,language,title,version,content,content_markdown,effective_at,published,updated_at')
			.eq('published', true)
			.order('doc_key', { ascending: true })
		rows = (fallback.data ?? []) as LegalDocRow[]
		if (fallback.error) {
			warning = `Could not query public.legal_documents (${fallback.error.code ?? 'error'}: ${fallback.error.message}).`
		}
	} else {
		rows = (viewQuery.data ?? []) as LegalDocRow[]
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-6">
				<p className="text-sm text-zinc-300">Legal & Compliance</p>
				<p className="mt-1 text-xs text-zinc-400">Published legal documents from Supabase (public.current_legal_documents).</p>
			</div>

			{warning ? (
				<div className="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-6">
					<p className="text-sm text-zinc-200">Warning</p>
					<p className="mt-2 text-xs text-zinc-400">{warning}</p>
				</div>
			) : null}

			<div className="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-6">
				<p className="text-sm text-zinc-200">Documents</p>
				<p className="mt-1 text-xs text-zinc-400">Rows: {rows.length}</p>

				<div className="mt-4 space-y-4">
					{rows.map((doc) => (
						<div key={`${doc.doc_key}:${doc.version ?? ''}:${doc.audience ?? ''}:${doc.language ?? ''}`} className="rounded-2xl border border-zinc-800 bg-zinc-950/30 p-5">
							<div className="flex flex-wrap items-baseline justify-between gap-2">
								<p className="text-sm font-medium text-zinc-100">{doc.title ?? doc.doc_key}</p>
								<p className="text-xs text-zinc-500">v{doc.version ?? '—'}</p>
							</div>
							<div className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
								<div className="text-xs text-zinc-400">
									<span className="text-zinc-500">doc_key:</span> {doc.doc_key}
								</div>
								<div className="text-xs text-zinc-400">
									<span className="text-zinc-500">slug:</span> {doc.slug ?? '—'}
								</div>
								<div className="text-xs text-zinc-400">
									<span className="text-zinc-500">audience:</span> {doc.audience ?? '—'}
								</div>
								<div className="text-xs text-zinc-400">
									<span className="text-zinc-500">language:</span> {doc.language ?? '—'}
								</div>
								<div className="text-xs text-zinc-400">
									<span className="text-zinc-500">published:</span> {String(doc.published ?? false)}
								</div>
								<div className="text-xs text-zinc-400">
									<span className="text-zinc-500">effective_at:</span> {doc.effective_at ?? '—'}
								</div>
							</div>

							<div className="mt-4">
								<p className="text-xs text-zinc-500">Content preview</p>
								<pre className="mt-2 whitespace-pre-wrap rounded-xl border border-zinc-800 bg-zinc-950/50 p-4 text-xs text-zinc-200">
									{previewText(doc.content_markdown ?? doc.content)}
								</pre>
							</div>
						</div>
					))}
					{rows.length === 0 ? (
						<p className="text-xs text-zinc-400">No published legal documents found.</p>
					) : null}
				</div>
			</div>
		</div>
	)
}
