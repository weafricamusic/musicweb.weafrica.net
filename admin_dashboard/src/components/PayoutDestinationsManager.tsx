'use client'

import { useEffect, useMemo, useState } from 'react'

type Destination = {
	id: string
	kind: 'bank' | 'mobile_money'
	label: string | null
	bank_name: string | null
	bank_account_name: string | null
	bank_account_number: string | null
	bank_branch: string | null
	mobile_network: string | null
	mobile_number: string | null
	mobile_account_name: string | null
	is_default: boolean
	created_at: string
	updated_at: string
}

type Props = {
	apiBase: string
	title?: string
	desc?: string
}

function kindLabel(k: Destination['kind']): string {
	return k === 'bank' ? 'Bank Account' : 'Mobile Money'
}

export function PayoutDestinationsManager(props: Props) {
	const [rows, setRows] = useState<Destination[]>([])
	const [loading, setLoading] = useState(false)
	const [saving, setSaving] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)

	const [kind, setKind] = useState<Destination['kind']>('mobile_money')
	const [label, setLabel] = useState('')

	const [bankName, setBankName] = useState('')
	const [bankAccountName, setBankAccountName] = useState('')
	const [bankAccountNumber, setBankAccountNumber] = useState('')
	const [bankBranch, setBankBranch] = useState('')

	const [mobileNetwork, setMobileNetwork] = useState('')
	const [mobileNumber, setMobileNumber] = useState('')
	const [mobileAccountName, setMobileAccountName] = useState('')

	const [makeDefault, setMakeDefault] = useState(true)

	const api = props.apiBase.replace(/\/$/, '')

	async function load() {
		setError(null)
		setOk(null)
		setLoading(true)
		try {
			const res = await fetch(api, { method: 'GET' })
			const json = (await res.json().catch(() => null)) as any
			if (!res.ok) throw new Error(json?.error || 'Failed to load payout methods')
			setRows((json?.destinations ?? []) as Destination[])
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to load payout methods')
		} finally {
			setLoading(false)
		}
	}

	useEffect(() => {
		void load()
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [])

	const defaultRow = useMemo(() => rows.find((r) => r.is_default) ?? null, [rows])

	async function create() {
		if (saving) return
		setError(null)
		setOk(null)
		setSaving(true)
		try {
			const payload: any = {
				kind,
				label: label.trim() || null,
				is_default: Boolean(makeDefault),
			}
			if (kind === 'bank') {
				payload.bank_name = bankName.trim() || null
				payload.bank_account_name = bankAccountName.trim() || null
				payload.bank_account_number = bankAccountNumber.trim() || null
				payload.bank_branch = bankBranch.trim() || null
			}
			if (kind === 'mobile_money') {
				payload.mobile_network = mobileNetwork.trim() || null
				payload.mobile_number = mobileNumber.trim() || null
				payload.mobile_account_name = mobileAccountName.trim() || null
			}
			const res = await fetch(api, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(payload),
			})
			const json = (await res.json().catch(() => null)) as any
			if (!res.ok) throw new Error(json?.error || 'Failed to save payout method')
			setOk('Saved.')
			setLabel('')
			setBankName('')
			setBankAccountName('')
			setBankAccountNumber('')
			setBankBranch('')
			setMobileNetwork('')
			setMobileNumber('')
			setMobileAccountName('')
			await load()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to save payout method')
		} finally {
			setSaving(false)
		}
	}

	async function setDefault(id: string) {
		if (saving) return
		setError(null)
		setOk(null)
		setSaving(true)
		try {
			const res = await fetch(`${api}/${encodeURIComponent(id)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'set_default' }),
			})
			const json = (await res.json().catch(() => null)) as any
			if (!res.ok) throw new Error(json?.error || 'Failed to set default')
			setOk('Default updated.')
			await load()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to set default')
		} finally {
			setSaving(false)
		}
	}

	async function remove(id: string) {
		if (saving) return
		setError(null)
		setOk(null)
		setSaving(true)
		try {
			const res = await fetch(`${api}/${encodeURIComponent(id)}`, { method: 'DELETE' })
			const json = (await res.json().catch(() => null)) as any
			if (!res.ok) throw new Error(json?.error || 'Failed to delete')
			setOk('Deleted.')
			await load()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to delete')
		} finally {
			setSaving(false)
		}
	}

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<div className="flex items-start justify-between gap-4">
				<div>
					<h2 className="text-base font-semibold">{props.title ?? 'Payment method'}</h2>
					<p className="mt-1 text-sm text-gray-400">{props.desc ?? 'Add bank account or mobile money for payouts.'}</p>
				</div>
				<button
					disabled={loading}
					onClick={() => load()}
					className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60"
				>
					{loading ? 'Loading…' : 'Refresh'}
				</button>
			</div>

			{error ? <div className="mt-4 rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}
			{ok ? <div className="mt-4 rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">{ok}</div> : null}

			<div className="mt-5">
				<div className="text-xs text-gray-400">Default</div>
				<p className="mt-1 text-sm">
					{defaultRow ? `${kindLabel(defaultRow.kind)}${defaultRow.label ? ` — ${defaultRow.label}` : ''}` : '—'}
				</p>
			</div>

			<div className="mt-6 overflow-auto">
				<table className="w-full min-w-[900px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Type</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Label</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Details</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Default</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((r) => (
								<tr key={r.id}>
									<td className="border-b border-white/10 py-3 pr-4">{kindLabel(r.kind)}</td>
									<td className="border-b border-white/10 py-3 pr-4">{r.label ?? '—'}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										{r.kind === 'bank'
											? `${r.bank_name ?? '—'} • ${r.bank_account_number ?? '—'}`
											: `${r.mobile_network ?? '—'} • ${r.mobile_number ?? '—'}`}
									</td>
									<td className="border-b border-white/10 py-3 pr-4">{r.is_default ? 'Yes' : 'No'}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="flex flex-wrap gap-2">
											{!r.is_default ? (
												<button
													disabled={saving}
													onClick={() => setDefault(r.id)}
													className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 disabled:opacity-60"
												>
													Set default
												</button>
											) : null}
											<button
												disabled={saving}
												onClick={() => remove(r.id)}
												className="inline-flex h-9 items-center rounded-xl bg-red-600 px-3 text-sm disabled:opacity-60"
											>
												Delete
											</button>
										</div>
									</td>
								</tr>
							))
						) : (
							<tr>
								<td colSpan={5} className="py-6 text-sm text-gray-400">
									No payment methods yet.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>

			<div className="mt-6 rounded-2xl border border-white/10 bg-black/20 p-5">
				<h3 className="text-sm font-semibold">Add new</h3>
				<div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
					<label className="text-sm">
						<span className="block text-xs text-gray-400">Type</span>
						<select
							value={kind}
							onChange={(e) => setKind(e.target.value as any)}
							className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm"
						>
							<option value="mobile_money">Mobile Money</option>
							<option value="bank">Bank Account</option>
						</select>
					</label>

					<label className="text-sm">
						<span className="block text-xs text-gray-400">Label (optional)</span>
						<input
							value={label}
							onChange={(e) => setLabel(e.target.value)}
							className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm"
							placeholder={kind === 'bank' ? 'e.g. NBS Bank' : 'e.g. Airtel Money'}
						/>
					</label>

					{kind === 'bank' ? (
						<>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Bank name</span>
								<input value={bankName} onChange={(e) => setBankName(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
							</label>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Account number</span>
								<input value={bankAccountNumber} onChange={(e) => setBankAccountNumber(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
							</label>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Account name (optional)</span>
								<input value={bankAccountName} onChange={(e) => setBankAccountName(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
							</label>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Branch (optional)</span>
								<input value={bankBranch} onChange={(e) => setBankBranch(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
							</label>
						</>
					) : null}

					{kind === 'mobile_money' ? (
						<>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Network</span>
								<input value={mobileNetwork} onChange={(e) => setMobileNetwork(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" placeholder="Airtel Money / TNM Mpamba" />
							</label>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Mobile number</span>
								<input value={mobileNumber} onChange={(e) => setMobileNumber(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" placeholder="e.g. 0999..." />
							</label>
							<label className="text-sm md:col-span-2">
								<span className="block text-xs text-gray-400">Account name (optional)</span>
								<input value={mobileAccountName} onChange={(e) => setMobileAccountName(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
							</label>
						</>
					) : null}

					<label className="flex items-center gap-2 text-sm md:col-span-2">
						<input type="checkbox" checked={makeDefault} onChange={(e) => setMakeDefault(e.target.checked)} />
						<span>Make default</span>
					</label>
				</div>

				<button
					disabled={saving}
					onClick={() => create()}
					className="mt-4 inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15 disabled:opacity-60"
				>
					{saving ? 'Saving…' : 'Save payment method'}
				</button>
			</div>
		</div>
	)
}
