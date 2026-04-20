// Shared Agora token helpers for Supabase Edge Functions (Deno).
//
// Uses the legacy v006 AccessToken format implemented using WebCrypto so it
// works in Deno without Node's crypto APIs.

export const AGORA_TOKEN_VERSION = "006";

function utf8Bytes(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

function u16le(n: number): Uint8Array {
  const buf = new ArrayBuffer(2);
  new DataView(buf).setUint16(0, n & 0xffff, true);
  return new Uint8Array(buf);
}

function u32le(n: number): Uint8Array {
  const buf = new ArrayBuffer(4);
  new DataView(buf).setUint32(0, n >>> 0, true);
  return new Uint8Array(buf);
}

function packBytes(bytes: Uint8Array): Uint8Array {
  if (bytes.length > 0xffff) {
    throw new Error("packBytes length overflow");
  }
  return concatBytes([u16le(bytes.length), bytes]);
}

function base64Encode(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

let crc32Table: Uint32Array | null = null;

function getCrc32Table(): Uint32Array {
  if (crc32Table) return crc32Table;
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[i] = c >>> 0;
  }
  crc32Table = table;
  return table;
}

function crc32(bytes: Uint8Array): number {
  const table = getCrc32Table();
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    c = table[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

async function hmacSha256(key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    toArrayBuffer(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, toArrayBuffer(message));
  return new Uint8Array(sig);
}

function buildPrivilegeMessageBytes(
  privileges: Record<number, number>,
  privilegeExpireTs: number,
): Uint8Array {
  const salt = crypto.getRandomValues(new Uint32Array(1))[0] >>> 0;
  // Agora v006 token message ts is the absolute privilege expire timestamp.
  const ts = (Math.max(0, Math.floor(privilegeExpireTs)) >>> 0);

  const keys = Object.keys(privileges)
    .map((k) => Number(k))
    .filter((k) => Number.isFinite(k))
    .sort((a, b) => a - b);

  const entries: Uint8Array[] = [u16le(keys.length)];
  for (const k of keys) {
    entries.push(u16le(k));
    entries.push(u32le(privileges[k] >>> 0));
  }

  return concatBytes([
    u32le(salt),
    u32le(ts),
    ...entries,
  ]);
}

export async function buildAgoraRtcTokenV006(params: {
  appId: string;
  appCertificate: string;
  channelName: string;
  uid: number;
  isPublisher: boolean;
  privilegeExpireTs: number;
}): Promise<string> {
  const appId = params.appId.trim();
  const appCertificate = params.appCertificate.trim();
  const channelName = params.channelName;
  const uid = Math.max(0, Math.floor(params.uid));
  const uidStr = uid === 0 ? "" : String(uid);

  const expire = params.privilegeExpireTs >>> 0;
  // Privilege IDs:
  // 1: join channel
  // 2: publish audio
  // 3: publish video
  // 4: publish data
  const privileges: Record<number, number> = { 1: expire };
  if (params.isPublisher) {
    privileges[2] = expire;
    privileges[3] = expire;
    privileges[4] = expire;
  }

  const messageBytes = buildPrivilegeMessageBytes(privileges, expire);

  const toSign = concatBytes([
    utf8Bytes(appId),
    utf8Bytes(channelName),
    utf8Bytes(uidStr),
    messageBytes,
  ]);

  const signature = await hmacSha256(utf8Bytes(appCertificate), toSign);

  const content = concatBytes([
    packBytes(signature),
    u32le(crc32(utf8Bytes(channelName))),
    u32le(crc32(utf8Bytes(uidStr))),
    packBytes(messageBytes),
  ]);

  return `${AGORA_TOKEN_VERSION}${appId}${base64Encode(content)}`;
}

// Agora RTM token builder (legacy v006 AccessToken).
// Implementation detail:
// - Agora's legacy RTM token builder uses the same AccessToken format but sets
//   "channelName" = userId (user account) and "uid" = "".
// - Privilege ID for RTM login is 1 (kRtmLogin).
export async function buildAgoraRtmTokenV006(params: {
  appId: string;
  appCertificate: string;
  userId: string;
  privilegeExpireTs: number;
}): Promise<string> {
  const appId = params.appId.trim();
  const appCertificate = params.appCertificate.trim();
  const userId = params.userId;

  const expire = (params.privilegeExpireTs >>> 0);

  // Privilege IDs (legacy AccessToken):
  // 1: RTM login
  const privileges: Record<number, number> = { 1: expire };
  const messageBytes = buildPrivilegeMessageBytes(privileges, expire);

  const toSign = concatBytes([
    utf8Bytes(appId),
    utf8Bytes(userId),
    // uidStr is empty for user-account tokens.
    utf8Bytes(""),
    messageBytes,
  ]);

  const signature = await hmacSha256(utf8Bytes(appCertificate), toSign);

  const content = concatBytes([
    packBytes(signature),
    u32le(crc32(utf8Bytes(userId))),
    u32le(crc32(utf8Bytes(""))),
    packBytes(messageBytes),
  ]);

  return `${AGORA_TOKEN_VERSION}${appId}${base64Encode(content)}`;
}
