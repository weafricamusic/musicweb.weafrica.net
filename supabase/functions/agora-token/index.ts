import { serve } from "https://deno.land/std/http/server.ts";
import pkg from "npm:agora-access-token";

const { RtcTokenBuilder, RtcRole } = pkg;

serve(async (req) => {
  const url = new URL(req.url);

  const channel = url.searchParams.get("channel");
  const uid = parseInt(url.searchParams.get("uid") || "0");

  if (!channel) {
    return new Response(
      JSON.stringify({ error: "Missing channel" }),
      { status: 400 }
    );
  }

  const appId = Deno.env.get("AGORA_APP_ID");
  const appCertificate = Deno.env.get("AGORA_APP_CERT");

  if (!appId || !appCertificate) {
    return new Response(
      JSON.stringify({ error: "Missing Agora config" }),
      { status: 500 }
    );
  }

  const role = RtcRole.SUBSCRIBER;
  const expireTime = 3600;
  const currentTime = Math.floor(Date.now() / 1000);
  const privilegeExpireTime = currentTime + expireTime;

  const token = RtcTokenBuilder.buildTokenWithUid(
    appId,
    appCertificate,
    channel,
    uid,
    role,
    privilegeExpireTime
  );

  return new Response(
    JSON.stringify({ token }),
    { headers: { "Content-Type": "application/json" } }
  );
});