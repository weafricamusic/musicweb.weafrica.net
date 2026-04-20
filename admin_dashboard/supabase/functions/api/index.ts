// @ts-nocheck
// Supabase Edge Function: api
// Public endpoint (deployed with --no-verify-jwt) to generate a PayChangu checkout URL.
//
// Env:
// - PAYCHANGU_CHECKOUT_URL (fallback)
// - PAYCHANGU_CHECKOUT_URL_<PLANID> (override) e.g. PAYCHANGU_CHECKOUT_URL_PREMIUM
//
// Body (JSON): { plan_id?: string, user_id?: string, months?: number, country_code?: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const BUILD_TAG = "2026-02-07-battle-authfix";

function isProductionEnv(): boolean {
	const env = (
		normalizeEnvOptional("WEAFRICA_ENV") ??
		normalizeEnvOptional("SUPABASE_ENV") ??
		normalizeEnvOptional("NODE_ENV") ??
		""
	).toLowerCase();
	if (env === "production" || env === "prod") return true;
	return false;
}

function isDiagAccessAllowed(req: Request): boolean {
	// In production, hide /diag from end-users.
	if (!isProductionEnv()) return true;
	if (isTestAccessAllowed(req)) return true;
	const expected =
		normalizeEnvOptional("WEAFRICA_DEBUG_DIAG_TOKEN") ??
		normalizeEnvOptional("WEAFRICA_DIAG_TOKEN");
	if (!expected) return false;
	const got = (
		req.headers.get("x-debug-token") ??
		req.headers.get("x-weafrica-diag-token") ??
		req.headers.get("x-diag-token") ??
		""
	).trim();
	return Boolean(got) && got === expected;
}

function json(data: unknown, init: ResponseInit = {}): Response {
	const headers = new Headers(init.headers);
	headers.set("content-type", "application/json; charset=utf-8");
	headers.set("x-weafrica-build-tag", BUILD_TAG);
	return new Response(JSON.stringify(data), { ...init, headers });
}

function withBuildTag(headers: HeadersInit | undefined): Headers {
	const h = new Headers(headers);
	h.set("x-weafrica-build-tag", BUILD_TAG);
	return h;
}

function corsHeaders(req: Request): Record<string, string> {
	// If you want to lock this down, replace '*' with your app origin(s).
	const origin = req.headers.get("origin") ?? "*";
	return {
		"access-control-allow-origin": origin,
		"access-control-allow-methods": "GET, POST, OPTIONS",
		"access-control-allow-headers":
			"content-type, authorization, x-weafrica-test-token, x-weafrica-diag-token, x-debug-token, x-diag-token, x-ai-scan-token",
		"access-control-max-age": "86400",
		"vary": "origin",
	};
}

function isAiScanAllowed(req: Request): boolean {
	// In dev/staging, allow if test token enabled. In prod, require AI_SECURITY_SCAN_TOKEN.
	if (!isProductionEnv()) return isTestAccessAllowed(req);
	const expected = normalizeEnvOptional("AI_SECURITY_SCAN_TOKEN");
	if (!expected) return false;
	const got = (req.headers.get("x-ai-scan-token") ?? "").trim();
	return Boolean(got) && got === expected;
}

