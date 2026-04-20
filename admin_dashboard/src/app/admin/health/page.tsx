import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'

type HealthStatus = {
  service?: string | null
  status?: string | null
  response_time_ms?: number | null
  error_message?: string | null
  checked_at?: string | null
}

type HealthSummary = Record<string, HealthStatus | null>

type HealthData = {
  summary: HealthSummary
  history: Record<string, HealthStatus[]>
}

const SERVICES = ['api', 'database', 'redis', 'agora'] as const

function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'
  return date.toLocaleString()
}

function formatLatency(value: number | null | undefined): string {
  if (value == null || Number.isNaN(Number(value))) return '—'
  return `${Math.round(Number(value))} ms`
}

function toneForStatus(status: string | null | undefined): string {
  if (status === 'healthy') return 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'
  if (status === 'degraded') return 'border-amber-500/30 bg-amber-500/10 text-amber-200'
  if (status === 'down') return 'border-red-500/30 bg-red-500/10 text-red-200'
  return 'border-white/10 bg-white/5 text-gray-300'
}

async function loadHealthData(): Promise<HealthData> {
  try {
    const summary = await adminBackendFetchJson<HealthSummary>('/admin/health')
    const historyEntries = await Promise.all(
      SERVICES.map(async (service) => {
        const history = await adminBackendFetchJson<HealthStatus[]>(`/admin/health/${service}?hours=24`).catch(() => [])
        return [service, Array.isArray(history) ? history.slice(0, 5) : []] as const
      }),
    )

    return {
      summary,
      history: Object.fromEntries(historyEntries),
    }
  } catch {
    return {
      summary: Object.fromEntries(SERVICES.map((service) => [service, { service, status: 'unknown' }])) as HealthSummary,
      history: Object.fromEntries(SERVICES.map((service) => [service, []])),
    }
  }
}

export default async function HealthOverviewPage() {
  const user = await verifyFirebaseSessionCookie()
  const health = await loadHealthData()

  return (
    <div className="space-y-6">
      <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
        <h1 className="text-lg font-semibold">System Health</h1>
        <p className="mt-1 text-sm text-gray-400">Live overview of auth, live, payments, and DB.</p>
        <p className="mt-3 text-xs text-gray-500">Signed in as {user?.email ?? user?.uid ?? '—'}</p>
      </div>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
        {SERVICES.map((service) => {
          const latest = health.summary[service]
          return (
            <Card key={service} title={service[0].toUpperCase() + service.slice(1)}>
              <StatusBadge status={latest?.status ?? 'unknown'} />
              <div className="mt-4 space-y-2 text-sm">
                <Item label="Latest status" value={latest?.status ?? 'unknown'} />
                <Item label="Response time" value={formatLatency(latest?.response_time_ms)} />
                <Item label="Last checked" value={formatDateTime(latest?.checked_at)} />
                <Item label="Last error" value={latest?.error_message?.trim() || '—'} />
              </div>
            </Card>
          )
        })}
      </div>

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
        {SERVICES.map((service) => {
          const history = health.history[service] ?? []
          return (
            <div key={`${service}-history`} className="rounded-2xl border border-white/10 bg-white/5 p-6">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h2 className="text-base font-medium">{service[0].toUpperCase() + service.slice(1)} history</h2>
                  <p className="mt-1 text-sm text-gray-400">Most recent backend checks in the last 24 hours.</p>
                </div>
                <StatusBadge status={health.summary[service]?.status ?? 'unknown'} compact />
              </div>

              {history.length ? (
                <div className="mt-4 space-y-3">
                  {history.map((entry, index) => (
                    <div key={`${service}-${entry.checked_at ?? index}`} className="rounded-xl border border-white/10 bg-black/20 p-4">
                      <div className="flex items-center justify-between gap-3 text-sm">
                        <span className="font-medium">{entry.status ?? 'unknown'}</span>
                        <span className="text-gray-500">{formatDateTime(entry.checked_at)}</span>
                      </div>
                      <div className="mt-2 grid grid-cols-1 gap-2 text-xs text-gray-400 sm:grid-cols-2">
                        <div>Latency: {formatLatency(entry.response_time_ms)}</div>
                        <div>Error: {entry.error_message?.trim() || '—'}</div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="mt-4 rounded-xl border border-white/10 bg-black/20 p-4 text-sm text-gray-400">
                  No recent checks recorded by the backend for this service.
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
      <h2 className="text-base font-medium">{title}</h2>
      <div className="mt-4 space-y-2 text-sm">{children}</div>
    </div>
  )
}

function Item({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-gray-400">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  )
}

function StatusBadge({ status, compact = false }: { status: string; compact?: boolean }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium ${toneForStatus(status)} ${compact ? '' : 'w-fit'}`}
    >
      {status}
    </span>
  )
}
