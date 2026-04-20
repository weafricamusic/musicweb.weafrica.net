import NavItem from './NavItem'
import CollapsibleGroup from './CollapsibleGroup'
import { getAdminContext } from "@/lib/admin/session"
import type { ReactNode } from 'react'
import {
	BarChart3,
	CreditCard,
	DollarSign,
	LayoutDashboard,
	Megaphone,
	Music,
	Radio,
	Settings,
	Shield,
	TrendingUp,
} from 'lucide-react'

function SectionLabel({ children }: { children: ReactNode }) {
	return (
		<div className="pt-4 pb-1 text-[11px] font-semibold uppercase tracking-widest text-zinc-500">
			{children}
		</div>
	)
}

export default async function Sidebar() {
	const ctx = await getAdminContext()
	const isProd = process.env.NODE_ENV === 'production'
	const canFinance = !!ctx?.permissions.can_manage_finance
	const canViewLogs = !!ctx?.permissions.can_view_logs
	const isOps = ctx?.admin.role === 'super_admin' || ctx?.admin.role === 'operations_admin'
	const isSuper = ctx?.admin.role === 'super_admin'
	const canMoney = canFinance || isSuper
	const canEvents = !!ctx?.permissions.can_manage_events || isSuper
	const canIdentity =
		!!ctx?.permissions.can_manage_users || !!ctx?.permissions.can_manage_artists || !!ctx?.permissions.can_manage_djs || isSuper
	const accordionKey = 'admin-sidebar'
	const subItemClass = 'px-3 py-1.5 text-[12.5px] rounded-md'
	return (
		<aside className="flex h-full w-64 flex-col border-r border-zinc-800 bg-zinc-950">
			<div className="p-5 pb-3">
				<div className="flex items-center justify-between">
					<h1 className="text-lg font-bold tracking-tight">WeAfrica Admin</h1>
					<label
						htmlFor="admin-nav"
						className="md:hidden inline-flex h-9 items-center rounded-lg border border-zinc-800 bg-zinc-900 px-3 text-sm hover:bg-zinc-800"
						aria-label="Close navigation"
					>
						✕
					</label>
				</div>
			</div>

			<nav className="flex-1 min-h-0 overflow-y-auto overscroll-contain px-5 pb-5">
				<SectionLabel>Overview</SectionLabel>
				<NavItem label="Overview" href="/admin/dashboard" icon={<LayoutDashboard size={16} />} />
				<NavItem label={isOps ? 'Ads & Promotions' : 'Ads & Promotions (Ops)'} href="/admin/ads" icon={<Megaphone size={16} />} />
				<NavItem label="Announcements" href="/admin/announcements" icon={<Megaphone size={16} />} />

				{canIdentity ? (
					<>
						<SectionLabel>Access &amp; Identity</SectionLabel>
						<CollapsibleGroup
							label="Access & Identity"
							storageKey="nav:identity"
							openOnPrefixes={['/admin/access-identity', '/admin/users', '/admin/artists', '/admin/djs', '/admin/verification', '/admin/account-actions', '/admin/settings']}
							accordionKey={accordionKey}
							icon={<Shield size={16} />}
						>
							<NavItem label="Overview" href="/admin/access-identity" className={subItemClass} />
							<NavItem label="Users (Consumers)" href="/admin/users" className={subItemClass} />
							<NavItem label="Artists" href="/admin/artists" className={subItemClass} />
							<NavItem label="DJs" href="/admin/djs" className={subItemClass} />
							<NavItem label="Verification Home" href="/admin/verification" className={subItemClass} />

							<CollapsibleGroup
								label="Verification"
								storageKey="nav:identity:verification"
								openOnPrefixes={['/admin/verification']}
								indent={false}
							>
								<CollapsibleGroup
									label="Artists"
									storageKey="nav:identity:verification:artists"
									openOnPrefixes={['/admin/verification/artists']}
									indent={false}
								>
									<NavItem label="Pending" href="/admin/verification/artists/pending" className={subItemClass} />
									<NavItem label="Approved" href="/admin/verification/artists/approved" className={subItemClass} />
									<NavItem label="Rejected" href="/admin/verification/artists/rejected" className={subItemClass} />
								</CollapsibleGroup>
								<CollapsibleGroup
									label="DJs"
									storageKey="nav:identity:verification:djs"
									openOnPrefixes={['/admin/verification/djs']}
									indent={false}
								>
									<NavItem label="Pending" href="/admin/verification/djs/pending" className={subItemClass} />
									<NavItem label="Approved" href="/admin/verification/djs/approved" className={subItemClass} />
									<NavItem label="Rejected" href="/admin/verification/djs/rejected" className={subItemClass} />
								</CollapsibleGroup>
							</CollapsibleGroup>

							<CollapsibleGroup label="Admin Users" storageKey="nav:identity:admin-users" indent={false}>
								<NavItem label="Super Admin" href="/admin/settings" className={subItemClass} />
								<NavItem label="Finance Admin" href="/admin/settings" className={subItemClass} />
								<NavItem label="Content Admin" href="/admin/settings" className={subItemClass} />
								<NavItem label="Support Admin" href="/admin/settings" className={subItemClass} />
							</CollapsibleGroup>

							<NavItem label="Roles & Permissions" href="/admin/settings" className={subItemClass} />
							<CollapsibleGroup
								label="Account Actions"
								storageKey="nav:identity:account-actions"
								openOnPrefixes={['/admin/account-actions']}
								indent={false}
							>
								<NavItem label="Suspend" href="/admin/users" className={subItemClass} />
								<NavItem label="Ban" href="/admin/users" className={subItemClass} />
								<NavItem label="Restore" href="/admin/users" className={subItemClass} />
							</CollapsibleGroup>
						</CollapsibleGroup>
					</>
				) : null}

				{canMoney ? (
					<CollapsibleGroup
						label="Money"
						storageKey="nav:money"
						openOnPrefixes={['/admin/money', '/admin/subscriptions', '/admin/payments', '/admin/coins', '/admin/payouts', '/admin/royalties', '/admin/countries', '/admin/pricing-currency']}
						accordionKey={accordionKey}
						icon={<DollarSign size={16} />}
						indent={false}
					>
						<NavItem label="Overview" href="/admin/money" className={subItemClass} />
						<CollapsibleGroup
							label="Subscriptions"
							storageKey="nav:money:subscriptions"
							openOnPrefixes={['/admin/subscriptions']}
							indent={false}
						>
							<NavItem label="Overview" href="/admin/subscriptions" className={subItemClass} />
							<NavItem label="Plans" href="/admin/subscriptions/plans" className={subItemClass} />
							<NavItem label="Payments" href="/admin/subscriptions/payments" className={subItemClass} />
							<NavItem label="Promotions" href="/admin/subscriptions/promotions" className={subItemClass} />
							<NavItem label="Content Access" href="/admin/subscriptions/content-access" className={subItemClass} />
							<NavItem label="User Subscriptions" href="/admin/subscriptions/user-subscriptions" className={subItemClass} />
								<NavItem label="Artists" href="/admin/subscriptions/artists" className={subItemClass} />
								<NavItem label="DJs" href="/admin/subscriptions/djs" className={subItemClass} />
							<CollapsibleGroup
								label="Consumers"
								storageKey="nav:money:subscriptions:consumers"
								openOnPrefixes={['/admin/subscriptions/consumers']}
								indent={false}
							>
								<NavItem label="Active" href="/admin/subscriptions/consumers/active" className={subItemClass} />
								<NavItem label="Past Due" href="/admin/subscriptions/consumers/past-due" className={subItemClass} />
								<NavItem label="Cancelled" href="/admin/subscriptions/consumers/cancelled" className={subItemClass} />
								<NavItem label="Expired" href="/admin/subscriptions/consumers/expired" className={subItemClass} />
							</CollapsibleGroup>
						</CollapsibleGroup>

						<CollapsibleGroup label="Payments" storageKey="nav:money:payments" openOnPrefixes={['/admin/payments']} indent={false} icon={<CreditCard size={16} />}>
							<NavItem label="Overview" href="/admin/payments" className={subItemClass} />
							<NavItem label="Transactions" href="/admin/payments/transactions" className={subItemClass} />
							<NavItem label="Successful" href="/admin/payments/transactions?type=revenue" className={subItemClass} />
							<NavItem label="Failed" href="/admin/payments/transactions?type=failed" className={subItemClass} />
							<NavItem label="Refunded" href="/admin/payments/transactions?type=refunded" className={subItemClass} />
							<NavItem label="Commission" href="/admin/payments/commission" className={subItemClass} />
							<NavItem label="Finance Tools" href="/admin/payments/tools" className={subItemClass} />
						</CollapsibleGroup>

						<CollapsibleGroup
							label="Coins System"
							storageKey="nav:money:coins"
							openOnPrefixes={['/admin/payments/coins', '/admin/coins/balances', '/admin/payments/transactions']}
							indent={false}
						>
							<NavItem label="Coin Packages" href="/admin/payments/coins" className={subItemClass} />
							<CollapsibleGroup label="Coin Usage" storageKey="nav:money:coins:usage" openOnPrefixes={['/admin/payments/transactions']} indent={false}>
								<NavItem label="Boosts" href="/admin/payments/transactions?type=boost" className={subItemClass} />
								<NavItem label="Gifting" href="/admin/payments/transactions?type=gift" className={subItemClass} />
								<NavItem label="Live Battles" href="/admin/payments/transactions?type=battle" className={subItemClass} />
							</CollapsibleGroup>
							<NavItem label="Coin Balances" href="/admin/payments/coins" className={subItemClass} />
						</CollapsibleGroup>

						<NavItem label="Royalties" href="/admin/payments/earnings/artists" className={subItemClass} />

						<CollapsibleGroup label="Payouts" storageKey="nav:money:payouts" openOnPrefixes={['/admin/payouts', '/admin/payments/withdrawals']} indent={false}>
							<NavItem label="Requested" href="/admin/payments/withdrawals?status=pending" className={subItemClass} />
							<NavItem label="Approved" href="/admin/payments/withdrawals?status=approved" className={subItemClass} />
							<NavItem label="Processing" href="/admin/payments/withdrawals?status=processing" className={subItemClass} />
							<NavItem label="Paid" href="/admin/payments/withdrawals?status=paid" className={subItemClass} />
							<NavItem label="Failed" href="/admin/payments/withdrawals?status=failed" className={subItemClass} />
						</CollapsibleGroup>

						<CollapsibleGroup label="Pricing & Currency" storageKey="nav:money:pricing" openOnPrefixes={['/admin/countries', '/admin/pricing-currency']} indent={false}>
							<NavItem label="Country Pricing" href="/admin/countries" className={subItemClass} />
							<NavItem label="Malawi Kwacha" href="/admin/countries" className={subItemClass} />
							<NavItem label="FX Rules" href="/admin/countries" className={subItemClass} />
						</CollapsibleGroup>
					</CollapsibleGroup>
				) : null}

				<CollapsibleGroup
					label="Content"
					storageKey="nav:content"
					openOnPrefixes={['/admin/tracks', '/admin/videos', '/admin/genres-categories', '/admin/playlists', '/admin/content/promotions', '/admin/moderation']}
					accordionKey={accordionKey}
					icon={<Music size={16} />}
				>
					<NavItem label="Overview" href="/admin/content" className={subItemClass} />
					<CollapsibleGroup label="Tracks" storageKey="nav:content:tracks" openOnPrefixes={['/admin/tracks']} indent={false}>
						<NavItem label="Upload Track" href="/admin/tracks/upload" className={subItemClass} />
						<NavItem label="Pending Approval" href="/admin/tracks/pending" className={subItemClass} />
						<NavItem label="Live" href="/admin/tracks/live" className={subItemClass} />
						<NavItem label="Removed" href="/admin/tracks/removed" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Videos" storageKey="nav:content:videos" openOnPrefixes={['/admin/videos']} indent={false}>
						<NavItem label="Pending Review" href="/admin/videos/pending" className={subItemClass} />
						<NavItem label="Live" href="/admin/videos/live" className={subItemClass} />
						<NavItem label="Taken Down" href="/admin/videos/taken-down" className={subItemClass} />
					</CollapsibleGroup>
					<NavItem label="Genres & Categories" href="/admin/genres-categories" className={subItemClass} />
					<NavItem label="Playlists" href="/admin/playlists" className={subItemClass} />
					<NavItem label="Promotions" href="/admin/content/promotions" className={subItemClass} />
					<NavItem label="Moderation Overview" href="/admin/moderation" className={subItemClass} />
					<NavItem label="User Moderation" href="/admin/moderation/users" className={subItemClass} />
					<NavItem label="Live Moderation" href="/admin/moderation/lives" className={subItemClass} />
					<NavItem label="Moderation Rules" href="/admin/moderation/rules" className={subItemClass} />
					{canEvents ? <NavItem label="Events & Tickets" href="/admin/events" className={subItemClass} /> : null}
					<CollapsibleGroup label="Reports & Flags" storageKey="nav:content:reports" openOnPrefixes={['/admin/moderation/reports']} indent={false}>
						<NavItem label="Copyright" href="/admin/moderation/reports?type=copyright" className={subItemClass} />
						<NavItem label="Abuse" href="/admin/moderation/reports?type=abuse" className={subItemClass} />
						<NavItem label="Spam" href="/admin/moderation/reports?type=spam" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Moderation Actions" storageKey="nav:content:moderation-actions" openOnPrefixes={['/admin/moderation/actions']} indent={false}>
						<NavItem label="Approve" href="/admin/moderation" className={subItemClass} />
						<NavItem label="Reject" href="/admin/moderation" className={subItemClass} />
						<NavItem label="Remove" href="/admin/moderation" className={subItemClass} />
					</CollapsibleGroup>
				</CollapsibleGroup>

				<CollapsibleGroup
					label="Live & Battles"
					storageKey="nav:live"
					openOnPrefixes={['/admin/live-battles', '/admin/live-streams', '/admin/live', '/admin/battles']}
					accordionKey={accordionKey}
					icon={<Radio size={16} />}
				>
					<NavItem label="Overview" href="/admin/live-battles" className={subItemClass} />
					<CollapsibleGroup label="Live Sessions" storageKey="nav:live:sessions" openOnPrefixes={['/admin/live-streams', '/admin/live']} indent={false}>
						<NavItem label="Ongoing" href="/admin/live-streams" className={subItemClass} />
						<NavItem label="Scheduled" href="/admin/live-streams?status=all" className={subItemClass} />
						<NavItem label="Ended" href="/admin/live-streams?status=ended" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Battles" storageKey="nav:live:battles" openOnPrefixes={['/admin/battles']} indent={false}>
						<NavItem label="Scheduled" href="/admin/live-battles" className={subItemClass} />
						<NavItem label="Live" href="/admin/live-battles" className={subItemClass} />
						<NavItem label="Completed" href="/admin/live-battles" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Battle Rules" storageKey="nav:live:battle-rules" openOnPrefixes={['/admin/battles/rules']} indent={false}>
						<NavItem label="Duration (20–30 min)" href="/admin/live-battles" className={subItemClass} />
						<NavItem label="Scoring" href="/admin/live-battles" className={subItemClass} />
						<NavItem label="Coin Rules" href="/admin/live-battles" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Live Moderation" storageKey="nav:live:moderation" openOnPrefixes={['/admin/live/moderation']} indent={false}>
						<NavItem label="Kick User" href="/admin/moderation/lives" className={subItemClass} />
						<NavItem label="Mute Stream" href="/admin/moderation/lives" className={subItemClass} />
						<NavItem label="End Stream" href="/admin/moderation/lives" className={subItemClass} />
					</CollapsibleGroup>
					<NavItem label="Live Reports" href="/admin/live/reports" className={subItemClass} />
				</CollapsibleGroup>

				<CollapsibleGroup
					label="Growth"
					storageKey="nav:growth"
					openOnPrefixes={['/admin/growth', '/admin/ads', '/admin/notifications']}
					accordionKey={accordionKey}
					icon={<TrendingUp size={16} />}
				>
					<NavItem label="Overview" href="/admin/growth" className={subItemClass} />
					<NavItem label="Featured Artists" href="/admin/growth/featured-artists" className={subItemClass} />
					<NavItem label="Featured DJs" href="/admin/growth/featured-djs" className={subItemClass} />
					<NavItem label="Featured Content" href="/admin/growth/featured-content" className={subItemClass} />
					<CollapsibleGroup label="Promotions" storageKey="nav:growth:promotions" openOnPrefixes={['/admin/growth/promotions']} indent={false}>
						<NavItem label="Campaigns" href="/admin/growth/promotions/campaigns" className={subItemClass} />
						<NavItem label="Boosts" href="/admin/growth/promotions/campaigns" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Ads" storageKey="nav:growth:ads" openOnPrefixes={['/admin/ads']} indent={false} icon={<Megaphone size={16} />}>
						<NavItem label={isOps ? 'AdMob Config' : 'AdMob Config (Ops)'} href="/admin/ads" className={subItemClass} />
						<NavItem label={isOps ? 'Campaigns' : 'Campaigns (Ops)'} href="/admin/ads/campaigns" className={subItemClass} />
						<NavItem label={isOps ? 'Admin Promotions' : 'Admin Promotions (Ops)'} href="/admin/ads/admin-promotions" className={subItemClass} />
						<NavItem label={isOps ? 'Paid Promotions' : 'Paid Promotions (Ops)'} href="/admin/ads/paid-promotions" className={subItemClass} />
						<NavItem label={isOps ? 'Surfaces' : 'Surfaces (Ops)'} href="/admin/ads/surfaces" className={subItemClass} />
						<NavItem label={isOps ? 'Ads Analytics' : 'Ads Analytics (Ops)'} href="/admin/ads/analytics" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Notifications" storageKey="nav:growth:notifications" openOnPrefixes={['/admin/notifications']} indent={false}>
						<NavItem label="Overview" href="/admin/notifications" className={subItemClass} />
						<NavItem label="Push" href="/admin/notifications/push" className={subItemClass} />
						<NavItem label="In-App" href="/admin/notifications/in-app" className={subItemClass} />
						{isProd ? null : <NavItem label="Email" href="/admin/notifications/email" className={subItemClass} />}
					</CollapsibleGroup>
				</CollapsibleGroup>

				<CollapsibleGroup
					label="Insights"
					storageKey="nav:insights"
					openOnPrefixes={['/admin/insights', '/admin/analytics']}
					accordionKey={accordionKey}
					icon={<BarChart3 size={16} />}
				>
					<NavItem label="Overview" href="/admin/insights" className={subItemClass} />
					<NavItem label="Platform Intelligence" href="/admin/analytics" className={subItemClass} />
					<NavItem label="Risk Flags" href="/admin/analytics/flags" className={subItemClass} />
					<NavItem label="Saved Flags" href="/admin/analytics/flags/saved" className={subItemClass} />
					<NavItem label="Timeline" href="/admin/analytics/timeline" className={subItemClass} />
					<CollapsibleGroup label="User Analytics" storageKey="nav:insights:user-analytics" openOnPrefixes={['/admin/analytics/users']} indent={false}>
						<NavItem label="Registrations" href="/admin/analytics" className={subItemClass} />
						<NavItem label="Active Users" href="/admin/analytics" className={subItemClass} />
						<NavItem label="Retention" href="/admin/analytics" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Artist Analytics" storageKey="nav:insights:artist-analytics" openOnPrefixes={['/admin/analytics/artists']} indent={false}>
						<NavItem label="Plays" href="/admin/analytics" className={subItemClass} />
						<NavItem label="Earnings" href="/admin/payments/earnings/artists" className={subItemClass} />
						<NavItem label="Growth" href="/admin/analytics" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="DJ Analytics" storageKey="nav:insights:dj-analytics" openOnPrefixes={['/admin/analytics/djs']} indent={false}>
						<NavItem label="Live Attendance" href="/admin/analytics" className={subItemClass} />
						<NavItem label="Battle Performance" href="/admin/analytics" className={subItemClass} />
						<NavItem label="Earnings" href="/admin/payments/earnings/djs" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Content Analytics" storageKey="nav:insights:content-analytics" openOnPrefixes={['/admin/analytics/content']} indent={false}>
						<NavItem label="Top Tracks" href="/admin/analytics" className={subItemClass} />
						<NavItem label="Top Videos" href="/admin/analytics" className={subItemClass} />
						<NavItem label="Trends" href="/admin/analytics" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Financial Reports" storageKey="nav:insights:financial-reports" openOnPrefixes={['/admin/analytics/reports']} indent={false}>
						<NavItem label="Revenue" href="/admin/analytics/reports" className={subItemClass} />
						<NavItem label="Subscriptions" href="/admin/analytics/reports" className={subItemClass} />
						<NavItem label="Payouts" href="/admin/analytics/reports" className={subItemClass} />
					</CollapsibleGroup>
				</CollapsibleGroup>

				<CollapsibleGroup
					label="System & Risk"
					storageKey="nav:system"
					openOnPrefixes={['/admin/system-risk', '/admin/health', '/admin/settings', '/admin/features', '/admin/security', '/admin/logs', '/admin/legal', '/admin/backups']}
					accordionKey={accordionKey}
					icon={<Settings size={16} />}
				>
					<NavItem label="Overview" href="/admin/system-risk" className={subItemClass} />
					<NavItem label="System Health" href="/admin/health" className={subItemClass} />
					<NavItem label="Platform Settings" href="/admin/settings" className={subItemClass} />
					<CollapsibleGroup label="Feature Toggles" storageKey="nav:system:features" openOnPrefixes={['/admin/features']} indent={false}>
						<NavItem label="Enable Downloads" href="/admin/system-risk" className={subItemClass} />
						<NavItem label="Enable Battles" href="/admin/system-risk" className={subItemClass} />
						<NavItem label="Enable Ads" href="/admin/system-risk" className={subItemClass} />
						<NavItem label="Country Toggles" href="/admin/system-risk" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Security" storageKey="nav:system:security" openOnPrefixes={['/admin/security']} indent={false}>
						<NavItem label="Login Attempts" href="/admin/system-risk" className={subItemClass} />
						<NavItem label="IP Blocks" href="/admin/system-risk" className={subItemClass} />
						<NavItem label="Admin MFA" href="/admin/system-risk" className={subItemClass} />
						<NavItem label="AI Security" href="/admin/ai-security" className={subItemClass} />
					</CollapsibleGroup>
					<CollapsibleGroup label="Audit Logs" storageKey="nav:system:audit" openOnPrefixes={['/admin/logs', '/admin/payments/logs', '/admin/moderation/logs']} indent={false}>
						{canViewLogs ? <NavItem label="Admin Actions" href="/admin/logs" className={subItemClass} /> : null}
						{canMoney ? <NavItem label="Financial Actions" href="/admin/payments/logs" className={subItemClass} /> : null}
						<NavItem label="Content Actions" href="/admin/moderation/logs" className={subItemClass} />
					</CollapsibleGroup>
					<NavItem label="Legal & Compliance" href="/admin/legal" className={subItemClass} />
					<NavItem label="Backups & Recovery" href="/admin/system-risk" className={subItemClass} />
				</CollapsibleGroup>
			</nav>
		</aside>
	)
}