function normalizeEnvOptional(key: string): string | null {
	const v = Deno.env.get(key);
	if (!v) return null;
	const t = v.trim().replace(/^['"]|['"]$/g, "");
	return t ? t : null;
}

function isTruthyEnv(key: string): boolean {
	const v = normalizeEnvOptional(key);
	if (!v) return false;
	return ["1", "true", "yes", "on", "enabled"].includes(v.toLowerCase());
}

function toEnvSuffix(planId: string): string {
	return planId
		.trim()
		.toUpperCase()
		.replace(/[^A-Z0-9]+/g, "_")
		.replace(/^_+|_+$/g, "");
}

function resolveCheckoutUrl(planId: string | null): { url: string | null; sourceKey: string | null } {
	if (planId) {
		const suffix = toEnvSuffix(planId);
		const keys = [`PAYCHANGU_CHECKOUT_URL_${suffix}`, `PAYCHANGU_CHECKOUT_URL_${planId.toUpperCase()}`];
		for (const key of keys) {
			const v = normalizeEnvOptional(key);
			if (v) return { url: v, sourceKey: key };
		}
	}

	const fallback = normalizeEnvOptional("PAYCHANGU_CHECKOUT_URL");
	return { url: fallback, sourceKey: fallback ? "PAYCHANGU_CHECKOUT_URL" : null };
}

function applyTemplate(url: string, vars: Record<string, string | number | null | undefined>): string {
	let out = url;
	for (const [k, v] of Object.entries(vars)) {
		out = out.replaceAll(`{{${k}}}`, v == null ? "" : String(v));
	}
	return out;
}

function addQueryParams(url: string, params: Record<string, string | number | null | undefined>): string {
	try {
		const u = new URL(url);
		for (const [k, v] of Object.entries(params)) {
			if (v == null || String(v).trim() === "") continue;
			if (u.searchParams.has(k)) continue;
			u.searchParams.set(k, String(v));
		}
		return u.toString();
	} catch {
		return url;
	}
}

type PromotionPublicRow = {
	id: string;
	title: string | null;
	description: string | null;
	image_url: string | null;
	target_plan: string | null;
	priority: number | null;
	starts_at: string | null;
	ends_at: string | null;
	created_at: string;
};

type SubscriptionPromotionRow = {
	id: string;
	target_plan_id: string | null;
	title: string | null;
	body: string;
	starts_at: string | null;
	ends_at: string | null;
	created_at: string;
};

type ContentPromotionRow = {
	id: string;
	title: string;
	description: string | null;
	target_plan: string;
	is_active: boolean;
	starts_at: string | null;
	ends_at: string | null;
	created_at: string;
};

type PushRegisterBody = {
	// Preferred field name.
	token?: string;
	// Alias to support older/mobile naming.
	fcm_token?: string;
	platform?: "ios" | "android" | "web" | "unknown";
	device_id?: string | null;
	country_code?: string | null;
	topics?: unknown;
	app_version?: string | null;
	device_model?: string | null;
	locale?: string | null;
};

function mustEnv(key: string): string {
	const v = normalizeEnvOptional(key);
	if (!v) throw new Error(`Missing ${key}`);
	return v;
}

function normalizeChannelId(v: unknown): string | null {
	if (typeof v !== "string") return null;
	const s = v.trim();
	if (!s) return null;
	if (s.length > 128) return null;
	// Keep it predictable: Agora supports letters/numbers/_/-.
	if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(s)) return null;
	return s;
}

function normalizeUid(v: unknown): number {
	if (typeof v === "number" && Number.isFinite(v)) return Math.max(0, Math.floor(v));
	if (typeof v === "string" && v.trim()) {
		const n = Number(v);
		if (Number.isFinite(n)) return Math.max(0, Math.floor(n));
	}
	return 0;
}

function normalizeBattleIdRaw(v: unknown): string | null {
	if (typeof v !== "string" && typeof v !== "number") return null;
	const s = String(v).trim();
	return s ? s : null;
}

function isUuidLike(v: string): boolean {
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

function parsePositiveInt(v: string): number | null {
	if (!/^[0-9]+$/.test(v)) return null;
	const n = Number(v);
	if (!Number.isFinite(n)) return null;
	const nn = Math.floor(n);
	return nn > 0 ? nn : null;
}

async function requireAppAuth(req: Request): Promise<{ ok: true; uid: string } | { ok: false; status: number; error: string }> {
	const authHeader = req.headers.get("authorization") ?? "";
	const hasAuthHeader = Boolean(authHeader.trim());
	const hasFirebase = Boolean(normalizeEnvOptional("FIREBASE_PROJECT_ID"));

	if (hasAuthHeader || hasFirebase) {
		const verified = await verifyFirebaseIdToken(req);
		if (verified.ok) return verified;
		if (!isTestAccessAllowed(req)) return { ok: false, status: 401, error: verified.error };
		return { ok: true, uid: "test" };
	}

	if (isTestAccessAllowed(req)) return { ok: true, uid: "test" };
	return { ok: false, status: 401, error: "Auth required." };
}

async function verifyFirebaseIdToken(req: Request): Promise<{ ok: true; uid: string } | { ok: false; error: string; missingConfig?: boolean }> {
	const auth = req.headers.get("authorization") ?? "";
	const m = auth.match(/^Bearer\s+(.+)$/i);
	if (!m) return { ok: false, error: "Missing Authorization: Bearer <idToken>" };
	const idToken = m[1]?.trim();
	if (!idToken || idToken === "null" || idToken === "undefined") return { ok: false, error: "Missing bearer token" };

	const projectId = normalizeEnvOptional("FIREBASE_PROJECT_ID");
	if (!projectId) {
		return { ok: false, error: "Firebase auth not configured (missing FIREBASE_PROJECT_ID)", missingConfig: true };
	}

	// Lightweight verification suitable for Edge Functions (no local JWK caching).
	// This validates signature + expiry on Google's side.
	const url = `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`;
	const res = await fetch(url);
	const payload = (await res.json().catch(() => null)) as any;
	if (!res.ok) {
		const raw = typeof payload?.error_description === "string" ? payload.error_description : "Invalid Firebase token";
		const rawNorm = raw.trim();
		// Common response from tokeninfo when clients accidentally send the wrong token type.
		if (rawNorm.toLowerCase() === "invalid value") {
			return {
				ok: false,
				error:
					"Invalid Firebase ID token. Ensure you are sending a Firebase Auth *ID token* (JWT from getIdToken()), not an access token / Supabase JWT / null.",
			};
		}
		return { ok: false, error: rawNorm || "Invalid Firebase token" };
	}

	const aud = typeof payload?.aud === "string" ? payload.aud : null;
	const iss = typeof payload?.iss === "string" ? payload.iss : null;
	if (aud !== projectId || iss !== `https://securetoken.google.com/${projectId}`) {
		return { ok: false, error: "Firebase token project mismatch" };
	}

	const uid = (typeof payload?.user_id === "string" && payload.user_id) || (typeof payload?.sub === "string" && payload.sub) || null;
	if (!uid) return { ok: false, error: "Firebase token missing uid" };
	return { ok: true, uid };
}

function isTestAccessAllowed(req: Request): boolean {
	if (!isTruthyEnv("WEAFRICA_ENABLE_TEST_ROUTES")) return false;
	const expected = normalizeEnvOptional("WEAFRICA_TEST_TOKEN");
	if (!expected) return false;
	const got = (req.headers.get("x-weafrica-test-token") ?? "").trim();
	return Boolean(got) && got === expected;
}

async function handleAgoraToken(req: Request): Promise<Response> {
	const body = (await req.json().catch(() => null)) as any;
	const channelId = normalizeChannelId(
		body?.channel_id ?? body?.channelId ?? body?.channelName ?? body?.channel ?? body?.channel_name,
	);
	if (!channelId) return json({ ok: false, error: "Missing/invalid channel_id" }, { status: 400 });

	const rawRole = typeof body?.role === "string" ? body.role.trim().toLowerCase() : "";
	const roleNormalized = rawRole || "broadcaster";

	const ttlRaw = Number(body?.ttl_seconds ?? body?.ttl ?? 3600);
	const ttlSeconds = Number.isFinite(ttlRaw) ? Math.max(60, Math.min(24 * 3600, Math.floor(ttlRaw))) : 3600;
	const uid = normalizeUid(body?.uid);

	const appId = mustEnv("AGORA_APP_ID");
	const certificate = mustEnv("AGORA_APP_CERTIFICATE");

	// Auth policy:
	// - audience/subscriber tokens: allowed without Firebase or test headers.
	// - broadcaster/publisher tokens: require Firebase ID token OR (if enabled) the test-token header.
	const requiresAuth = roleNormalized === "broadcaster" || roleNormalized === "publisher";
	if (requiresAuth) {
		const authHeader = req.headers.get("authorization") ?? "";
		if (authHeader.trim()) {
			const verified = await verifyFirebaseIdToken(req);
			if (!verified.ok) return json({ ok: false, error: verified.error }, { status: 401 });
		} else if (!isTestAccessAllowed(req)) {
			return json({ ok: false, error: "Missing Authorization: Bearer <idToken>" }, { status: 401 });
		}
	}

	const rtcRole: AgoraRtcRole | null =
		roleNormalized === "broadcaster" || roleNormalized === "publisher"
			? "publisher"
			: roleNormalized === "audience" || roleNormalized === "subscriber"
				? "subscriber"
				: null;

	if (!rtcRole) {
		return json(
			{ ok: false, error: "Invalid role. Use broadcaster|audience or publisher|subscriber." },
			{ status: 400 },
		);
	}

	const now = Math.floor(Date.now() / 1000);
	const expiresAt = now + ttlSeconds;
	const token = await buildAgoraRtcToken({
		appId,
		appCertificate: certificate,
		channelName: channelId,
		uid,
		role: rtcRole,
		expireTs: expiresAt,
	});

	return json(
		{
			ok: true,
			app_id: appId,
			channel_id: channelId,
			uid,
			expires_at: expiresAt,
			token,
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleBattleStatus(req: Request, battleIdRaw: string): Promise<Response> {
	const supabase = makeSupabaseAdmin();
	const battleIdInt = parsePositiveInt(battleIdRaw);
	const battleIdUuid = isUuidLike(battleIdRaw) ? battleIdRaw : null;

	// Primary: live_battles (if present). Support either uuid battle_id or integer id.
	if (battleIdUuid) {
		const res = await supabase.from("live_battles").select("*").eq("battle_id", battleIdUuid).maybeSingle();
		if (!res.error) {
			if (!res.data) return json({ ok: false, error: "not_found", battle_id: battleIdRaw }, { status: 404, headers: { "cache-control": "no-store" } });
			return json({ ok: true, battle_id: battleIdRaw, battle: res.data }, { status: 200, headers: { "cache-control": "no-store" } });
		}
		if (!isMissingTable(res.error) && !isMissingColumn(res.error, "battle_id")) {
			return json(
				{ ok: false, error: "db_error", message: res.error.message, battle_id: battleIdRaw },
				{ status: 500, headers: { "cache-control": "no-store" } },
			);
		}
	}

	if (battleIdInt) {
		// Try live_battles.id first (common bigserial).
		const resById = await supabase.from("live_battles").select("*").eq("id", battleIdInt).maybeSingle();
		if (!resById.error) {
			if (resById.data) return json({ ok: true, battle_id: battleIdRaw, battle: resById.data }, { status: 200, headers: { "cache-control": "no-store" } });
		}
		// If this fails because table doesn't exist, we'll fall back to live_streams.
		if (resById.error && !isMissingTable(resById.error) && !isUuidSyntaxError(resById.error)) {
			return json(
				{ ok: false, error: "db_error", message: resById.error.message, battle_id: battleIdRaw },
				{ status: 500, headers: { "cache-control": "no-store" } },
			);
		}
	}

	// Fallback: live_streams keyed by integer id.
	const stream = battleIdInt
		? await supabase.from("live_streams").select("*").eq("id", battleIdInt).maybeSingle()
		: ({ data: null, error: null } as any);
	if (stream.error) {
		if (isMissingTable(stream.error)) {
			return json(
				{ ok: false, error: "not_found", battle_id: battleIdRaw, hint: "live_battles/live_streams tables not found" },
				{ status: 404, headers: { "cache-control": "no-store" } },
			);
		}
		return json(
			{ ok: false, error: "db_error", message: stream.error.message, battle_id: battleIdRaw },
			{ status: 500, headers: { "cache-control": "no-store" } },
		);
	}
	if (!stream.data) {
		return json({ ok: false, error: "not_found", battle_id: battleIdRaw }, { status: 404, headers: { "cache-control": "no-store" } });
	}

	return json(
		{ ok: true, battle_id: battleIdRaw, battle: stream.data, source: "live_streams" },
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleBattleReady(req: Request): Promise<Response> {
	const auth = await requireAppAuth(req);
	if (!auth.ok) return json({ ok: false, error: "unauthorized", message: auth.error }, { status: auth.status });

	const body = (await req.json().catch(() => null)) as any;
	const battleIdRaw = normalizeBattleIdRaw(body?.battle_id ?? body?.battleId ?? body?.battle);
	if (!battleIdRaw) return json({ ok: false, error: "invalid_request", message: "Missing/invalid battle_id" }, { status: 400 });
	const battleIdInt = parsePositiveInt(battleIdRaw);
	const battleIdUuid = isUuidLike(battleIdRaw) ? battleIdRaw : null;
	if (!battleIdInt && !battleIdUuid) {
		return json({ ok: false, error: "invalid_request", message: "battle_id must be a positive integer or uuid" }, { status: 400 });
	}

	const supabase = makeSupabaseAdmin();

	// Best effort: update live_battles if available; otherwise return not_supported.
	const updatePatch = { ready: true, ready_at: new Date().toISOString(), ready_by_uid: auth.uid };
	const update = battleIdUuid
		? await supabase.from("live_battles").update(updatePatch).eq("battle_id", battleIdUuid).select("*").maybeSingle()
		: battleIdInt
			? await supabase.from("live_battles").update(updatePatch).eq("id", battleIdInt).select("*").maybeSingle()
			: ({ data: null, error: null } as any);

	if (update.error) {
		if (isMissingTable(update.error)) {
			return json(
				{ ok: false, error: "not_supported", message: "live_battles table not available on this project", battle_id: battleIdRaw },
				{ status: 501 },
			);
		}
		if (isUuidSyntaxError(update.error) && battleIdInt) {
			return json(
				{ ok: false, error: "not_supported", message: "live_battles uses UUID ids; numeric battle_id not supported", battle_id: battleIdRaw },
				{ status: 501 },
			);
		}
		return json({ ok: false, error: "db_error", message: update.error.message, battle_id: battleIdRaw }, { status: 500 });
	}

	if (!update.data) {
		return json({ ok: false, error: "not_found", battle_id: battleIdRaw }, { status: 404 });
	}

	return json({ ok: true, battle_id: battleIdRaw, battle: update.data, ready: true }, { status: 200 });
}

function asPlanId(raw: string | null): string | null {
	if (!raw) return null;
	const v = raw.trim().toLowerCase();
	if (!v) return null;
	if (v.length > 64) return null;
	if (!/^[a-z0-9][a-z0-9_-]{1,63}$/.test(v)) return null;
	if (v === "free") return "starter";
	if (v === "premium") return "pro";
	if (v === "platinum") return "elite";
	if (v === "premium_weekly") return "pro_weekly";
	if (v === "platinum_weekly") return "elite_weekly";
	return v;
}

function makeSupabaseAdmin() {
	// In Supabase Edge Functions, SUPABASE_URL is available by default.
	const supabaseUrl = mustEnv("SUPABASE_URL");
	// You must set this as a Function secret (Dashboard -> Edge Functions -> api -> Secrets)
	const serviceKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
	return createClient(supabaseUrl, serviceKey, {
		auth: { persistSession: false, autoRefreshToken: false },
	});
}

function isMissingTable(err: unknown): boolean {
	const e = err as { message?: unknown; code?: unknown } | null;
	const msg = String(e?.message ?? "").toLowerCase();
	const code = String(e?.code ?? "");
	return code === "42P01" || code === "PGRST205" || msg.includes("does not exist") || msg.includes("schema cache") || msg.includes("could not find the table");
}

function isMissingColumn(err: unknown, column: string): boolean {
	const e = err as { message?: unknown; code?: unknown } | null;
	const msg = String(e?.message ?? "").toLowerCase();
	const code = String(e?.code ?? "");
	return code === "42703" || msg.includes(`column ${column.toLowerCase()}`) || msg.includes(`could not find the '${column.toLowerCase()}' column`) || msg.includes(column.toLowerCase());
}

function isUuidSyntaxError(err: unknown): boolean {
	const e = err as { message?: unknown; code?: unknown } | null;
	const msg = String(e?.message ?? "").toLowerCase();
	const code = String(e?.code ?? "");
	return code === "22P02" || msg.includes("invalid input syntax") || msg.includes("uuid");
}

function randomUint32(): number {
	const buf = new Uint32Array(1);
	crypto.getRandomValues(buf);
	// Ensure unsigned 32-bit.
	return buf[0] >>> 0;
}

function encodeUtf8(s: string): Uint8Array {
	return new TextEncoder().encode(s);
}

function concatBytes(...chunks: Uint8Array[]): Uint8Array {
	const total = chunks.reduce((sum, c) => sum + c.byteLength, 0);
	const out = new Uint8Array(total);
	let offset = 0;
	for (const c of chunks) {
		out.set(c, offset);
		offset += c.byteLength;
	}
	return out;
}

function toBase64(bytes: Uint8Array): string {
	let bin = "";
	for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
	return btoa(bin);
}

function crc32(bytes: Uint8Array): number {
	let crc = 0xffffffff;
	for (let i = 0; i < bytes.length; i++) {
		crc ^= bytes[i];
		for (let j = 0; j < 8; j++) {
			const mask = -(crc & 1);
			crc = (crc >>> 1) ^ (0xedb88320 & mask);
		}
	}
	return (crc ^ 0xffffffff) >>> 0;
}

class ByteWriter {
	private chunks: Uint8Array[] = [];

	putUint16LE(n: number) {
		const b = new Uint8Array(2);
		new DataView(b.buffer).setUint16(0, n & 0xffff, true);
		this.chunks.push(b);
	}

	putUint32LE(n: number) {
		const b = new Uint8Array(4);
		new DataView(b.buffer).setUint32(0, n >>> 0, true);
		this.chunks.push(b);
	}

	putBytes(b: Uint8Array) {
		this.chunks.push(b);
	}

	putStringBytes(b: Uint8Array) {
		this.putUint16LE(b.byteLength);
		this.putBytes(b);
	}

	toBytes(): Uint8Array {
		return concatBytes(...this.chunks);
	}
}

async function hmacSha256(key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
	// Deno's WebCrypto typings can be strict about BufferSource being backed by
	// an ArrayBuffer (not a SharedArrayBuffer / ArrayBufferLike). Make a copy.
	const keyCopy = new Uint8Array(key.byteLength);
	keyCopy.set(key);
	const msgCopy = new Uint8Array(message.byteLength);
	msgCopy.set(message);

	const cryptoKey = await crypto.subtle.importKey(
		"raw",
		keyCopy.buffer,
		{ name: "HMAC", hash: "SHA-256" },
		false,
		["sign"],
	);
	const sig = await crypto.subtle.sign("HMAC", cryptoKey, msgCopy.buffer);
	return new Uint8Array(sig);
}

type AgoraRtcRole = "publisher" | "subscriber";

async function buildAgoraRtcToken(args: {
	appId: string;
	appCertificate: string;
	channelName: string;
	uid: number;
	role: AgoraRtcRole;
	expireTs: number;
}): Promise<string> {
	const version = "006";
	const salt = randomUint32();
	const ts = Math.floor(Date.now() / 1000);
	const uidStr = String(args.uid);

	// Privileges:
	// 1: join channel
	// 2: publish audio
	// 3: publish video
	// 4: publish data
	const privileges: Array<[number, number]> = [[1, args.expireTs]];
	if (args.role === "publisher") {
		privileges.push([2, args.expireTs], [3, args.expireTs], [4, args.expireTs]);
	}

	const msgWriter = new ByteWriter();
	msgWriter.putUint32LE(salt);
	msgWriter.putUint32LE(ts);
	msgWriter.putUint16LE(privileges.length);
	for (const [k, v] of privileges) {
		msgWriter.putUint16LE(k);
		msgWriter.putUint32LE(v);
	}
	const message = msgWriter.toBytes();

	const signInput = concatBytes(encodeUtf8(args.appId), encodeUtf8(args.channelName), encodeUtf8(uidStr), message);
	const signature = await hmacSha256(encodeUtf8(args.appCertificate), signInput);

	const contentWriter = new ByteWriter();
	contentWriter.putStringBytes(signature);
	contentWriter.putUint32LE(crc32(encodeUtf8(args.channelName)));
	contentWriter.putUint32LE(crc32(encodeUtf8(uidStr)));
	contentWriter.putStringBytes(message);

	return version + args.appId + toBase64(contentWriter.toBytes());
}

function normalizeBodyText(v: unknown): string | null {
	if (typeof v !== "string") return null;
	const s = v.trim();
	return s ? s : null;
}

function normalizeCountryCode(v: unknown): string | null {
	const s = normalizeBodyText(v);
	if (!s) return null;
	return s.trim().toLowerCase();
}

function normalizeTopics(v: unknown): string[] {
	if (!Array.isArray(v)) return [];
	return v
		.map((t) => (typeof t === "string" ? t.trim() : ""))
		.filter(Boolean)
		.slice(0, 25);
}

async function requireFirebaseAuth(req: Request): Promise<{ ok: true; uid: string } | { ok: false; status: number; error: string }> {
	const verified = await verifyFirebaseIdToken(req);
	if (!verified.ok) {
		return { ok: false, status: verified.missingConfig ? 503 : 401, error: verified.error };
	}
	return verified;
}

async function handlePushRegister(req: Request): Promise<Response> {
	const authed = await requireFirebaseAuth(req);
	if (!authed.ok) return json({ ok: false, error: authed.error }, { status: authed.status });

	const body = (await req.json().catch(() => null)) as PushRegisterBody | null;
	if (!body || typeof body !== "object") return json({ ok: false, error: "Invalid body" }, { status: 400 });

	const token = String((body as any).token ?? (body as any).fcm_token ?? "").trim();
	if (!token) return json({ ok: false, error: "token is required" }, { status: 400 });

	const platformRaw = String((body as any).platform ?? "unknown").toLowerCase();
	const platform = platformRaw === "ios" || platformRaw === "android" || platformRaw === "web" ? platformRaw : "unknown";

	const deviceId = normalizeBodyText((body as any).device_id);
	const country = normalizeCountryCode((body as any).country_code);
	const topics = normalizeTopics((body as any).topics);
	const appVersion = normalizeBodyText((body as any).app_version);
	const deviceModel = normalizeBodyText((body as any).device_model);
	const locale = normalizeBodyText((body as any).locale);

	const supabase = makeSupabaseAdmin();
	const nowIso = new Date().toISOString();
	const payload = {
		token,
		user_uid: authed.uid,
		platform,
		device_id: deviceId,
		country_code: country,
		topics,
		app_version: appVersion,
		device_model: deviceModel,
		locale,
		updated_at: nowIso,
		last_seen_at: nowIso,
	};

	const { error } = await supabase.from("notification_device_tokens").upsert(payload, { onConflict: "token" });
	if (error) {
		if (isMissingTable(error)) {
			return json(
				{ ok: true, warning: "notification_device_tokens table not found; token not stored" },
				{ status: 200 },
			);
		}
		return json({ ok: false, error: error.message }, { status: 500 });
	}

	return json({ ok: true, message: "Token registered", user_uid: authed.uid }, { status: 200 });
}

type ActiveSubscriptionRow = Record<string, unknown>;
type PlanRow = Record<string, unknown>;

function defaultEntitlements(planId: string) {
	const pid = String(planId ?? "starter").trim() || "starter";
	const weekly = pid.endsWith("_weekly");
	const base = pid.replace(/_weekly$/g, "");

	if (base === "artist_starter") {
		return {
			plan_id: pid,
			name: "Artist Free",
			price_mwk: 0,
			billing_interval: "month",
			ads_enabled: true,
			coins_multiplier: 1,
			can_participate_battles: false,
			battle_priority: "none",
			analytics_level: "basic",
			content_access: "limited",
			content_limit_ratio: 0.3,
			featured_status: false,
			perks: {
				creator: {
					type: "artist",
					uploads: { songs: 5, videos: 0, bulk_upload: false },
					monetization: { streams: false, coins: false, live: false, battles: false, fan_support: false },
					withdrawals: { access: "none" },
					live: { host: false, battles: false, multi_guest: false, song_requests: false },
				},
				battles: { enabled: false, priority: "none" },
				content: { exclusive: false, early_access: false },
				tickets: { sell: { enabled: false, tiers: [] } },
				recognition: { vip_badge: false },
				monthly_bonus_coins: 0,
			},
			features: {
				creator: {
					audience: "artist",
					tier: "free",
					uploads: { songs: 5, videos: 0, bulk_upload: false },
					monetization: { streams: false, coins: false, live: false, battles: false, fan_support: false },
					live: { host: false, battles: false, multi_guest: false, song_requests: false },
					withdrawals: { access: "none" },
				},
				battles: { enabled: false, priority: "none" },
				content: { exclusive: false, early_access: false },
				tickets: { sell: { enabled: false, tiers: [] } },
				monthly_bonus_coins: 0,
				vip_badge: false,
				recognition: { vip_badge: false },
			},
		};
	}
	if (base === "artist_pro") {
		return {
			plan_id: pid,
			name: "Artist Premium",
			price_mwk: 6000,
			billing_interval: "month",
			ads_enabled: false,
			coins_multiplier: 2,
			can_participate_battles: true,
			battle_priority: "standard",
			analytics_level: "standard",
			content_access: "standard",
			content_limit_ratio: 1,
			featured_status: false,
			perks: {
				creator: {
					type: "artist",
					uploads: { songs: 20, videos: 5, bulk_upload: false },
					monetization: { streams: true, coins: true, live: true, battles: true, fan_support: false },
					withdrawals: { access: "limited" },
					live: { host: true, battles: true, multi_guest: false, song_requests: false },
				},
				battles: { enabled: true, priority: "standard" },
				content: { exclusive: false, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard"] } },
				recognition: { vip_badge: false },
				monthly_bonus_coins: 0,
			},
			features: {
				creator: {
					audience: "artist",
					tier: "premium",
					uploads: { songs: 20, videos: 5, bulk_upload: false },
					monetization: { streams: true, coins: true, live: true, battles: true, fan_support: false },
					live: { host: true, battles: true, multi_guest: false, song_requests: false },
					withdrawals: { access: "limited" },
				},
				battles: { enabled: true, priority: "standard" },
				content: { exclusive: false, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard"] } },
				monthly_bonus_coins: 0,
				vip_badge: false,
				recognition: { vip_badge: false },
			},
		};
	}
	if (base === "artist_premium") {
		return {
			plan_id: pid,
			name: "Artist Platinum",
			price_mwk: 12500,
			billing_interval: "month",
			ads_enabled: false,
			coins_multiplier: 3,
			can_participate_battles: true,
			battle_priority: "priority",
			analytics_level: "advanced",
			content_access: "exclusive",
			content_limit_ratio: 1,
			featured_status: true,
			perks: {
				creator: {
					type: "artist",
					uploads: { songs: "unlimited", videos: "unlimited", bulk_upload: true },
					monetization: { streams: true, coins: true, live: true, battles: true, fan_support: true },
					withdrawals: { access: "unlimited" },
					live: { host: true, battles: true, multi_guest: true, song_requests: true },
				},
				battles: { enabled: true, priority: "priority" },
				content: { exclusive: true, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard", "vip", "priority"] } },
				recognition: { vip_badge: true },
				monthly_bonus_coins: 200,
			},
			features: {
				creator: {
					audience: "artist",
					tier: "platinum",
					uploads: { songs: -1, videos: -1, bulk_upload: true },
					monetization: { streams: true, coins: true, live: true, battles: true, fan_support: true },
					live: { host: true, battles: true, multi_guest: true, song_requests: true },
					withdrawals: { access: "unlimited" },
				},
				battles: { enabled: true, priority: "priority" },
				content: { exclusive: true, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard", "vip", "priority"] } },
				monthly_bonus_coins: 200,
				vip_badge: true,
				recognition: { vip_badge: true },
			},
		};
	}
	if (base === "dj_starter") {
		return {
			plan_id: pid,
			name: "DJ Free",
			price_mwk: 0,
			billing_interval: "month",
			ads_enabled: true,
			coins_multiplier: 1,
			can_participate_battles: false,
			battle_priority: "none",
			analytics_level: "basic",
			content_access: "limited",
			content_limit_ratio: 0.3,
			featured_status: false,
			perks: {
				creator: {
					type: "dj",
					uploads: { mixes: 5, bulk_upload: false },
					monetization: { live_gifts: false, battles: false, streams: false, fan_support: false },
					withdrawals: { access: "none" },
					live: { host: false, battles: false, dj_sets: false, song_requests: false },
				},
				battles: { enabled: false, priority: "none" },
				content: { exclusive: false, early_access: false },
				tickets: { sell: { enabled: false, tiers: [] } },
				recognition: { vip_badge: false },
				monthly_bonus_coins: 0,
			},
			features: {
				creator: {
					audience: "dj",
					tier: "free",
					uploads: { mixes: 5, bulk_upload: false },
					monetization: { live_gifts: false, battles: false, streams: false, fan_support: false },
					live: { host: false, battles: false, dj_sets: false, song_requests: false },
					withdrawals: { access: "none" },
				},
				battles: { enabled: false, priority: "none" },
				content: { exclusive: false, early_access: false },
				tickets: { sell: { enabled: false, tiers: [] } },
				monthly_bonus_coins: 0,
				vip_badge: false,
				recognition: { vip_badge: false },
			},
		};
	}
	if (base === "dj_pro") {
		return {
			plan_id: pid,
			name: "DJ Premium",
			price_mwk: 8000,
			billing_interval: "month",
			ads_enabled: false,
			coins_multiplier: 2,
			can_participate_battles: true,
			battle_priority: "standard",
			analytics_level: "standard",
			content_access: "standard",
			content_limit_ratio: 1,
			featured_status: false,
			perks: {
				creator: {
					type: "dj",
					uploads: { mixes: "unlimited", bulk_upload: false },
					monetization: { live_gifts: true, battles: true, streams: true, fan_support: false },
					withdrawals: { access: "limited" },
					live: { host: true, battles: true, dj_sets: true, song_requests: false },
				},
				battles: { enabled: true, priority: "standard" },
				content: { exclusive: false, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard"] } },
				recognition: { vip_badge: false },
				monthly_bonus_coins: 0,
			},
			features: {
				creator: {
					audience: "dj",
					tier: "premium",
					uploads: { mixes: -1, bulk_upload: false },
					monetization: { live_gifts: true, battles: true, streams: true, fan_support: false },
					live: { host: true, battles: true, dj_sets: true, song_requests: false },
					withdrawals: { access: "limited" },
				},
				battles: { enabled: true, priority: "standard" },
				content: { exclusive: false, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard"] } },
				monthly_bonus_coins: 0,
				vip_badge: false,
				recognition: { vip_badge: false },
			},
		};
	}
	if (base === "dj_premium") {
		return {
			plan_id: pid,
			name: "DJ Platinum",
			price_mwk: 15000,
			billing_interval: "month",
			ads_enabled: false,
			coins_multiplier: 3,
			can_participate_battles: true,
			battle_priority: "priority",
			analytics_level: "advanced",
			content_access: "exclusive",
			content_limit_ratio: 1,
			featured_status: true,
			perks: {
				creator: {
					type: "dj",
					uploads: { mixes: "unlimited", bulk_upload: true },
					monetization: { live_gifts: true, battles: true, streams: true, fan_support: true },
					withdrawals: { access: "unlimited" },
					live: { host: true, battles: true, dj_sets: true, audience_voting: true, rewards: true, song_requests: true, highlighted_comments: true, polls: true },
				},
				battles: { enabled: true, priority: "priority" },
				content: { exclusive: true, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard", "vip", "priority"] } },
				recognition: { vip_badge: true },
				monthly_bonus_coins: 200,
			},
			features: {
				creator: {
					audience: "dj",
					tier: "platinum",
					uploads: { mixes: -1, bulk_upload: true },
					monetization: { live_gifts: true, battles: true, streams: true, fan_support: true },
					live: { host: true, battles: true, dj_sets: true, audience_voting: true, rewards: true, song_requests: true, highlighted_comments: true, polls: true },
					withdrawals: { access: "unlimited" },
				},
				battles: { enabled: true, priority: "priority" },
				content: { exclusive: true, early_access: true },
				tickets: { sell: { enabled: true, tiers: ["standard", "vip", "priority"] } },
				monthly_bonus_coins: 200,
				vip_badge: true,
				recognition: { vip_badge: true },
			},
		};
	}

	if (base === "elite") {
		return {
			plan_id: pid,
			name: weekly ? "Elite Artist (Weekly)" : "Elite Artist",
			price_mwk: weekly ? 2125 : 8500,
			billing_interval: weekly ? "week" : "month",
			ads_enabled: false,
			coins_multiplier: 3,
			can_participate_battles: true,
			battle_priority: "priority",
			analytics_level: "advanced",
			content_access: "exclusive",
			content_limit_ratio: null,
			featured_status: true,
			perks: {},
			features: {},
		};
	}
	if (base === "pro") {
		return {
			plan_id: pid,
			name: weekly ? "Pro Artist (Weekly)" : "Pro Artist",
			price_mwk: weekly ? 1250 : 5000,
			billing_interval: weekly ? "week" : "month",
			ads_enabled: false,
			coins_multiplier: 2,
			can_participate_battles: true,
			battle_priority: "standard",
			analytics_level: "standard",
			content_access: "standard",
			content_limit_ratio: null,
			featured_status: false,
			perks: {},
			features: {},
		};
	}
	return {
		plan_id: "starter",
		name: "Starter",
		price_mwk: 0,
		billing_interval: "month",
		ads_enabled: true,
		coins_multiplier: 1,
		can_participate_battles: false,
		battle_priority: "none",
		analytics_level: "basic",
		content_access: "limited",
		content_limit_ratio: 0.3,
		featured_status: false,
		perks: {},
		features: {},
	};
}

function asBillingInterval(v: unknown): "month" | "week" {
	const s = String(v ?? "").trim().toLowerCase();
	if (s === "week" || s === "weekly") return "week";
	return "month";
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
	return value !== null && typeof value === "object" && !Array.isArray(value);
}

function mergeRecordsDeep(
	base: Record<string, unknown> | null | undefined,
	override: Record<string, unknown> | null | undefined,
): Record<string, unknown> | undefined {
	if (!isPlainRecord(base) && !isPlainRecord(override)) return undefined;
	if (!isPlainRecord(base)) return override ? { ...override } : undefined;
	if (!isPlainRecord(override)) return { ...base };

	const merged: Record<string, unknown> = { ...base };
	for (const [key, value] of Object.entries(override)) {
		const current = merged[key];
		merged[key] = isPlainRecord(current) && isPlainRecord(value)
			? mergeRecordsDeep(current, value) ?? value
			: value;
	}

	return merged;
}

function toNumber(v: unknown, fallback = 0): number {
	if (typeof v === "number" && Number.isFinite(v)) return v;
	if (typeof v === "string" && v.trim() && Number.isFinite(Number(v))) return Number(v);
	return fallback;
}

async function findActiveSubscription(supabase: ReturnType<typeof makeSupabaseAdmin>, uid: string): Promise<{ row: ActiveSubscriptionRow | null; warning?: string }> {
	const attempts = ["user_id", "uid", "user_uid"] as const;
	let lastErr: unknown = null;

	for (const col of attempts) {
		const { data, error } = await supabase
			.from("user_subscriptions")
			.select("*")
			.eq(col, uid)
			.eq("status", "active")
			.order("created_at", { ascending: false })
			.limit(1)
			.maybeSingle();

		if (!error && data) return { row: (data as ActiveSubscriptionRow | null) ?? null };
		if (!error && !data) continue;
		if (isMissingColumn(error, col)) continue;
		if (isUuidSyntaxError(error)) {
			// Column exists but uid isn't the correct type (e.g. uuid vs Firebase uid).
			// Treat as "no subscription" instead of failing startup.
			return { row: null, warning: `user_subscriptions.${col} type mismatch for Firebase uid` };
		}
		if (isMissingTable(error)) {
			return { row: null, warning: "user_subscriptions table not found" };
		}
		lastErr = error;
	}

	if (lastErr) {
		return { row: null, warning: (lastErr as any)?.message ?? "Failed to query subscription" };
	}
	return { row: null };
}

async function handleSubscriptionsMe(req: Request): Promise<Response> {
	const authed = await requireFirebaseAuth(req);
	if (!authed.ok) return json({ ok: false, error: authed.error }, { status: authed.status });

	const supabase = makeSupabaseAdmin();
	const { row: active, warning } = await findActiveSubscription(supabase, authed.uid);
	const activePlanId = String((active as any)?.plan_id ?? "starter").trim() || "starter";
	const planId = asPlanId(activePlanId) ?? "starter";

	let planRow: PlanRow | null = null;
	{
		const { data, error } = await supabase
			.from("subscription_plans")
			.select("*")
			.eq("plan_id", activePlanId)
			.limit(1)
			.maybeSingle();
		if (error) {
			if (!isMissingTable(error)) return json({ ok: false, error: error.message }, { status: 500 });
		} else {
			planRow = (data as PlanRow | null) ?? null;
		}
	}

	const fallback = defaultEntitlements(planId);
	const fallbackPerks = (fallback.perks && typeof fallback.perks === "object") ? (fallback.perks as Record<string, unknown>) : {};
	const fallbackFeatures = (fallback.features && typeof fallback.features === "object") ? (fallback.features as Record<string, unknown>) : {};
	const dbPerks = ((planRow as any)?.perks && typeof (planRow as any).perks === "object") ? ((planRow as any).perks as Record<string, unknown>) : null;
	const dbFeatures = ((planRow as any)?.features && typeof (planRow as any).features === "object") ? ((planRow as any).features as Record<string, unknown>) : null;
	const mergedPerks = mergeRecordsDeep(fallbackPerks, dbPerks) ?? fallbackPerks;
	const mergedFeatures = mergeRecordsDeep(fallbackFeatures, dbFeatures) ?? fallbackFeatures;
	const entitlements = planRow
		? {
			plan_id: String((planRow as any).plan_id ?? fallback.plan_id),
			name: String((planRow as any).name ?? fallback.name),
			price_mwk: toNumber((planRow as any).price_mwk, fallback.price_mwk),
			billing_interval: asBillingInterval((planRow as any).billing_interval ?? fallback.billing_interval),
			ads_enabled: Boolean((planRow as any).ads_enabled ?? fallback.ads_enabled),
			coins_multiplier: toNumber((planRow as any).coins_multiplier, fallback.coins_multiplier),
			can_participate_battles: Boolean((planRow as any).can_participate_battles ?? fallback.can_participate_battles),
			battle_priority: String((planRow as any).battle_priority ?? fallback.battle_priority),
			analytics_level: String((planRow as any).analytics_level ?? fallback.analytics_level),
			content_access: String((planRow as any).content_access ?? fallback.content_access),
			content_limit_ratio: (planRow as any).content_limit_ratio ?? fallback.content_limit_ratio,
			featured_status: Boolean((planRow as any).featured_status ?? fallback.featured_status),
			perks: mergedPerks,
			features: mergedFeatures,
		}
		: fallback;

	return json(
		{
			ok: true,
			user: { uid: authed.uid },
			subscription: active
				? {
					id: (active as any).id ?? null,
					plan_id: (active as any).plan_id ?? null,
					status: (active as any).status ?? null,
					started_at: (active as any).started_at ?? (active as any).start_date ?? null,
					ends_at: (active as any).ends_at ?? (active as any).end_date ?? null,
					auto_renew: (active as any).auto_renew ?? null,
					country_code: (active as any).country_code ?? null,
					source: (active as any).source ?? null,
				}
				: null,
			plan: planRow
				? {
					plan_id: String((planRow as any).plan_id ?? entitlements.plan_id),
					name: String((planRow as any).name ?? entitlements.name),
					price_mwk: toNumber((planRow as any).price_mwk, entitlements.price_mwk),
					billing_interval: String((planRow as any).billing_interval ?? entitlements.billing_interval),
					features: mergedFeatures,
				}
				: {
					plan_id: entitlements.plan_id,
					name: entitlements.name,
					price_mwk: entitlements.price_mwk,
					billing_interval: entitlements.billing_interval,
					features: mergedFeatures,
				},
			entitlements,
			...(warning ? { warning } : null),
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleGetPromotions(req: Request, planId: string | null): Promise<Response> {
	const supabase = makeSupabaseAdmin();
	const nowIso = new Date().toISOString();

	let query = supabase
		.from("promotions")
		.select("id,title,description,image_url,target_plan,priority,starts_at,ends_at,created_at")
		.eq("is_active", true)
		.or(`starts_at.is.null,starts_at.lte.${nowIso}`)
		.or(`ends_at.is.null,ends_at.gte.${nowIso}`)
		.order("priority", { ascending: false })
		.order("created_at", { ascending: false })
		.limit(50);

	if (planId) query = query.in("target_plan", ["all", planId]);

	const { data, error } = await query;
	if (error) return json({ ok: false, error: error.message }, { status: 500 });
	return json({ ok: true, promotions: (data ?? []) as PromotionPublicRow[] }, { status: 200, headers: { "cache-control": "no-store" } });
}

function mapContentToSubscriptionPublic(row: ContentPromotionRow): SubscriptionPromotionRow {
	return {
		id: row.id,
		target_plan_id: row.target_plan === "all" ? null : String(row.target_plan),
		title: row.title,
		body: String(row.description ?? row.title ?? "").trim() || row.title,
		starts_at: row.starts_at ?? null,
		ends_at: row.ends_at ?? null,
		created_at: row.created_at,
	};
}

async function handleGetSubscriptionPromotions(req: Request, planId: string | null): Promise<Response> {
	const supabase = makeSupabaseAdmin();
	const nowIso = new Date().toISOString();

	let subscriptionQuery = supabase
		.from("subscription_promotions")
		.select("id,target_plan_id,title,body,starts_at,ends_at,created_at")
		.eq("status", "published")
		.or(`starts_at.is.null,starts_at.lte.${nowIso}`)
		.or(`ends_at.is.null,ends_at.gte.${nowIso}`)
		.order("created_at", { ascending: false })
		.limit(50);

	if (planId) subscriptionQuery = subscriptionQuery.or(`target_plan_id.is.null,target_plan_id.eq.${planId}`);

	let contentQuery = supabase
		.from("promotions")
		.select("id,title,description,target_plan,is_active,starts_at,ends_at,created_at")
		.eq("is_active", true)
		.or(`starts_at.is.null,starts_at.lte.${nowIso}`)
		.or(`ends_at.is.null,ends_at.gte.${nowIso}`)
		.order("created_at", { ascending: false })
		.limit(50);

	if (planId) contentQuery = contentQuery.in("target_plan", ["all", planId]);

	const [{ data: subscriptionPromotions, error: subscriptionError }, { data: contentPromotions, error: contentError }] = await Promise.all([
		subscriptionQuery,
		contentQuery,
	]);

	if (subscriptionError) return json({ ok: false, error: subscriptionError.message }, { status: 500 });
	if (contentError) return json({ ok: false, error: contentError.message }, { status: 500 });

	const mappedContent = ((contentPromotions ?? []) as unknown as ContentPromotionRow[]).map(mapContentToSubscriptionPublic);

	const combined = ([...(((subscriptionPromotions ?? []) as unknown as SubscriptionPromotionRow[]) ?? []), ...mappedContent] as SubscriptionPromotionRow[])
		.filter((p) => Boolean(p.id))
		.sort((a, b) => {
			const ad = Date.parse(a.created_at);
			const bd = Date.parse(b.created_at);
			if (Number.isFinite(ad) && Number.isFinite(bd)) return bd - ad;
			return String(b.created_at).localeCompare(String(a.created_at));
		})
		.slice(0, 50);

	return json({ ok: true, promotions: combined }, { status: 200, headers: { "cache-control": "no-store" } });
}

function normalizeBodyString(v: unknown): string | null {
	return typeof v === "string" && v.trim() ? v.trim() : null;
}

function normalizePlanId(v: unknown): string | null {
	const s = normalizeBodyString(v);
	if (!s) return null;
	return asPlanId(s.trim());
}

function parseEnvInt(key: string, fallback: number): number {
	const v = normalizeEnvOptional(key);
	if (!v) return fallback;
	const n = Number(v);
	if (!Number.isFinite(n)) return fallback;
	return Math.floor(n);
}

function todayUtcDateString(): string {
	return new Date().toISOString().slice(0, 10);
}

async function getUserCoinBalance(supabase: ReturnType<typeof makeSupabaseAdmin>, uid: string): Promise<number> {
	const { data, error } = await supabase.rpc("user_coin_balance", { p_actor_id: uid });
	if (error) throw new Error(error.message);
	const n = Number(data ?? 0);
	return Number.isFinite(n) ? n : 0;
}

async function getUserAiCreditBalance(supabase: ReturnType<typeof makeSupabaseAdmin>, uid: string): Promise<number> {
	const { data, error } = await supabase.rpc("user_ai_credit_balance", { p_uid: uid });
	if (error) {
		// Backward-compatible: if credits table/RPC isn't deployed yet, treat as zero.
		if (isMissingTable(error) || String(error.message ?? "").toLowerCase().includes("user_ai_credit_balance")) return 0;
		throw new Error(error.message);
	}
	const n = Number(data ?? 0);
	return Number.isFinite(n) ? Math.max(0, Math.floor(n)) : 0;
}

async function getUserPlanStatus(
	supabase: ReturnType<typeof makeSupabaseAdmin>,
	uid: string,
): Promise<{ plan_id: string; is_premium_active: boolean }> {
	// Best-effort: subscription system may not exist on all projects.
	const { data, error } = await supabase
		.from("user_subscriptions")
		.select("plan_id,status,ends_at")
		.eq("user_id", uid)
		.eq("status", "active")
		.order("created_at", { ascending: false })
		.limit(1)
		.maybeSingle();

	if (error) {
		if (isMissingTable(error) || isMissingColumn(error, "plan_id") || isMissingColumn(error, "user_id")) {
			return { plan_id: "starter", is_premium_active: false };
		}
		throw new Error(error.message);
	}

	const planId = asPlanId(String((data as any)?.plan_id || "starter")) ?? "starter";
	const endsAtRaw = (data as any)?.ends_at ? String((data as any).ends_at) : null;
	const endsAt = endsAtRaw ? Date.parse(endsAtRaw) : NaN;
	const stillActive = !endsAtRaw || (Number.isFinite(endsAt) && endsAt > Date.now());
	const premiumActive = stillActive && (planId === "pro" || planId === "elite" || planId === "pro_weekly" || planId === "elite_weekly");
	return { plan_id: planId, is_premium_active: premiumActive };
}

async function spendUserCoins(
	supabase: ReturnType<typeof makeSupabaseAdmin>,
	uid: string,
	coinCost: number,
	action: string,
): Promise<number> {
	if (!Number.isFinite(coinCost) || coinCost <= 0) return await getUserCoinBalance(supabase, uid);
	const { error } = await supabase.from("transactions").insert({
		type: "adjustment",
		actor_type: "user",
		actor_id: uid,
		target_type: null,
		target_id: null,
		amount_mwk: 0,
		coins: -Math.abs(Math.floor(coinCost)),
		source: action,
		meta: { action },
	});
	if (error) {
		if (isMissingTable(error)) throw new Error("transactions table missing");
		throw new Error(error.message);
	}
	return await getUserCoinBalance(supabase, uid);
}

async function trySpendAiCredits(
	supabase: ReturnType<typeof makeSupabaseAdmin>,
	uid: string,
	creditsCost: number,
	action: string,
): Promise<{ ok: true; balance: number } | { ok: false; balance: number }> {
	const cost = Math.max(0, Math.floor(creditsCost));
	if (cost === 0) return { ok: true, balance: await getUserAiCreditBalance(supabase, uid) };

	const { data, error } = await supabase.rpc("ai_try_spend_credits", { p_uid: uid, p_cost: cost, p_reason: action });
	if (error) {
		// If credits RPC isn't available, treat as insufficient.
		if (isMissingTable(error) || String(error.message ?? "").toLowerCase().includes("ai_try_spend_credits")) {
			return { ok: false, balance: 0 };
		}
		throw new Error(error.message);
	}
	const n = Number(data ?? -1);
	if (!Number.isFinite(n) || n < 0) {
		return { ok: false, balance: await getUserAiCreditBalance(supabase, uid) };
	}
	return { ok: true, balance: Math.max(0, Math.floor(n)) };
}

async function getDailyBeatUsage(supabase: ReturnType<typeof makeSupabaseAdmin>, uid: string, day: string): Promise<number> {
	const { data, error } = await supabase.rpc("ai_get_daily_beat_usage", { p_uid: uid, p_day: day });
	if (error) throw new Error(error.message);
	const n = Number(data ?? 0);
	return Number.isFinite(n) ? n : 0;
}

async function incrementDailyBeatUsage(supabase: ReturnType<typeof makeSupabaseAdmin>, uid: string, day: string): Promise<number> {
	const { data, error } = await supabase.rpc("ai_increment_daily_beat_usage", { p_uid: uid, p_day: day });
	if (error) throw new Error(error.message);
	const n = Number(data ?? 0);
	return Number.isFinite(n) ? n : 0;
}

function handleAiPricing(req: Request): Response {
	const beatCostCoins = Math.max(0, parseEnvInt("AI_BEAT_GENERATE_COST_COINS", 25));
	const beatDailyFreeLimit = Math.max(0, parseEnvInt("AI_BEAT_DAILY_FREE_LIMIT", 3));
	const djNextCostCoins = Math.max(0, parseEnvInt("AI_DJ_NEXT_COST_COINS", 0));

	return json(
		{
			ok: true,
			pricing: {
				currency: "coins",
				costs: {
					beat_generate: { coins: beatCostCoins },
					dj_next: { coins: djNextCostCoins },
				},
				free_limits: {
					beat_generate_daily: beatDailyFreeLimit,
				},
			},
			build_tag: BUILD_TAG,
			public: true,
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleAiBalance(req: Request): Promise<Response> {
	const auth = await requireAppAuth(req);
	if (!auth.ok) return json({ ok: false, error: "unauthorized", message: auth.error }, { status: auth.status });

	const supabase = makeSupabaseAdmin();
	const day = todayUtcDateString();
	const beatDailyFreeLimit = Math.max(0, parseEnvInt("AI_BEAT_DAILY_FREE_LIMIT", 3));
	const beatCostCoins = Math.max(0, parseEnvInt("AI_BEAT_GENERATE_COST_COINS", 25));

	const [coinBalance, aiCreditBalance, used, plan] = await Promise.all([
		getUserCoinBalance(supabase, auth.uid),
		getUserAiCreditBalance(supabase, auth.uid),
		getDailyBeatUsage(supabase, auth.uid, day),
		getUserPlanStatus(supabase, auth.uid),
	]);

	const freeRemaining = Math.max(0, beatDailyFreeLimit - used);

	return json(
		{
			ok: true,
			uid: auth.uid,
			plan_id: plan.plan_id,
			is_premium_active: plan.is_premium_active,
			coin_balance: coinBalance,
			ai_credit_balance: aiCreditBalance,
			beat_generation: {
				day,
				free_remaining: freeRemaining,
				coin_cost: beatCostCoins,
			},
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleAiFakeStreamScan(req: Request): Promise<Response> {
	if (!isAiScanAllowed(req)) return json({ ok: false, error: "forbidden" }, { status: 403 });

	const url = new URL(req.url);
	const windowMinutesRaw = Number(url.searchParams.get("window_minutes") ?? url.searchParams.get("windowMinutes") ?? 10);
	const windowMinutes = Number.isFinite(windowMinutesRaw) ? Math.max(1, Math.min(120, Math.floor(windowMinutesRaw))) : 10;

	const repeatRaw = Number(url.searchParams.get("repeat_threshold") ?? url.searchParams.get("repeatThreshold") ?? 20);
	const repeatThreshold = Number.isFinite(repeatRaw) ? Math.max(1, Math.min(1000, Math.floor(repeatRaw))) : 20;

	const shortSecondsRaw = Number(url.searchParams.get("short_seconds") ?? url.searchParams.get("shortSeconds") ?? 5);
	const shortSeconds = Number.isFinite(shortSecondsRaw) ? Math.max(1, Math.min(60, Math.floor(shortSecondsRaw))) : 5;

	const shortRaw = Number(url.searchParams.get("short_threshold") ?? url.searchParams.get("shortThreshold") ?? 10);
	const shortThreshold = Number.isFinite(shortRaw) ? Math.max(1, Math.min(1000, Math.floor(shortRaw))) : 10;

	const spikeRaw = Number(url.searchParams.get("song_spike_threshold") ?? url.searchParams.get("songSpikeThreshold") ?? 200);
	const songSpikeThreshold = Number.isFinite(spikeRaw) ? Math.max(1, Math.min(100000, Math.floor(spikeRaw))) : 200;

	const sinceIso = new Date(Date.now() - windowMinutes * 60 * 1000).toISOString();
	const supabase = makeSupabaseAdmin();

	const { data, error } = await supabase
		.from("song_streams")
		.select("user_id,song_id,duration_seconds,created_at")
		.gte("created_at", sinceIso)
		.limit(5000);

	if (error) {
		// Helpful hint if table isn't deployed yet.
		if ((error as any)?.code === "42P01") {
			return json(
				{ ok: false, error: "missing_table", message: "song_streams table not found. Apply migration 20260211123000_song_streams.sql." },
				{ status: 503 },
			);
		}
		return json({ ok: false, error: "db_error", message: error.message }, { status: 500 });
	}

	const perUserSongCount = new Map<string, number>();
	const perUserSongShortCount = new Map<string, number>();
	const perSongCount = new Map<string, number>();

	for (const row of data ?? []) {
		const userId = (row as any)?.user_id ? String((row as any).user_id) : "";
		const songId = (row as any)?.song_id ? String((row as any).song_id) : "";
		const duration = Number((row as any)?.duration_seconds ?? 0) || 0;
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

	for (const [key, totalStreams] of perUserSongCount.entries()) {
		const shortStreams = perUserSongShortCount.get(key) ?? 0;
		if (totalStreams <= repeatThreshold && shortStreams <= shortThreshold) continue;
		suspiciousPairs += 1;
		const [userId, songId] = key.split("::");
		const message = `Suspicious streaming detected: ${totalStreams} plays (short<${shortSeconds}s: ${shortStreams}) for song ${songId} in ${windowMinutes} minutes`;
		const ins = await supabase.from("ai_alerts").insert({
			type: "fake_stream",
			reference_id: userId,
			severity: "high",
			message,
		});
		if (!(ins as any).error) alertsInserted += 1;
	}

	for (const [songId, cnt] of perSongCount.entries()) {
		if (cnt <= songSpikeThreshold) continue;
		suspiciousSongs += 1;
		const message = `Abnormal play spike: ${cnt} plays for song ${songId} in ${windowMinutes} minutes`;
		const ins = await supabase.from("ai_alerts").insert({
			type: "fake_stream",
			reference_id: `song:${songId}`,
			severity: "medium",
			message,
		});
		if (!(ins as any).error) alertsInserted += 1;
	}

	return json(
		{
			ok: true,
			since: sinceIso,
			window_minutes: windowMinutes,
			repeat_threshold: repeatThreshold,
			short_seconds: shortSeconds,
			short_threshold: shortThreshold,
			song_spike_threshold: songSpikeThreshold,
			streams_scanned: (data ?? []).length,
			suspicious_pairs: suspiciousPairs,
			suspicious_songs: suspiciousSongs,
			alerts_inserted: alertsInserted,
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleBeatGenerate(req: Request): Promise<Response> {
	// Production hardening:
	// - Beat generation is monetized, so require a valid Firebase ID token by default.
	// - Test-token access is allowed only when WEAFRICA_ENABLE_TEST_ROUTES=true (dev-only).
	let uid: string;
	if (isTestAccessAllowed(req)) {
		uid = "test";
	} else {
		const verified = await verifyFirebaseIdToken(req);
		if (!verified.ok) {
			const status = verified.missingConfig ? 503 : 401;
			return json({ ok: false, error: "unauthorized", message: verified.error }, { status });
		}
		uid = verified.uid;
	}

	const supabase = makeSupabaseAdmin();
	const day = todayUtcDateString();
	const beatDailyFreeLimit = Math.max(0, parseEnvInt("AI_BEAT_DAILY_FREE_LIMIT", 3));
	const beatCostCoins = Math.max(0, parseEnvInt("AI_BEAT_GENERATE_COST_COINS", 25));
	const beatCostCredits = Math.max(0, parseEnvInt("AI_BEAT_GENERATE_CREDITS_COST", 0));
	const action = "beat_generate";

	const used = await getDailyBeatUsage(supabase, uid, day);
	if (used >= beatDailyFreeLimit) {
		const [coinBalance, aiCreditBalance] = await Promise.all([
			getUserCoinBalance(supabase, uid),
			getUserAiCreditBalance(supabase, uid),
		]);

		const canPayWithCredits = beatCostCredits > 0 && aiCreditBalance >= beatCostCredits;
		const canPayWithCoins = beatCostCoins > 0 && coinBalance >= beatCostCoins;

		if (!canPayWithCredits && !canPayWithCoins) {
			return json(
				{
					ok: false,
					error: "payment_required",
					message: "Daily free limit reached; payment required.",
					details: {
						action,
						coin_cost: beatCostCoins,
						credits_cost: beatCostCredits,
						coin_balance: coinBalance,
						ai_credit_balance: aiCreditBalance,
					},
				},
				{ status: 402, headers: { "cache-control": "no-store" } },
			);
		}

		// Spend credits first when configured and available; otherwise spend coins.
		if (canPayWithCredits) {
			const spent = await trySpendAiCredits(supabase, uid, beatCostCredits, action);
			if (!spent.ok) {
				return json(
					{
						ok: false,
						error: "payment_required",
						message: "Insufficient AI credits.",
						details: {
							action,
							coin_cost: beatCostCoins,
							credits_cost: beatCostCredits,
							coin_balance: coinBalance,
							ai_credit_balance: aiCreditBalance,
						},
					},
					{ status: 402, headers: { "cache-control": "no-store" } },
				);
			}
		} else {
			await spendUserCoins(supabase, uid, beatCostCoins, action);
		}

		// Paid generation does not increment free usage.
		return json(
			{
				ok: true,
				uid,
				mode: "paid",
				beat: {
					id: `beat_${day}_${randomUint32()}`,
					created_at: new Date().toISOString(),
				},
			},
			{ status: 200, headers: { "cache-control": "no-store" } },
		);
	}

	const nextCount = await incrementDailyBeatUsage(supabase, uid, day);
	const remaining = Math.max(0, beatDailyFreeLimit - nextCount);

	// This endpoint is a monetization gate + quota counter.
	// Actual beat generation happens elsewhere; we return a lightweight payload.
	return json(
		{
			ok: true,
			uid,
			mode: "free",
			beat: {
				id: `beat_${day}_${randomUint32()}`,
				created_at: new Date().toISOString(),
			},
			beat_generation: {
				day,
				free_remaining: remaining,
				coin_cost: beatCostCoins,
			},
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleDjNext(req: Request): Promise<Response> {
	// Public by default (no PII). If you want to lock down, requireAppAuth here.
	const body = (await req.json().catch(() => null)) as any;
	const coinsPerMinRaw = body?.coins_per_min ?? body?.coinsPerMin;
	const coinsPerMin = Number(coinsPerMinRaw);
	const threshold = Math.max(1, parseEnvInt("AI_DJ_CROWD_BOOST_THRESHOLD_COINS_PER_MIN", 500));

	if (!Number.isFinite(coinsPerMin) || coinsPerMin < 0) {
		return json({ ok: false, error: "invalid_request", message: "coins_per_min must be a non-negative number" }, { status: 400 });
	}

	const crowdBoostDetected = coinsPerMin >= threshold;
	const messages = crowdBoostDetected
		? [
			"High coins/min detected; consider enabling crowd boost.",
			"Tip: reduce coins/min or offer a limited-time boost to avoid churn.",
		]
		: [];

	return json(
		{
			ok: true,
			crowd_boost_detected: crowdBoostDetected,
			messages,
			coins_per_min: coinsPerMin,
			threshold_coins_per_min: threshold,
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

function handleDiag(req: Request): Response {
	const url = new URL(req.url);
	const firebaseProjectId = normalizeEnvOptional("FIREBASE_PROJECT_ID");
	return json(
		{
			ok: true,
			name: "weafrica-edge-api",
			build_tag: BUILD_TAG,
			firebase_project_id: firebaseProjectId,
			firebase_expected_issuer: firebaseProjectId ? `https://securetoken.google.com/${firebaseProjectId}` : null,
			paths: {
				diag: "/diag",
				agora_token: "/agora/token",
				paychangu_start: "/paychangu/start",
			},
			allowed_channel_prefixes: ["live_", "weafrica_live_", "weafrica_battle_"],
			cors: {
				allow_origin: req.headers.get("origin") ?? "*",
			},
			runtime: {
				now: new Date().toISOString(),
				method: req.method,
				host: url.host,
				pathname: url.pathname,
			},
			env: {
				has_firebase_project_id: Boolean(normalizeEnvOptional("FIREBASE_PROJECT_ID")),
				has_agora_app_id: Boolean(normalizeEnvOptional("AGORA_APP_ID")),
				has_agora_app_certificate: Boolean(normalizeEnvOptional("AGORA_APP_CERTIFICATE")),
				has_service_role_key: Boolean(normalizeEnvOptional("SUPABASE_SERVICE_ROLE_KEY")),
				// Alias for clarity/stability in external smoke tests.
				has_supabase_service_role_key: Boolean(normalizeEnvOptional("SUPABASE_SERVICE_ROLE_KEY")),
				has_replicate_api_token: Boolean(normalizeEnvOptional("REPLICATE_API_TOKEN")),
				enable_test_routes: isTruthyEnv("WEAFRICA_ENABLE_TEST_ROUTES"),
				has_test_token: Boolean(normalizeEnvOptional("WEAFRICA_TEST_TOKEN")),
			},
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

type ReplicatePrediction = {
	id: string;
	status: string;
	output?: unknown;
	error?: unknown;
	urls?: { get?: string };
};

function buildBeatAudioPrompt(body: any): { prompt: string; style: string | null; mood: string | null; bpm: number | null; durationSeconds: number | null; seed: number | null } {
	const promptRaw = typeof body?.prompt === "string" ? body.prompt.trim() : "";
	const style = typeof body?.style === "string" ? body.style.trim() : null;
	const mood = typeof body?.mood === "string" ? body.mood.trim() : null;
	const bpmRaw = body?.bpm;
	const durationRaw = body?.duration_seconds ?? body?.durationSeconds ?? body?.duration;
	const seedRaw = body?.seed;
	const bpm = Number.isFinite(Number(bpmRaw)) ? Math.max(0, Math.floor(Number(bpmRaw))) : null;
	const durationSeconds = Number.isFinite(Number(durationRaw)) ? Math.max(1, Math.min(60, Math.floor(Number(durationRaw)))) : null;
	const seed = Number.isFinite(Number(seedRaw)) ? Math.max(0, Math.floor(Number(seedRaw))) : null;

	const parts: string[] = [];
	if (promptRaw) parts.push(promptRaw);
	if (style) parts.push(`style: ${style}`);
	if (mood) parts.push(`mood: ${mood}`);
	if (bpm != null && bpm > 0) parts.push(`bpm: ${bpm}`);
	const prompt = parts.join(" | ").trim();
	return { prompt, style, mood, bpm, durationSeconds, seed };
}

function extractFirstUrlFromReplicateOutput(output: unknown): string | null {
	if (typeof output === "string" && output.trim()) return output.trim();
	if (Array.isArray(output)) {
		for (const v of output) {
			if (typeof v === "string" && v.trim()) return v.trim();
		}
	}
	if (output && typeof output === "object") {
		const o = output as Record<string, unknown>;
		for (const k of ["audio", "mp3", "url", "file", "output"]) {
			const v = o[k];
			const inner = extractFirstUrlFromReplicateOutput(v);
			if (inner) return inner;
		}
	}
	return null;
}

async function replicateCreatePrediction(input: Record<string, unknown>): Promise<ReplicatePrediction> {
	const token = mustEnv("REPLICATE_API_TOKEN");
	const model = normalizeEnvOptional("WEAFRICA_REPLICATE_MUSIC_MODEL") ?? "meta/musicgen";
	const version = normalizeEnvOptional("WEAFRICA_REPLICATE_MUSIC_VERSION");

	let url: string;
	let payload: Record<string, unknown>;
	if (version) {
		url = "https://api.replicate.com/v1/predictions";
		payload = { version, input };
	} else {
		const [owner, name] = model.split("/");
		if (!owner || !name) throw new Error(`Invalid WEAFRICA_REPLICATE_MUSIC_MODEL: ${model}`);
		url = `https://api.replicate.com/v1/models/${owner}/${name}/predictions`;
		payload = { input };
	}

	const res = await fetch(url, {
		method: "POST",
		headers: {
			"content-type": "application/json",
			"authorization": `Token ${token}`,
		},
		body: JSON.stringify(payload),
	});
	const data = (await res.json().catch(() => null)) as any;
	if (!res.ok) {
		const msg = typeof data?.detail === "string" ? data.detail : typeof data?.error === "string" ? data.error : `Replicate create failed (${res.status})`;
		throw new Error(msg);
	}
	if (!data?.id) throw new Error("Replicate create returned no prediction id");
	return data as ReplicatePrediction;
}

async function replicateGetPrediction(predictionId: string): Promise<ReplicatePrediction> {
	const token = mustEnv("REPLICATE_API_TOKEN");
	const url = `https://api.replicate.com/v1/predictions/${encodeURIComponent(predictionId)}`;
	const res = await fetch(url, {
		headers: {
			"authorization": `Token ${token}`,
		},
	});
	const data = (await res.json().catch(() => null)) as any;
	if (!res.ok) {
		const msg = typeof data?.detail === "string" ? data.detail : typeof data?.error === "string" ? data.error : `Replicate get failed (${res.status})`;
		throw new Error(msg);
	}
	return data as ReplicatePrediction;
}

async function handleBeatAudioStart(req: Request): Promise<Response> {
	// Production: require Firebase Bearer token (no test-token fallback)
	const verified = await verifyFirebaseIdToken(req);
	if (!verified.ok) return json({ ok: false, error: "unauthorized", message: verified.error }, { status: verified.missingConfig ? 503 : 401 });
	const uid = verified.uid;

	const body = (await req.json().catch(() => null)) as any;
	const { prompt, style, mood, bpm, durationSeconds, seed } = buildBeatAudioPrompt(body);
	if (!prompt) return json({ ok: false, error: "invalid_request", message: "prompt is required" }, { status: 400 });

	const supabase = makeSupabaseAdmin();
	const bucket = normalizeEnvOptional("WEAFRICA_AI_BEATS_BUCKET") ?? "ai_beats";
	const action = "beat_audio_generation";
	const coinCost = Math.max(0, parseEnvInt("AI_BEAT_AUDIO_COST_COINS", 250));

	// Create job first (so we can surface job_id even on payment failure).
	const insert = await supabase
		.from("ai_beat_audio_jobs")
		.insert({
			user_id: uid,
			status: "queued",
			provider: "replicate",
			style,
			bpm,
			mood,
			duration_seconds: durationSeconds,
			prompt,
			seed,
			storage_bucket: bucket,
			monetization: { action, coin_cost: coinCost },
		})
		.select("id")
		.maybeSingle();
	if (insert.error) throw new Error(insert.error.message);
	const jobId = String((insert.data as any)?.id ?? "");
	if (!jobId) throw new Error("Failed to create job");

	// Enforce monetization (coins only for now).
	const balance = await getUserCoinBalance(supabase, uid);
	if (coinCost > 0 && balance < coinCost) {
		await supabase.from("ai_beat_audio_jobs").update({ status: "failed", error: "payment_required" }).eq("id", jobId);
		return json(
			{
				ok: false,
				error: "payment_required",
				message: "Insufficient coin balance.",
				details: {
					action,
					coin_cost: coinCost,
					coin_balance: balance,
				},
				job_id: jobId,
			},
			{ status: 402, headers: { "cache-control": "no-store" } },
		);
	}
	await spendUserCoins(supabase, uid, coinCost, action);

	// Start Replicate prediction.
	const input: Record<string, unknown> = {
		prompt,
	};
	if (durationSeconds != null) input.duration = durationSeconds;
	if (seed != null) input.seed = seed;

	const pred = await replicateCreatePrediction(input);
	const update = await supabase
		.from("ai_beat_audio_jobs")
		.update({ status: "running", provider_prediction_id: pred.id })
		.eq("id", jobId);
	if (update.error) throw new Error(update.error.message);

	return json(
		{
			ok: true,
			job_id: jobId,
			status: "running",
			provider_prediction_id: pred.id,
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

async function handleBeatAudioStatus(req: Request): Promise<Response> {
	const verified = await verifyFirebaseIdToken(req);
	if (!verified.ok) return json({ ok: false, error: "unauthorized", message: verified.error }, { status: verified.missingConfig ? 503 : 401 });
	const uid = verified.uid;

	const url = new URL(req.url);
	const jobId = (url.searchParams.get("job_id") ?? url.searchParams.get("jobId") ?? "").trim();
	if (!jobId) return json({ ok: false, error: "invalid_request", message: "job_id is required" }, { status: 400 });

	const supabase = makeSupabaseAdmin();
	const { data: job, error } = await supabase
		.from("ai_beat_audio_jobs")
		.select("*")
		.eq("id", jobId)
		.maybeSingle();
	if (error) throw new Error(error.message);
	if (!job) return json({ ok: false, error: "not_found" }, { status: 404, headers: { "cache-control": "no-store" } });
	if (String((job as any).user_id) !== uid) return json({ ok: false, error: "forbidden" }, { status: 403, headers: { "cache-control": "no-store" } });

	let status = String((job as any).status ?? "queued");
	const providerPredictionId = (job as any).provider_prediction_id ? String((job as any).provider_prediction_id) : null;
	const storageBucket = (job as any).storage_bucket ? String((job as any).storage_bucket) : (normalizeEnvOptional("WEAFRICA_AI_BEATS_BUCKET") ?? "ai_beats");
	let storagePath = (job as any).storage_path ? String((job as any).storage_path) : null;
	let outputMime = (job as any).output_mime ? String((job as any).output_mime) : null;

	// If still running, poll Replicate to see if it's done.
	if ((status === "queued" || status === "running") && providerPredictionId) {
		try {
			const pred = await replicateGetPrediction(providerPredictionId);
			if (pred.status === "failed" || pred.status === "canceled") {
				status = "failed";
				await supabase
					.from("ai_beat_audio_jobs")
					.update({ status: "failed", error: typeof pred.error === "string" ? pred.error : "replicate_failed" })
					.eq("id", jobId);
			} else if (pred.status === "succeeded") {
				// Download + upload if we haven't stored it yet.
				if (!storagePath) {
					const outUrl = extractFirstUrlFromReplicateOutput(pred.output);
					if (!outUrl) {
						status = "failed";
						await supabase.from("ai_beat_audio_jobs").update({ status: "failed", error: "missing_output_url" }).eq("id", jobId);
					} else {
						const dl = await fetch(outUrl);
						if (!dl.ok) {
							status = "failed";
							await supabase.from("ai_beat_audio_jobs").update({ status: "failed", error: `download_failed_${dl.status}` }).eq("id", jobId);
						} else {
							const bytes = new Uint8Array(await dl.arrayBuffer());
							const mime = dl.headers.get("content-type") ?? "audio/mpeg";
							const path = `beats/${uid}/${jobId}.mp3`;
							const up = await supabase.storage.from(storageBucket).upload(path, bytes, { contentType: mime, upsert: true });
							if ((up as any).error) {
								status = "failed";
								await supabase.from("ai_beat_audio_jobs").update({ status: "failed", error: (up as any).error.message ?? "upload_failed" }).eq("id", jobId);
							} else {
								status = "succeeded";
								storagePath = path;
								outputMime = mime;
								await supabase
									.from("ai_beat_audio_jobs")
									.update({ status: "succeeded", storage_bucket: storageBucket, storage_path: path, output_mime: mime, output_bytes: bytes.byteLength })
									.eq("id", jobId);
							}
						}
					}
				}
			}
		} catch (e) {
			// Keep job running; client can retry.
		}
	}

	if (status === "succeeded" && storagePath) {
		const signed = await supabase.storage.from(storageBucket).createSignedUrl(storagePath, 60 * 60);
		if ((signed as any).error) throw new Error((signed as any).error.message ?? "Failed to sign URL");
		return json(
			{
				ok: true,
				job_id: jobId,
				status,
				audio_url: (signed as any).data?.signedUrl ?? null,
				output_mime: outputMime,
			},
			{ status: 200, headers: { "cache-control": "no-store" } },
		);
	}

	return json(
		{
			ok: true,
			job_id: jobId,
			status,
			provider_prediction_id: providerPredictionId,
			error: status === "failed" ? (job as any).error ?? "failed" : null,
		},
		{ status: 200, headers: { "cache-control": "no-store" } },
	);
}

serve(async (req: Request) => {
	const requestId = crypto.randomUUID();
	const cors = corsHeaders(req);
	const isProd = isProductionEnv();

	const finalize = async (res: Response, route: string, errForLog?: unknown): Promise<Response> => {
		const headers = new Headers(res.headers);
		for (const [k, v] of Object.entries(cors)) headers.set(k, v);
		headers.set("x-weafrica-request-id", requestId);
		headers.set("x-weafrica-route", route);

		if (isProd && res.status >= 500) {
			// Log full details to function logs only.
			try {
				if (errForLog) console.error(`[${requestId}] route=${route} uncaught_error`, errForLog);
				const bodyText = await res.clone().text().catch(() => null);
				console.error(`[${requestId}] route=${route} status=${res.status} response_body=`, bodyText);
			} catch {
				// no-op
			}

			return json(
				{
					ok: false,
					error: "internal_error",
					message: "Internal server error",
					request_id: requestId,
				},
				{ status: res.status, headers },
			);
		}

		return new Response(res.body, { status: res.status, headers });
	};

	if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: withBuildTag(cors) });

	const url = new URL(req.url);
	const pathname = url.pathname.replace(/\/+$/g, "");
	const parts = pathname.split("/").filter(Boolean);
	// Supabase functions are typically invoked as:
	//   https://<ref>.functions.supabase.co/<function-name>/<optional-subpath>
	// So for this function (name: 'api'), the first path segment is usually 'api'.
	const subpathParts = parts[0] === "api" ? parts.slice(1) : parts;
	const subpath = "/" + subpathParts.join("/");
	const isStartRoute = subpath === "/" || subpath === "" || subpath === "/paychangu/start" || subpath === "/start";
	const isDiagRoute = subpath === "/diag";
	const isBattleStatusRoute = subpath === "/battle/status";
	const isBattleReadyRoute = subpath === "/battle/ready";
	const isPromotionsRoute = subpath === "/promotions" || subpath === "/promo" || subpath === "/promotion";
	const isSubscriptionPromotionsRoute = subpath === "/subscriptions/promotions";
	const isAgoraTokenRoute = subpath === "/agora/token";
	const isPushRegisterRoute = subpath === "/push/register";
	const isSubscriptionsMeRoute = subpath === "/subscriptions/me";
	const isAiPricingRoute = subpath === "/ai/pricing";
	const isAiBalanceRoute = subpath === "/ai/balance";
	const isAiFakeStreamScanRoute = subpath === "/ai/fake-stream-scan";
	const isBeatGenerateRoute = subpath === "/beat/generate";
	const isBeatAudioStartRoute = subpath === "/beat/audio/start";
	const isBeatAudioStatusRoute = subpath === "/beat/audio/status";
	const isDjNextRoute = subpath === "/dj/next";

	if (req.method === "GET" && isDiagRoute) {
		if (!isDiagAccessAllowed(req)) {
			return await finalize(json({ error: "Not found" }, { status: 404 }), "diag_denied");
		}
		return await finalize(handleDiag(req), "diag");
	}

	if (req.method === "GET" && isAiPricingRoute) {
		return await finalize(handleAiPricing(req), "ai_pricing");
	}

	if (req.method === "GET" && isAiBalanceRoute) {
		try {
			return await finalize(await handleAiBalance(req), "ai_balance");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=ai_balance exception`, e);
			return await finalize(
				json(
					{ ok: false, error: "internal_error", message: msg, request_id: requestId },
					{ status: msg.startsWith("Missing ") ? 503 : 500 },
				),
				"ai_balance_exception",
				e,
			);
		}
	}

	if ((req.method === "GET" || req.method === "POST") && isAiFakeStreamScanRoute) {
		try {
			return await finalize(await handleAiFakeStreamScan(req), "ai_fake_stream_scan");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=ai_fake_stream_scan exception`, e);
			return await finalize(
				json({ ok: false, error: "internal_error", message: msg, request_id: requestId }, { status: 500 }),
				"ai_fake_stream_scan_exception",
				e,
			);
		}
	}

	if (req.method === "POST" && isBeatGenerateRoute) {
		try {
			return await finalize(await handleBeatGenerate(req), "beat_generate");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=beat_generate exception`, e);
			return await finalize(
				json(
					{ ok: false, error: "internal_error", message: msg, request_id: requestId },
					{ status: msg.startsWith("Missing ") ? 503 : 500 },
				),
				"beat_generate_exception",
				e,
			);
		}
	}

	if (req.method === "POST" && isBeatAudioStartRoute) {
		try {
			return await finalize(await handleBeatAudioStart(req), "beat_audio_start");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=beat_audio_start exception`, e);
			return await finalize(
				json(
					{ ok: false, error: "internal_error", message: msg, request_id: requestId },
					{ status: msg.startsWith("Missing ") ? 503 : 500 },
				),
				"beat_audio_start_exception",
				e,
			);
		}
	}

	if (req.method === "GET" && isBeatAudioStatusRoute) {
		try {
			return await finalize(await handleBeatAudioStatus(req), "beat_audio_status");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=beat_audio_status exception`, e);
			return await finalize(
				json(
					{ ok: false, error: "internal_error", message: msg, request_id: requestId },
					{ status: msg.startsWith("Missing ") ? 503 : 500 },
				),
				"beat_audio_status_exception",
				e,
			);
		}
	}

	if (req.method === "POST" && isDjNextRoute) {
		try {
			return await finalize(await handleDjNext(req), "dj_next");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=dj_next exception`, e);
			return await finalize(
				json(
					{ ok: false, error: "internal_error", message: msg, request_id: requestId },
					{ status: msg.startsWith("Missing ") ? 503 : 500 },
				),
				"dj_next_exception",
				e,
			);
		}
	}

	if (req.method === "GET" && isBattleStatusRoute) {
		try {
			const battleIdRaw = normalizeBattleIdRaw(url.searchParams.get("battle_id") ?? url.searchParams.get("battleId"));
			if (!battleIdRaw) return await finalize(json({ ok: false, error: "invalid_request", message: "Missing/invalid battle_id" }, { status: 400 }), "battle_status_invalid");
			return await finalize(await handleBattleStatus(req, battleIdRaw), "battle_status");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=battle_status exception`, e);
			return await finalize(json({ ok: false, error: "internal_error", message: msg, request_id: requestId }, { status: 500 }), "battle_status_exception", e);
		}
	}

	if (req.method === "POST" && isBattleReadyRoute) {
		try {
			return await finalize(await handleBattleReady(req), "battle_ready");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=battle_ready exception`, e);
			return await finalize(json({ ok: false, error: "internal_error", message: msg, request_id: requestId }, { status: 500 }), "battle_ready_exception", e);
		}
	}

	if (req.method === "GET" && (isPromotionsRoute || isSubscriptionPromotionsRoute)) {
		try {
			const planId = asPlanId(url.searchParams.get("plan_id"));
			const res = isSubscriptionPromotionsRoute
				? await handleGetSubscriptionPromotions(req, planId)
				: await handleGetPromotions(req, planId);
			return await finalize(res, isSubscriptionPromotionsRoute ? "subscriptions_promotions" : "promotions");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=promotions exception`, e);
			return await finalize(json({ ok: false, error: msg, request_id: requestId }, { status: msg.startsWith("Missing ") ? 503 : 500 }), "promotions_exception", e);
		}
	}

	if (req.method === "POST" && isAgoraTokenRoute) {
		try {
			return await finalize(await handleAgoraToken(req), "agora_token");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=agora_token exception`, e);
			return await finalize(json({ ok: false, error: msg, request_id: requestId }, { status: msg.startsWith("Missing ") ? 503 : 500 }), "agora_token_exception", e);
		}
	}

	if (req.method === "POST" && isPushRegisterRoute) {
		try {
			return await finalize(await handlePushRegister(req), "push_register");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=push_register exception`, e);
			return await finalize(json({ ok: false, error: msg, request_id: requestId }, { status: msg.startsWith("Missing ") ? 503 : 500 }), "push_register_exception", e);
		}
	}

	if (req.method === "GET" && isSubscriptionsMeRoute) {
		try {
			return await finalize(await handleSubscriptionsMe(req), "subscriptions_me");
		} catch (e) {
			const msg = e instanceof Error ? e.message : String(e);
			console.error(`[${requestId}] route=subscriptions_me exception`, e);
			return await finalize(json({ ok: false, error: msg, request_id: requestId }, { status: msg.startsWith("Missing ") ? 503 : 500 }), "subscriptions_me_exception", e);
		}
	}

	if (!isStartRoute) {
		return await finalize(
			json(
				{
					ok: false,
					error: "not_found",
					message: `No route for ${req.method} ${url.pathname}.`,
					request_id: requestId,
				},
				{ status: 404 },
			),
			"not_found",
		);
	}

	// Backward-compatible: some clients accidentally call start as GET.
	// Support GET via query params, and POST via JSON body.
	let planId: string | null = null;
	let userId: string | null = null;
	let months = 1;
	let countryCode: string | null = null;

	if (req.method === "GET") {
		planId = normalizePlanId(url.searchParams.get("plan_id") ?? url.searchParams.get("planId"));
		userId = normalizeBodyString(url.searchParams.get("user_id") ?? url.searchParams.get("userId") ?? url.searchParams.get("uid"));
		const monthsRaw = Number(url.searchParams.get("months") ?? url.searchParams.get("interval_count") ?? url.searchParams.get("intervalCount"));
		months = Number.isFinite(monthsRaw) ? Math.max(1, Math.min(24, monthsRaw)) : 1;
		countryCode = normalizeBodyString(url.searchParams.get("country_code") ?? url.searchParams.get("countryCode"))?.toUpperCase() ?? null;
	} else if (req.method === "POST") {
		const body = (await req.json().catch(() => null)) as any;
		planId = normalizePlanId(body?.plan_id);
		userId = normalizeBodyString(body?.user_id ?? body?.uid);
		const monthsRaw = Number(body?.months ?? body?.interval_count);
		months = Number.isFinite(monthsRaw) ? Math.max(1, Math.min(24, monthsRaw)) : 1;
		countryCode = normalizeBodyString(body?.country_code)?.toUpperCase() ?? null;
	} else {
		return await finalize(
			json(
				{
					ok: false,
					error: "method_not_allowed",
					message: `Use POST ${url.pathname} with JSON body (or GET with query params).`,
					allowed: ["GET", "POST", "OPTIONS"],
					request_id: requestId,
				},
				{ status: 405 },
			),
			"method_not_allowed",
		);
	}

	const { url: rawUrl, sourceKey } = resolveCheckoutUrl(planId);
	if (!rawUrl) {
		return await finalize(
			json(
				{
					ok: false,
					error: "missing_config",
					message:
						"Missing PayChangu checkout configuration. Set PAYCHANGU_CHECKOUT_URL (fallback) or PAYCHANGU_CHECKOUT_URL_<PLANID> in Supabase Function env vars.",
					request_id: requestId,
				},
				{ status: 503 },
			),
			"paychangu_missing_config",
		);
	}

	let checkoutUrl = applyTemplate(rawUrl, {
		user_id: userId,
		plan_id: planId,
		months,
		country_code: countryCode,
	});

	checkoutUrl = addQueryParams(checkoutUrl, {
		user_id: userId,
		plan_id: planId,
		months,
		country_code: countryCode,
		source: "weafrica",
	});

	return await finalize(
		json(
			{
				ok: true,
				checkout_url: checkoutUrl,
				source: sourceKey,
			},
			{ status: 200 },
		),
		"paychangu_start",
	);
});
