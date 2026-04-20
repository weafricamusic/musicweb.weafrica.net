import type { ReactNode } from "react"

export default function TeamManagement() {
	return (
		<Card title="Team Management">
			<div className="flex justify-end mb-4">
				<button className="bg-orange-500 px-4 py-2 rounded">
					Invite Member
				</button>
			</div>

			{[
				{ name: "James Banda", role: "Admin" },
				{ name: "Catherine M.", role: "Moderator" },
				{ name: "Paul Chirwa", role: "Editor" },
			].map((user) => (
				<div
					key={user.name}
					className="flex justify-between py-3 border-t border-white/10"
				>
					<span>{user.name}</span>
					<span className="text-gray-400">{user.role}</span>
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
