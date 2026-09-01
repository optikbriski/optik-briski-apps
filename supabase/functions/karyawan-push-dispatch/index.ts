// Edge Function: kirim FCM ke token karyawan cabang (kill-state).
// Secrets (salah satu):
//   FCM_SERVER_KEY          — legacy FCM server key
//   FCM_SERVICE_ACCOUNT_JSON — JSON service account (FCM HTTP v1)
// Tanpa secret → { ok:true, skipped:true } (build/deploy aman).

// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Body = {
  toko_id?: string;
  user_ids?: string[];
  judul?: string;
  isi?: string;
  tipe?: string;
  payload?: string;
};

function b64url(data: Uint8Array): string {
  let s = btoa(String.fromCharCode(...data));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

async function accessTokenFromServiceAccount(
  sa: Record<string, string>,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claim = b64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(new Uint8Array(sig))}`;
  const tokRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokJson = await tokRes.json();
  if (!tokRes.ok || !tokJson.access_token) {
    throw new Error(`oauth: ${JSON.stringify(tokJson)}`);
  }
  return tokJson.access_token as string;
}

async function sendLegacy(
  serverKey: string,
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<number> {
  let sent = 0;
  for (const to of tokens) {
    const res = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        Authorization: `key=${serverKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        to,
        priority: "high",
        notification: { title, body },
        data,
      }),
    });
    if (res.ok) sent++;
  }
  return sent;
}

async function sendV1(
  sa: Record<string, string>,
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<number> {
  const access = await accessTokenFromServiceAccount(sa);
  const projectId = sa.project_id;
  let sent = 0;
  for (const token of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${access}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data,
            android: { priority: "HIGH" },
          },
        }),
      },
    );
    if (res.ok) sent++;
  }
  return sent;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const body = (await req.json()) as Body;
    const judul = String(body.judul || "Pengingat").slice(0, 120);
    const isi = String(body.isi || "").slice(0, 400);
    const tipe = String(body.tipe || "INFO");
    const toko = String(body.toko_id || "").trim();
    const payload = String(body.payload || "").trim();
    const userIds = Array.isArray(body.user_ids)
      ? body.user_ids.map((x) => String(x)).filter(Boolean)
      : [];

    const serverKey = Deno.env.get("FCM_SERVER_KEY")?.trim() || "";
    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")?.trim() || "";
    if (!serverKey && !saRaw) {
      return new Response(
        JSON.stringify({
          ok: true,
          skipped: true,
          reason: "no_fcm_secret",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let q = supabase
      .from("karyawan_push_tokens")
      .select("token, karyawan_id, user_id");
    if (userIds.length > 0) {
      q = q.in("user_id", userIds);
    } else if (toko) {
      const { data: idsRpc, error: rpcErr } = await supabase.rpc(
        "list_karyawan_ids_for_toko",
        { p_toko: toko },
      );
      if (rpcErr) throw rpcErr;
      const ids = Array.isArray(idsRpc)
        ? idsRpc.map((x: string) => String(x)).filter(Boolean)
        : [];
      if (ids.length === 0) {
        return new Response(
          JSON.stringify({ ok: true, sent: 0, tokens: 0 }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      q = q.in("karyawan_id", ids);
    } else {
      return new Response(
        JSON.stringify({ ok: false, error: "toko_id atau user_ids wajib" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: rows, error } = await q;
    if (error) throw error;
    const tokens = [
      ...new Set(
        (rows || [])
          .map((r: { token?: string }) => String(r.token || "").trim())
          .filter((t: string) => t && !t.startsWith("local:")),
      ),
    ];

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({
          ok: true,
          sent: 0,
          tokens: 0,
          note: "hanya local: atau belum ada FCM token",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const data: Record<string, string> = { judul, isi, tipe };
    if (payload) data.payload = payload;
    let sent = 0;
    if (saRaw) {
      const sa = JSON.parse(saRaw) as Record<string, string>;
      sent = await sendV1(sa, tokens, judul, isi, data);
    } else {
      sent = await sendLegacy(serverKey, tokens, judul, isi, data);
    }

    return new Response(
      JSON.stringify({ ok: true, sent, tokens: tokens.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: String(e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
