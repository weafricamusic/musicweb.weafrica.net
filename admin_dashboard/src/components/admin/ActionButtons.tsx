'use client'

export default function ActionButtons(props: {
	onApprove?: () => void
	onReject?: () => void
	approveLabel?: string
	rejectLabel?: string
	disabled?: boolean
}) {
	const { onApprove, onReject, approveLabel = 'Approve', rejectLabel = 'Reject', disabled } = props
	return (
		<div className="flex flex-col gap-2 md:flex-row">
			<button
				type="button"
				disabled={disabled}
				onClick={onApprove}
				className="rounded-lg bg-green-600 px-3 py-2 text-sm font-medium transition hover:bg-green-700 disabled:opacity-60"
			>
				{approveLabel}
			</button>
			<button
				type="button"
				disabled={disabled}
				onClick={onReject}
				className="rounded-lg bg-red-600 px-3 py-2 text-sm font-medium transition hover:bg-red-700 disabled:opacity-60"
			>
				{rejectLabel}
			</button>
		</div>
	)
}
