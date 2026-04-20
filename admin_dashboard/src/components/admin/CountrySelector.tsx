'use client'

export default function CountrySelector({ countries, current }: { countries: { country_code: string; country_name: string }[]; current: string }) {
  return (
    <form action="/api/admin/country" method="post" className="flex items-center gap-2">
      <label className="text-xs text-gray-400">Country</label>
      <select
        name="code"
        defaultValue={current}
        className="h-9 rounded-lg bg-white/5 border border-white/10 px-2 text-sm"
        onChange={(e) => {
          (e.target.closest('form') as HTMLFormElement | null)?.requestSubmit()
        }}
      >
        {countries.map((c) => (
          <option key={c.country_code} value={c.country_code}>
            {c.country_name} ({c.country_code})
          </option>
        ))}
      </select>
    </form>
  )
}
