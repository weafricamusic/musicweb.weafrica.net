// Supabase Edge Function: ai-security-scan
// Rule-based security scan (no OpenAI). Inserts rows into public.ai_alerts.
//
// Detectors (v1):
// - Coin abuse: same sender->receiver sends > threshold within 5 minutes.
//
// Auth:
// - If WEAFRICA_ENV/SUPABASE_ENV/NODE_ENV is production/prod, requires header x-ai-scan-token
//   matching env AI_SECURITY_SCAN_TOKEN.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const BUILD_TAG = "2026-02-11-ai-security-scan-v1";

function json(data: unknown, init: ResponseInit = {}): Response {
	const headers = new Headers(init.headers);
	headers.set("content-type", "application/json; charset=utf-8");
	headers.set("x-weafrica-build-tag", BUILD_TAG);
	return new Response(JSON.stringify(data), { ...init, headers });
}

function normalizeEnvOptional(key: string): string | null {
	const v = Deno.env.get(key);
	if (!v) return null;
	const t = v.trim().replace(/^['"]|['"]$/g, "");
	return t ? t : null;
}

function isProductionEnv(): boolean {
	const env = (
		normalizeEnvOptional("WEAFRICA_ENV") ??
		normalizeEnvOptional("SUPABASE_ENV") ??
		normalizeEnvOptional("NODE_ENV") ??
		""
	).toLowerCase();
	return env === "production" || env === "prod";
}

function corsHeaders(req: Request): Record<string, string> {
	const origin = req.headers.get("origin") ?? "*";
	return {
		"access-control-allow-origin": origin,
		"access-control-allow-methods": "GET, POST, OPTIONS",
		"access-control-allow-headers": "content-type, x-ai-scan-token",
		"access-control-max-age": "86400",
		vary: "origin",
	};
}

function requireTokenIfProd(req: Request): { ok: boolean; error?: string } {
	if (!isProductionEnv()) return { ok: true };
	const expected = normalizeEnvOptional("AI_SECURITY_SCAN_TOKEN");
	if (!expected) return { ok: false, error: "AI_SECURITY_SCAN_TOKEN not set" };
	const got = (req.headers.get("x-ai-scan-token") ?? "").trim();
	if (!got || got !== expected) return { ok: false, error: "Forbidden" };
	return { ok: true };
}

serve(async (req) => {
	if (req.method === "OPTIONS") {
		return new Response(null, { status: 204, headers: corsHeaders(req) });
	}

	const auth = requireTokenIfProd(req);
	if (!auth.ok) return json({ ok: false, error: auth.error }, { status: auth.error === "Forbidden" ? 403 : 500, headers: corsHeaders(req) });

	const url = normalizeEnvOptional("SUPABASE_URL");
	const serviceKey = normalizeEnvOptional("SUPABASE_SERVICE_ROLE_KEY");
	if (!url || !serviceKey) {
		return json(
			{ ok: false, error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" },
			{ status: 500, headers: corsHeaders(req) },
		);
	}

	const supabase = createClient(url, serviceKey, {
		auth: { persistSession: false, autoRefreshToken: false },
	});

	// v1 params (tunable via query string)
	const u = new URL(req.url);
	const windowMinutes = Math.max(1, Math.min(60, Number(u.searchParams.get("window_minutes") ?? "5") || 5));
	const thresholdCoins = Math.max(1, Math.min(1_000_000, Number(u.searchParams.get("threshold_coins") ?? "3000") || 3000));

	const sinceIso = new Date(Date.now() - windowMinutes * 60 * 1000).toISOString();

	// Query recent coin send events.
	// We use public.transactions because that's the canonical ledger in this repo.
	const { data: transactions, error } = await supabase
		.from("transactions")
		.select("actor_id,target_type,target_id,coins,created_at,type")
		.eq("type", "gift")
		.gte("created_at", sinceIso);

	if (error) {
		return json({ ok: false, error: error.message }, { status: 500, headers: corsHeaders(req) });
	}

	const grouped = new Map<string, { sender: string; receiver: string; totalCoins: number }>();
	for (const tx of transactions ?? []) {
		const sender = (tx as any).actor_id ? String((tx as any).actor_id) : "";
		const receiver = (tx as any).target_id ? String((tx as any).target_id) : "";
		const targetType = (tx as any).target_type ? String((tx as any).target_type) : "";
		const coins = Number((tx as any).coins ?? 0) || 0;
		if (!sender || !receiver) continue;
		if (targetType && targetType !== "dj" && targetType !== "artist") continue;

		const key = `${sender}::${receiver}`;
		const existing = grouped.get(key);
		if (existing) existing.totalCoins += coins;
		else grouped.set(key, { sender, receiver, totalCoins: coins });
	}

	let alertsInserted = 0;
	for (const g of grouped.values()) {
		if (g.totalCoins <= thresholdCoins) continue;

		const message = `User ${g.sender} sent ${g.totalCoins} coins to ${g.receiver} within ${windowMinutes} minutes`;

		const { error: insErr } = await supabase.from("ai_alerts").insert({
			type: "coin_abuse",
			reference_id: g.sender,
			severity: "high",
			message,
		});

		if (!insErr) alertsInserted += 1;
	}

	return json(
		{
			ok: true,
			window_minutes: windowMinutes,
			threshold_coins: thresholdCoins,
			since: sinceIso,
			transactions: (transactions ?? []).length,
			alerts_inserted: alertsInserted,
		},
		{ status: 200, headers: corsHeaders(req) },
	);
});
