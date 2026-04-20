import { getArtists, setArtistApproval } from "./actions"
import CreatorRowActions from '@/components/admin/CreatorRowActions'

export const dynamic = "force-dynamic"

export default async function ArtistsPage() {
	const artists = await getArtists()

	return (
		<div className="bg-white/5 rounded-xl p-6">
			<h1 className="text-xl font-semibold mb-6">Artists</h1>

			<div className="grid grid-cols-6 text-sm text-gray-400 pb-2 border-b border-white/10">
				<div>Name</div>
				<div>Songs</div>
				<div>Videos</div>
				<div>Status</div>
				<div>Joined</div>
				<div>Action</div>
			</div>

			{artists.map((a) => (
				<div key={a.id} className="grid grid-cols-6 items-center py-3 border-b border-white/5">
					<div className="font-medium">{a.stage_name}</div>
					<div>{a.songs_count}</div>
					<div>{a.videos_count}</div>

					<div>
						<span
							className={`px-2 py-1 rounded text-xs ${
								a.status === 'active'
									? "bg-green-500/20 text-green-400"
									: a.status === 'blocked'
										? "bg-red-500/20 text-red-300"
										: "bg-yellow-500/20 text-yellow-400"
							}`}
						>
							{a.status === 'active' ? 'Active' : a.status === 'blocked' ? 'Suspended' : 'Pending'}
						</span>
					</div>

					<div className="text-xs text-gray-400">
						{new Date(a.created_at).toLocaleDateString()}
					</div>

					<CreatorRowActions entity="artists" id={a.id} name={a.stage_name} status={a.status} />
				</div>
			))}
		</div>
	)
}
