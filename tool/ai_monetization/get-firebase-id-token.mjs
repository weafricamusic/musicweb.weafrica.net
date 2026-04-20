#!/usr/bin/env node

/**
 * Fetches a Firebase ID token using the Identity Toolkit REST API.
 *
 * This script prints ONLY the token to stdout on success.
 * Errors/usage are printed to stderr.
 *
 * Required env vars:
 *   - FIREBASE_WEB_API_KEY (or FIREBASE_API_KEY)
 *   - FIREBASE_EMAIL
 *   - FIREBASE_PASSWORD
 */

const apiKey =
  process.env.FIREBASE_WEB_API_KEY ||
  process.env.NEXT_PUBLIC_FIREBASE_API_KEY ||
  process.env.FIREBASE_API_KEY ||
  "";
const email = process.env.FIREBASE_EMAIL || "";
const password = process.env.FIREBASE_PASSWORD || "";

function usage(exitCode) {
  process.stderr.write(
    [
      "Missing required env vars.",
      "\nRequired:",
      "  FIREBASE_WEB_API_KEY (or NEXT_PUBLIC_FIREBASE_API_KEY, or FIREBASE_API_KEY)",
      "  FIREBASE_EMAIL",
      "  FIREBASE_PASSWORD",
      "\nExample (does not print token):",
      "  ID_TOKEN=\"$(FIREBASE_WEB_API_KEY=... FIREBASE_EMAIL=... FIREBASE_PASSWORD=... node tool/ai_monetization/get-firebase-id-token.mjs)\" \\\n  BASE_URL=\"https://<ref>.functions.supabase.co\" \\\n  bash tool/ai_monetization/smoke_test.sh\n",
    ].join("\n"),
  );
  process.exit(exitCode);
}

if (!apiKey || !email || !password) usage(2);

const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`;

let resp;
try {
  resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      email,
      password,
      returnSecureToken: true,
    }),
  });
} catch (err) {
  process.stderr.write(`Request failed: ${String(err)}\n`);
  process.exit(1);
}

let data;
try {
  data = await resp.json();
} catch {
  process.stderr.write(`Unexpected response (non-JSON). HTTP ${resp.status}\n`);
  process.exit(1);
}

if (!resp.ok) {
  const message = data?.error?.message ? String(data.error.message) : `HTTP ${resp.status}`;
  process.stderr.write(`Firebase auth failed: ${message}\n`);
  process.exit(1);
}

const idToken = data?.idToken ? String(data.idToken) : "";
if (!idToken) {
  process.stderr.write("Firebase auth succeeded but no idToken returned.\n");
  process.exit(1);
}

process.stdout.write(idToken + "\n");
