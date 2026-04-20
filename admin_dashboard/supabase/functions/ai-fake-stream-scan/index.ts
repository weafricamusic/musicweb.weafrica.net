// Supabase Edge Function: ai-fake-stream-scan
// Rule-based fake stream detector (no OpenAI). Inserts rows into public.ai_alerts.
//
// Detectors (v1):
// 1) Very short repeated streams (<5s) per user+song
// 2) Same user streaming same song repeatedly
// 3) Abnormal play spike per song (all users)
//
// Auth:
// - If WEAFRICA_ENV/SUPABASE_ENV/NODE_ENV is production/prod, requires header x-ai-scan-token
//   matching env AI_SECURITY_SCAN_TOKEN.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const BUILD_TAG = "2026-02-11-ai-fake-stream-scan-v1";

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

type StreamRow = {
	user_id: string | null;
	song_id: string | null;
	duration_seconds: number | null;
	created_at: string;
};

serve(async (req) => {
	if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });

	const auth = requireTokenIfProd(req);
	if (!auth.ok) return json({ ok: false, error: auth.error }, { status: auth.error === "Forbidden" ? 403 : 500, headers: corsHeaders(req) });

	const url = normalizeEnvOptional("SUPABASE_URL");
	const serviceKey = normalizeEnvOptional("SUPABASE_SERVICE_ROLE_KEY");
	if (!url || !serviceKey) {
		return json({ ok: false, error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, { status: 500, headers: corsHeaders(req) });
	}

	const supabase = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

	const u = new URL(req.url);
	const windowMinutes = Math.max(1, Math.min(120, Number(u.searchParams.get("window_minutes") ?? "10") || 10));
	const repeatStreamsThreshold = Math.max(1, Math.min(1000, Number(u.searchParams.get("repeat_threshold") ?? "20") || 20));
	const shortSeconds = Math.max(1, Math.min(60, Number(u.searchParams.get("short_seconds") ?? "5") || 5));
	const shortStreamsThreshold = Math.max(1, Math.min(1000, Number(u.searchParams.get("short_threshold") ?? "10") || 10));
	const songSpikeThreshold = Math.max(1, Math.min(100000, Number(u.searchParams.get("song_spike_threshold") ?? "200") || 200));

	const sinceIso = new Date(Date.now() - windowMinutes * 60 * 1000).toISOString();

	const { data, error } = await supabase
		.from("song_streams")
		.select("user_id,song_id,duration_seconds,created_at")
		.gte("created_at", sinceIso);

	if (error) return json({ ok: false, error: error.message }, { status: 500, headers: corsHeaders(req) });

	const streams = (data ?? []) as StreamRow[];

	const perUserSongCount = new Map<string, number>();
	const perUserSongShortCount = new Map<string, number>();
	const perSongCount = new Map<string, number>();

	for (const s of streams) {
		const userId = s.user_id ? String(s.user_id) : "";
		const songId = s.song_id ? String(s.song_id) : "";
		const duration = Number(s.duration_seconds ?? 0) || 0;
		if (songId) perSongCount.set(songId, (perSongCount.get(songId) ?? 0) + 1);
		if (!userId || !songId) continue;
		const key = `${userId}::${songId}`;
		perUserSongCount.set(key, (perUserSongCount.get(key) ?? 0) + 1);
		if (duration > 0 && duration < shortSeconds) {
			perUserSongShortCount.set(key, (perUserSongShortCount.get(key) ?? 0) + 1);
		}
	}

	let alertsInserted = 0;
	let suspiciousPairs = 0;
	let suspiciousSongs = 0;

	// 1+2) user+song repeats and short repeats
	for (const [key, totalStreams] of perUserSongCount.entries()) {
		const shortStreams = perUserSongShortCount.get(key) ?? 0;
		if (totalStreams <= repeatStreamsThreshold && shortStreams <= shortStreamsThreshold) continue;

		suspiciousPairs += 1;
		const [userId, songId] = key.split("::");
		const msg = `Suspicious streaming detected: ${totalStreams} plays (short<${shortSeconds}s: ${shortStreams}) for song ${songId} within ${windowMinutes} minutes`;

		const { error: insErr } = await supabase.from("ai_alerts").insert({
			type: "fake_stream",
			reference_id: userId,
			severity: "high",
			message: msg,
		});
		if (!insErr) alertsInserted += 1;
	}

	// 3) abnormal spike for a song across all users
	for (const [songId, cnt] of perSongCount.entries()) {
		if (cnt <= songSpikeThreshold) continue;
		suspiciousSongs += 1;
		const msg = `Abnormal play spike: ${cnt} plays for song ${songId} within ${windowMinutes} minutes`;
		const { error: insErr } = await supabase.from("ai_alerts").insert({
			type: "fake_stream",
			reference_id: `song:${songId}`,
			severity: "medium",
			message: msg,
		});
		if (!insErr) alertsInserted += 1;
	}

	return json(
		{
			ok: true,
			window_minutes: windowMinutes,
			repeat_threshold: repeatStreamsThreshold,
			short_seconds: shortSeconds,
			short_threshold: shortStreamsThreshold,
			song_spike_threshold: songSpikeThreshold,
			since: sinceIso,
			streams: streams.length,
			suspicious_pairs: suspiciousPairs,
			suspicious_songs: suspiciousSongs,
			alerts_inserted: alertsInserted,
		},
		{ status: 200, headers: corsHeaders(req) },
	);
});
