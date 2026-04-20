'use client'

import { useEffect, useId, useRef } from 'react'

export function ConfirmDialog(props: {
	open: boolean
	title: string
	description?: string
	confirmText?: string
	cancelText?: string
	confirmTone?: 'danger' | 'primary'
	busy?: boolean
	onCancelActionPath?: string
	onConfirmActionPath?: string
	initialReason?: string
	onCancelAction?: () => void
	onConfirmAction?: (payload: { reason: string }) => void
}) {
	const dialogRef = useRef<HTMLDialogElement | null>(null)
	const id = useId()

	useEffect(() => {
		const el = dialogRef.current
		if (!el) return
		if (props.open && !el.open) el.showModal()
		if (!props.open && el.open) el.close()
	}, [props.open])

	return (
		<dialog
			ref={dialogRef}
			className="w-full max-w-md rounded-2xl border border-black/[.08] bg-white p-0 text-zinc-900 shadow-xl dark:border-white/[.145] dark:bg-black dark:text-white"
			onClose={() => {
					if (props.onCancelAction) props.onCancelAction()
					if (props.onCancelActionPath) {
						window.location.assign(props.onCancelActionPath)
					}
			}}
		>
			<form
				method="dialog"
				className="p-6"
				onSubmit={(e) => {
					e.preventDefault()
					const form = e.currentTarget
					const fd = new FormData(form)
					const reason = String(fd.get('reason') ?? '').trim()
					if (props.onConfirmAction) props.onConfirmAction({ reason })
					if (props.onConfirmActionPath) {
						fetch(props.onConfirmActionPath, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ reason }) })
							.catch(() => null)
					}
					const el = dialogRef.current
					if (el && el.open) el.close()
				}}
			>
				<h2 className="text-base font-semibold">{props.title}</h2>
				{props.description ? <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">{props.description}</p> : null}

				<label className="mt-4 block text-sm">
					<span className="text-zinc-600 dark:text-zinc-400">Reason (optional)</span>
					<textarea
						name="reason"
						defaultValue={props.initialReason ?? ''}
						rows={3}
						className="mt-2 w-full rounded-xl border border-black/[.08] bg-transparent px-3 py-2 outline-none dark:border-white/[.145]"
						autoFocus
						aria-describedby={id}
					/>
				</label>

				<div id={id} className="mt-2 text-xs text-zinc-600 dark:text-zinc-400">
					This will be written to the audit logs.
				</div>

				<div className="mt-5 flex items-center justify-end gap-2">
					<button
						type="button"
						onClick={() => {
							if (props.onCancelActionPath) {
								window.location.assign(props.onCancelActionPath)
							}
						}}
						disabled={props.busy}
						className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
					>
						{props.cancelText ?? 'Cancel'}
					</button>
					<button
						type="submit"
						disabled={props.busy}
						className={
							"inline-flex h-10 items-center rounded-xl px-4 text-sm text-white disabled:opacity-60 " +
							(props.confirmTone === 'danger' ? 'bg-red-600 hover:bg-red-500' : 'bg-black hover:bg-zinc-800 dark:bg-white dark:text-black dark:hover:bg-zinc-200')
						}
					>
						{props.busy ? 'Working…' : props.confirmText ?? 'Confirm'}
					</button>
				</div>
			</form>
		</dialog>
	)
}
