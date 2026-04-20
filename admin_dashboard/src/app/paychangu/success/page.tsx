export const runtime = 'nodejs'

export default async function PayChanguSuccessPage({
	searchParams,
}: {
	searchParams?: Promise<Record<string, string | string[] | undefined>>
}) {
	const sp = (await searchParams) ?? {}
	const status = Array.isArray(sp.status) ? sp.status[0] : sp.status
	const txRef = Array.isArray(sp.tx_ref) ? sp.tx_ref[0] : sp.tx_ref

	const normalizedStatus = (status ?? '').toString().trim().toLowerCase()
	const ok = normalizedStatus === '' || normalizedStatus === 'success' || normalizedStatus === 'successful' || normalizedStatus === 'paid'

	return (
		<div className="min-h-screen bg-zinc-950 px-6 py-16 text-white">
			<div className="mx-auto w-full max-w-lg rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-xl font-semibold">{ok ? 'Payment completed' : 'Payment status received'}</h1>
				<p className="mt-2 text-sm text-gray-300">
					{ok
						? 'Your payment was received. You can close this page and return to the app.'
						: 'We received an update from the payment provider. You can close this page and return to the app.'}
				</p>
				<div className="mt-4 rounded-xl border border-white/10 bg-black/20 p-4 text-sm text-gray-200">
					<div>
						<span className="text-gray-400">Status:</span> {status ?? '—'}
					</div>
					<div className="mt-1 break-all">
						<span className="text-gray-400">Reference:</span> {txRef ?? '—'}
					</div>
				</div>
				<p className="mt-4 text-xs text-gray-400">
					If your subscription doesn’t update immediately, wait a few seconds and refresh your subscription status in the app.
				</p>
			</div>
		</div>
	)
}
