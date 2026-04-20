import 'server-only'

export type PipedreamInvokeResult = {
	ok: boolean
	status: number
	data: unknown
}

export async function invokePipedreamWorkflow(args: {
	workflowId: string
	token: string
	payload?: unknown
}): Promise<PipedreamInvokeResult> {
	const workflowId = String(args.workflowId ?? '').trim()
	if (!workflowId) throw new Error('Missing PIPEDREAM_WORKFLOW_ID')

	const token = String(args.token ?? '').trim()
	if (!token) throw new Error('Missing PIPEDREAM_API_TOKEN')

	const url = `https://api.pipedream.com/v1/workflows/${encodeURIComponent(workflowId)}/invoke`

	const res = await fetch(url, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json',
		},
		body: args.payload === undefined ? undefined : JSON.stringify(args.payload),
		cache: 'no-store',
	})

	let data: unknown = null
	const contentType = res.headers.get('content-type') || ''
	if (contentType.includes('application/json')) data = await res.json().catch(() => null)
	else data = await res.text().catch(() => null)

	if (!res.ok) {
		const msg = typeof data === 'string' ? data : JSON.stringify(data)
		throw new Error(`Pipedream invoke failed (${res.status}): ${msg}`)
	}

	return { ok: true, status: res.status, data }
}
