import type { ReactNode } from "react"
import ActionButtons from './ActionButtons'

export default function ContentApproval() {
	return (
		<Card title="Content Approval">
			{[
				{ title: "New Hit Track", author: "Young Flame" },
				{ title: "Afro Jam", author: "DJ Tasha" },
				{ title: "My Music Video", author: "Lisa B" },
			].map((item) => (
				<div
					key={item.title}
					className="flex justify-between items-center py-3 border-t border-white/10"
				>
					<div>
						<p>{item.title}</p>
						<p className="text-xs text-gray-400">{item.author}</p>
					</div>

					<ActionButtons />
				</div>
			))}
		</Card>
	)
}

function Card({ title, children }: { title: string; children: ReactNode }) {
	return (
		<div className="bg-white/5 rounded-xl p-5">
			<h2 className="font-semibold mb-4">{title}</h2>
			{children}
		</div>
	)
}
