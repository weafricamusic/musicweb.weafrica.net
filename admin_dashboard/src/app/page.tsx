import Link from 'next/link'

export default function Home() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-50 px-6 dark:bg-black">
      <main className="w-full max-w-lg rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
        <h1 className="text-xl font-semibold">WEAfrica Music Admin</h1>
        <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
          Admin-only control room for catalog, moderation, finance, growth, and notifications.
        </p>
        <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
          Artist, DJ, and consumer login flows are not exposed from this deployment.
        </p>
        <div className="mt-6 flex gap-3">
          <Link
            className="inline-flex h-11 items-center justify-center rounded-xl bg-foreground px-4 text-sm text-background"
              href="/login"
          >
            Admin login
          </Link>
          <Link
            className="inline-flex h-11 items-center justify-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
            href="/admin/dashboard"
          >
            Dashboard
          </Link>
        </div>
      </main>
    </div>
  );
}
