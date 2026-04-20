'use client'

import { useState } from 'react'

type TxType = 'coin_purchase' | 'subscription' | 'ad' | 'gift' | 'battle_reward' | 'adjustment'

type TargetType = 'artist' | 'dj'

export default function FinanceToolsClient() {
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)
	const [loading, setLoading] = useState(false)

	const [txType, setTxType] = useState<TxType>('coin_purchase')
	const [actorId, setActorId] = useState('')
	const [targetType, setTargetType] = useState<TargetType>('artist')
	const [targetId, setTargetId] = useState('')
	const [amountMwk, setAmountMwk] = useState('5000')
	const [coins, setCoins] = useState('500')
	const [source, setSource] = useState('PayChangu')

	const [withdrawType, setWithdrawType] = useState<TargetType>('artist')
	const [withdrawId, setWithdrawId] = useState('')
	const [withdrawAmount, setWithdrawAmount] = useState('80000')
	const [withdrawMethod, setWithdrawMethod] = useState('Mobile')

	async function post(body: any) {
		setError(null)
		setOk(null)
		setLoading(true)
		try {
			const res = await fetch('/api/admin/finance/tools', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body),
			})
			const json = (await res.json().catch(() => null)) as any
			if (!res.ok) throw new Error(json?.error || 'Request failed')
			setOk('Saved successfully.')
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Request failed')
		} finally {
			setLoading(false)
		}
	}

	function isTxGiftLike(t: TxType) {
		return t === 'gift' || t === 'battle_reward'
	}

	return (
		<div className="space-y-6">
			{error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}
			{ok ? <div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">{ok}</div> : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Create Transaction</h2>
				<p className="mt-1 text-sm text-gray-400">Writes to the ledger. No deletes.</p>

				<div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
					<label className="text-sm">
						<span className="block text-xs text-gray-400">Type</span>
						<select value={txType} onChange={(e) => setTxType(e.target.value as TxType)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm">
							<option value="coin_purchase">Coin Purchase</option>
							<option value="subscription">Subscription</option>
							<option value="ad">Ad</option>
							<option value="gift">Gift</option>
							<option value="battle_reward">Battle Reward</option>
							<option value="adjustment">Adjustment</option>
						</select>
					</label>

					<label className="text-sm">
						<span className="block text-xs text-gray-400">Actor ID (user)</span>
						<input value={actorId} onChange={(e) => setActorId(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" placeholder="user id (optional for system)" />
					</label>

					{isTxGiftLike(txType) ? (
						<>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Target Type</span>
								<select value={targetType} onChange={(e) => setTargetType(e.target.value as TargetType)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm">
									<option value="artist">Artist</option>
									<option value="dj">DJ</option>
								</select>
							</label>
							<label className="text-sm">
								<span className="block text-xs text-gray-400">Target ID</span>
								<input value={targetId} onChange={(e) => setTargetId(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" placeholder={`${targetType} id`} />
							</label>
						</>
					) : null}

					<label className="text-sm">
						<span className="block text-xs text-gray-400">Amount (MWK)</span>
						<input value={amountMwk} onChange={(e) => setAmountMwk(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
					</label>
					<label className="text-sm">
						<span className="block text-xs text-gray-400">Coins</span>
						<input value={coins} onChange={(e) => setCoins(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
					</label>
					<label className="text-sm md:col-span-2">
						<span className="block text-xs text-gray-400">Source</span>
						<input value={source} onChange={(e) => setSource(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" placeholder="PayChangu / Live / System" />
					</label>
				</div>

				<button
					disabled={loading}
					onClick={() =>
						post({
							action: 'create_transaction',
							type: txType,
							actor_id: actorId || null,
							target_type: isTxGiftLike(txType) ? targetType : null,
							target_id: isTxGiftLike(txType) ? targetId || null : null,
							amount_mwk: amountMwk,
							coins,
							source,
						})
					}
					className="mt-4 inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15 disabled:opacity-60"
				>
					{loading ? 'Saving…' : 'Create transaction'}
				</button>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Create Withdrawal Request</h2>
				<p className="mt-1 text-sm text-gray-400">Creates a pending withdrawal (manual approval required).</p>

				<div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
					<label className="text-sm">
						<span className="block text-xs text-gray-400">Role</span>
						<select value={withdrawType} onChange={(e) => setWithdrawType(e.target.value as TargetType)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm">
							<option value="artist">Artist</option>
							<option value="dj">DJ</option>
						</select>
					</label>
					<label className="text-sm">
						<span className="block text-xs text-gray-400">User ID</span>
						<input value={withdrawId} onChange={(e) => setWithdrawId(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" placeholder={`${withdrawType} id`} />
					</label>
					<label className="text-sm">
						<span className="block text-xs text-gray-400">Amount (MWK)</span>
						<input value={withdrawAmount} onChange={(e) => setWithdrawAmount(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
					</label>
					<label className="text-sm">
						<span className="block text-xs text-gray-400">Method</span>
						<input value={withdrawMethod} onChange={(e) => setWithdrawMethod(e.target.value)} className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm" placeholder="Mobile / Bank" />
					</label>
				</div>

				<button
					disabled={loading}
					onClick={() =>
						post({
							action: 'create_withdrawal',
							beneficiary_type: withdrawType,
							beneficiary_id: withdrawId,
							amount_mwk: withdrawAmount,
							method: withdrawMethod,
						})
					}
					className="mt-4 inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15 disabled:opacity-60"
				>
					{loading ? 'Saving…' : 'Create withdrawal request'}
				</button>
			</div>
		</div>
	)
}
