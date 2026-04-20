import { getDjs, setDjApproval } from "./actions"
import CreatorRowActions from '@/components/admin/CreatorRowActions'
import Link from 'next/link'

export const dynamic = "force-dynamic"

export default async function DJsPage() {
	const djs = await getDjs()

	return (
		<div className="bg-white/5 rounded-xl p-6">
			<h1 className="text-xl font-semibold mb-6">DJs</h1>

			<div className="grid grid-cols-6 text-sm text-gray-400 pb-2 border-b border-white/10">
				<div>Name</div>
				<div>Status</div>
				<div>Joined</div>
				<div>Dashboard</div>
				<div className="col-span-2">Action</div>
			</div>

			{djs.map((d) => (
				<div key={d.id} className="grid grid-cols-6 items-center py-3 border-b border-white/5">
					<div className="font-medium">{d.dj_name}</div>

					<div>
						<span
							className={`px-2 py-1 rounded text-xs ${
								d.status === 'active'
									? "bg-green-500/20 text-green-400"
									: d.status === 'blocked'
										? "bg-red-500/20 text-red-300"
										: "bg-yellow-500/20 text-yellow-400"
							}`}
						>
							{d.status === 'active' ? 'Active' : d.status === 'blocked' ? 'Suspended' : 'Pending'}
						</span>
					</div>

					<div className="text-xs text-gray-400">{new Date(d.created_at).toLocaleDateString()}</div>

					<div>
						<Link
							href={`/dashboard/djs/${encodeURIComponent(d.id)}`}
							className="text-xs text-blue-300 hover:text-blue-200 hover:underline"
						>
							Open
						</Link>
					</div>

					<div className="col-span-2">
						<CreatorRowActions entity="djs" id={d.id} name={d.dj_name} status={d.status} />
					</div>
				</div>
			))}
		</div>
	)
}
