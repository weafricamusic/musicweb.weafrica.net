import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminContext } from '@/lib/admin/session'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import SubscriptionsToolsClient from './SubscriptionsToolsClient'
import { isConsumerPlan, isArtistPlan, isDjPlan } from '@/lib/subscription/admin-plan-scope'

export const runtime = 'nodejs'

type PlanRow = {
  plan_id: string
  name: string
  price_mwk: number
  billing_interval: string
  coins_multiplier: number
  ads_enabled: boolean
  can_participate_battles: boolean
  battle_priority: string
  analytics_level: string
  content_access: string
  content_limit_ratio: number | null
  featured_status: boolean
  is_active?: boolean | null
  features?: Record<string, unknown> | null
  created_at?: string | null
  updated_at?: string | null
}

type PlanCountRow = { plan_id: string; active_count: string | number }

export default async function SubscriptionsAdminPage() {
  const ctx = await getAdminContext()
  if (!ctx || !ctx.permissions.can_manage_finance) {
    return (
      <div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
        <h1 className="text-lg font-semibold">Access denied</h1>
        <p className="mt-2 text-sm text-gray-400">You do not have finance permissions.</p>
        <div className="mt-4">
          <Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
            Return to dashboard
          </Link>
        </div>
      </div>
    )
  }

  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) return <ServiceRoleRequired title="Service role required for subscriptions" />

  // Some deployments may not have the newer `audience` column yet.
  let plans: any[] | null = null
  let plansError: any = null
  ;({ data: plans, error: plansError } = await supabase
    .from('subscription_plans')
    .select(
      'audience,plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,is_active,features,created_at,updated_at',
    )
    .order('price_mwk', { ascending: true }))

  if (plansError && String(plansError.message ?? '').includes('column subscription_plans.audience does not exist')) {
    ;({ data: plans, error: plansError } = await supabase
      .from('subscription_plans')
      .select(
        'plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,is_active,features,created_at,updated_at',
      )
      .order('price_mwk', { ascending: true }))
  }

  const { data: planCounts } = await supabase.rpc('subscription_plan_counts', { p_country_code: null })

  const consumerPlans = ((plans ?? []) as PlanRow[]).filter((plan) => isConsumerPlan(plan))
  const artistPlans = ((plans ?? []) as PlanRow[]).filter((plan) => isArtistPlan(plan))
  const djPlans = ((plans ?? []) as PlanRow[]).filter((plan) => isDjPlan(plan))

  const countsByPlan = new Map<string, number>(
    ((planCounts ?? []) as PlanCountRow[]).map((r) => [String(r.plan_id), Number(r.active_count ?? 0)]),
  )

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Subscriptions</h1>
          <p className="mt-1 text-sm text-gray-400">Manage Consumer, Artist, and DJ subscription plans and assignments.</p>
        </div>
        <Link href="/admin/payments" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
          Back to finance
        </Link>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
          <h2 className="text-base font-semibold">Consumers</h2>
          <p className="mt-1 text-sm text-gray-400">Free/Premium/Platinum and consumer buckets.</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <Link href="/admin/subscriptions/consumers/active" className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5">
              Active
            </Link>
            <Link href="/admin/subscriptions/user-subscriptions?audience=consumer" className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5">
              User subs
            </Link>
          </div>
        </div>
        <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
          <h2 className="text-base font-semibold">Artists</h2>
          <p className="mt-1 text-sm text-gray-400">Artist-specific plans and features.</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <Link href="/admin/subscriptions/artists" className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5">
              Open
            </Link>
            <Link href="/admin/subscriptions/user-subscriptions?audience=artist" className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5">
              User subs
            </Link>
          </div>
        </div>
        <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
          <h2 className="text-base font-semibold">DJs</h2>
          <p className="mt-1 text-sm text-gray-400">DJ-specific plans and features.</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <Link href="/admin/subscriptions/djs" className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5">
              Open
            </Link>
            <Link href="/admin/subscriptions/user-subscriptions?audience=dj" className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5">
              User subs
            </Link>
          </div>
        </div>
      </div>

      {plansError ? (
        <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
          Failed to load subscription plans: {plansError.message}. Apply the subscriptions migration in Supabase.
        </div>
      ) : null}

      <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
        <h2 className="text-base font-semibold">Plan catalog</h2>
        <p className="mt-1 text-sm text-gray-400">Coins multiplier affects earnings from actions (uploads, battles, daily bonus, etc.).</p>

        <div className="mt-4 overflow-auto">
          <table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
            <thead>
              <tr className="text-gray-400">
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Plan</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Price (MWK)</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Duration</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Ads</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Coins</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Battles</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Analytics</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Content</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Features (JSON)</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Created</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Updated</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Active subs</th>
              </tr>
            </thead>
            <tbody>
              {consumerPlans.length ? (
                consumerPlans.map((p) => (
                  <tr key={p.plan_id} className="hover:bg-white/5">
                    <td className="border-b border-white/10 py-3 pr-4 font-medium">{p.name}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{Number(p.price_mwk ?? 0).toLocaleString()}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{String(p.billing_interval ?? 'month') === 'month' ? '30 days (monthly)' : String(p.billing_interval)}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.ads_enabled ? 'Enabled' : 'Ad-free'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">×{Number(p.coins_multiplier ?? 1)}</td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      {p.can_participate_battles ? (p.battle_priority === 'priority' ? 'Priority' : 'Yes') : 'No'}
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.analytics_level}</td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      {p.content_access}
                      {p.content_limit_ratio != null ? ` (${Math.round(Number(p.content_limit_ratio) * 100)}%)` : ''}
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      <pre className="max-w-[360px] whitespace-pre-wrap break-words rounded-lg bg-black/20 p-2 text-xs text-gray-200 border border-white/10">
                        {JSON.stringify(p.features ?? {}, null, 2)}
                      </pre>
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      {p.is_active === false ? (
                        <span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">Inactive</span>
                      ) : (
                        <span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">Active</span>
                      )}
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4 text-xs text-gray-300">{p.created_at ? new Date(p.created_at).toLocaleString() : '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4 text-xs text-gray-300">{p.updated_at ? new Date(p.updated_at).toLocaleString() : '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{countsByPlan.get(p.plan_id) ?? 0}</td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={13} className="py-6 text-sm text-gray-400">
                    No plans found. Apply the subscriptions migration in Supabase.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {artistPlans.length ? (
        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-base font-semibold">Artist plans</h2>
          <p className="mt-1 text-sm text-gray-400">Artist-specific catalog from the same subscription_plans table.</p>
          <div className="mt-4 overflow-auto">
            <table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
              <thead>
                <tr className="text-gray-400">
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Plan</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Price (MWK)</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Duration</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Ads</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Coins</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Battles</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Analytics</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Content</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Features (JSON)</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Created</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Updated</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Active subs</th>
                </tr>
              </thead>
              <tbody>
                {artistPlans.map((p) => (
                  <tr key={p.plan_id} className="hover:bg-white/5">
                    <td className="border-b border-white/10 py-3 pr-4 font-medium">{p.name}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{Number(p.price_mwk ?? 0).toLocaleString()}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{String(p.billing_interval ?? 'month') === 'month' ? '30 days (monthly)' : String(p.billing_interval)}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.ads_enabled ? 'Enabled' : 'Ad-free'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">×{Number(p.coins_multiplier ?? 1)}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.can_participate_battles ? (p.battle_priority === 'priority' ? 'Priority' : 'Yes') : 'No'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.analytics_level}</td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      {p.content_access}
                      {p.content_limit_ratio != null ? ` (${Math.round(Number(p.content_limit_ratio) * 100)}%)` : ''}
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      <pre className="max-w-[360px] whitespace-pre-wrap break-words rounded-lg bg-black/20 p-2 text-xs text-gray-200 border border-white/10">
                        {JSON.stringify(p.features ?? {}, null, 2)}
                      </pre>
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      {p.is_active === false ? (
                        <span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">Inactive</span>
                      ) : (
                        <span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">Active</span>
                      )}
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4 text-xs text-gray-300">{p.created_at ? new Date(p.created_at).toLocaleString() : '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4 text-xs text-gray-300">{p.updated_at ? new Date(p.updated_at).toLocaleString() : '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{countsByPlan.get(p.plan_id) ?? 0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      {djPlans.length ? (
        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-base font-semibold">DJ plans</h2>
          <p className="mt-1 text-sm text-gray-400">DJ-specific catalog from the same subscription_plans table.</p>
          <div className="mt-4 overflow-auto">
            <table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
              <thead>
                <tr className="text-gray-400">
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Plan</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Price (MWK)</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Duration</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Ads</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Coins</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Battles</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Analytics</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Content</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Features (JSON)</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Created</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Updated</th>
                  <th className="border-b border-white/10 py-3 pr-4 font-medium">Active subs</th>
                </tr>
              </thead>
              <tbody>
                {djPlans.map((p) => (
                  <tr key={p.plan_id} className="hover:bg-white/5">
                    <td className="border-b border-white/10 py-3 pr-4 font-medium">{p.name}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{Number(p.price_mwk ?? 0).toLocaleString()}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{String(p.billing_interval ?? 'month') === 'month' ? '30 days (monthly)' : String(p.billing_interval)}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.ads_enabled ? 'Enabled' : 'Ad-free'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">×{Number(p.coins_multiplier ?? 1)}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.can_participate_battles ? (p.battle_priority === 'priority' ? 'Priority' : 'Yes') : 'No'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{p.analytics_level}</td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      {p.content_access}
                      {p.content_limit_ratio != null ? ` (${Math.round(Number(p.content_limit_ratio) * 100)}%)` : ''}
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      <pre className="max-w-[360px] whitespace-pre-wrap break-words rounded-lg bg-black/20 p-2 text-xs text-gray-200 border border-white/10">
                        {JSON.stringify(p.features ?? {}, null, 2)}
                      </pre>
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      {p.is_active === false ? (
                        <span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">Inactive</span>
                      ) : (
                        <span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">Active</span>
                      )}
                    </td>
                    <td className="border-b border-white/10 py-3 pr-4 text-xs text-gray-300">{p.created_at ? new Date(p.created_at).toLocaleString() : '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4 text-xs text-gray-300">{p.updated_at ? new Date(p.updated_at).toLocaleString() : '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{countsByPlan.get(p.plan_id) ?? 0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      <div className="grid gap-6 md:grid-cols-2">
        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-base font-semibold">Plan editor</h2>
          <p className="mt-1 text-sm text-gray-400">Update pricing, duration, features JSON, and enable/disable plans for all audiences.</p>
          <p className="mt-2 text-xs text-gray-500">Free plan is protected and must stay active.</p>
          <Link href="/admin/subscriptions/plans" className="mt-4 inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
            Open plan editor
          </Link>
        </div>

        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-base font-semibold">Content access rules</h2>
          <p className="mt-1 text-sm text-gray-400">Define what each plan can view or do (songs/videos %, categories, battles, VIP content).</p>
          <Link href="/admin/subscriptions/content-access" className="mt-4 inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
            Manage content rules
          </Link>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-base font-semibold">Implementation flow</h2>
          <p className="mt-1 text-sm text-gray-400">Admin dashboard is the source of truth for subscriptions.</p>
          <ul className="mt-4 space-y-2 text-sm text-gray-300">
            <li>1) Configure consumer Free / Premium / Platinum in <b>Plan editor</b> (ads, coins, battles, analytics, featured status).</li>
            <li>2) Define plan content visibility in <b>Content access rules</b> (limited / standard / exclusive).</li>
            <li>3) Configure upgrade nudges and VIP offers in <b>Promotions</b>.</li>
            <li>4) Connect payment gateway (PayChangu) via webhook to activate/extend subscriptions.</li>
            <li>5) Monitor subscriptions, payments, renewals; use admin tools to extend/cancel/refund adjustments.</li>
          </ul>
        </div>

        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-base font-semibold">Payment gateway (PayChangu)</h2>
          <p className="mt-1 text-sm text-gray-400">
            The admin dashboard receives PayChangu webhooks and applies subscription state changes (idempotent upsert + ledger entries).
          </p>
          <div className="mt-4 space-y-2 text-sm text-gray-300">
            <div>
              <b>Webhook:</b> <span className="font-mono">POST /api/webhooks/paychangu</span>
            </div>
            <div>
              <b>Required env:</b> <span className="font-mono">PAYCHANGU_WEBHOOK_SECRET</span>
            </div>
            <div>
              <b>Expected metadata:</b> <span className="font-mono">user_id</span>, <span className="font-mono">plan_id</span>, optional <span className="font-mono">months</span>, <span className="font-mono">country_code</span> for consumer plans
            </div>
            <div>
              <b>Expiry job:</b> <span className="font-mono">POST /api/cron/subscriptions/expire</span> (header <span className="font-mono">x-cron-secret</span> = <span className="font-mono">SUBSCRIPTIONS_CRON_SECRET</span>)
            </div>
          </div>
          <div className="mt-4 flex flex-wrap gap-3">
            <Link href="/admin/subscriptions/payments" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
              Monitor payment events
            </Link>
            <Link href="/admin/subscriptions/user-subscriptions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
              Monitor user subscriptions
            </Link>
          </div>
        </div>
      </div>

      <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-base font-semibold">Payments & renewals</h2>
          <p className="mt-1 text-sm text-gray-400">Monitor consumer subscription status and manually extend, cancel, or record refund adjustments.</p>
        <div className="mt-4 flex flex-wrap gap-3">
          <Link href="/admin/subscriptions/user-subscriptions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
            Manage user subscriptions
          </Link>
          <Link href="/admin/subscriptions/payments" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
            View subscription payments
          </Link>
        </div>
      </div>

      <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
        <h2 className="text-base font-semibold">Promotions & notifications</h2>
        <p className="mt-1 text-sm text-gray-400">Create upgrade nudges and VIP announcements by subscription level.</p>
        <Link href="/admin/subscriptions/promotions" className="mt-4 inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
          Manage promotions
        </Link>
      </div>

      <SubscriptionsToolsClient />

      <div className="rounded-2xl border border-white/10 bg-white/5 p-6 text-sm text-gray-300">
        <b>Note:</b> Country config has global toggles like <span className="font-mono">ads_enabled</span> and <span className="font-mono">premium_enabled</span>.
        For production gating, use both: country-level availability + user plan entitlements.
      </div>
    </div>
  )
}
