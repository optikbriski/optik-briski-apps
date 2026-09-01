// @ts-ignore
declare const Deno: any;

/**
 * Hitung story Instagram Business yang masih live, filter hari Asia/Jakarta.
 *
 * Secret (salah satu):
 *   META_PAGE_ACCESS_TOKEN  — Page token (Facebook Login + Page + IG)
 *   META_ACCESS_TOKEN       — alias
 *   INSTAGRAM_GRAPH_TOKEN   — Instagram Login token (graph.instagram.com)
 *
 * POST JWT Admin/Karyawan:
 *   { toko_id: string, tanggal?: "YYYY-MM-DD", force?: boolean }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CACHE_MS = 8 * 60 * 1000;
const GRAPH_VER = (Deno.env.get("META_GRAPH_VERSION") ?? "v21.0").trim() ||
  "v21.0";

type Body = {
  toko_id?: string;
  tanggal?: string;
  force?: boolean;
};

type IgAccount = { id: string; username?: string };

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function graphToken(): string {
  return (
    Deno.env.get("META_PAGE_ACCESS_TOKEN") ??
    Deno.env.get("META_ACCESS_TOKEN") ??
    Deno.env.get("INSTAGRAM_GRAPH_TOKEN") ??
    ""
  ).trim();
}

function jakartaYmd(d = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

function aliasesOf(tokoId: string): string[] {
  const t = tokoId.trim();
  if (t === "PUSAT" || t === "CABANG-PUSAT") return ["PUSAT", "CABANG-PUSAT"];
  return t ? [t] : [];
}

function cleanUsername(raw: unknown): string {
  return String(raw ?? "")
    .trim()
    .replace(/^@+/, "")
    .toLowerCase();
}

function graphHosts(): string[] {
  const preferred = (Deno.env.get("META_GRAPH_HOST") ?? "").trim();
  const out: string[] = [];
  if (preferred) out.push(preferred.replace(/^https?:\/\//, ""));
  for (const h of ["graph.facebook.com", "graph.instagram.com"]) {
    if (!out.includes(h)) out.push(h);
  }
  return out;
}

async function graphGet(
  pathAndQuery: string,
  token: string,
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const q = pathAndQuery.includes("?") ? "&" : "?";
  let lastStatus = 0;
  let lastData: Record<string, unknown> = {};
  for (const host of graphHosts()) {
    const url =
      `https://${host}/${GRAPH_VER}/${pathAndQuery}${q}access_token=${
        encodeURIComponent(token)
      }`;
    const res = await fetch(url);
    const data = await res.json().catch(() => ({}));
    lastStatus = res.status;
    lastData = data && typeof data === "object"
      ? data as Record<string, unknown>
      : {};
    if (res.ok) return { ok: true, status: res.status, data: lastData };
    const msg = String(
      (lastData.error as { message?: string } | undefined)?.message ?? "",
    ).toLowerCase();
    if (msg.includes("oauth") || msg.includes("invalid") || res.status === 400) {
      continue;
    }
    return { ok: false, status: res.status, data: lastData };
  }
  return { ok: false, status: lastStatus || 502, data: lastData };
}

function graphError(data: Record<string, unknown>, fallback: string): string {
  const err = data.error as { message?: string } | undefined;
  const msg = String(err?.message ?? "").trim();
  if (!msg) return fallback;
  const low = msg.toLowerCase();
  if (low.includes("expired") || low.includes("session")) {
    return "Token Instagram kedaluwarsa. Perbarui META_PAGE_ACCESS_TOKEN.";
  }
  if (low.includes("permission") || low.includes("(#10)") || low.includes("(#200)")) {
    return "Token IG kurang izin (instagram_basic / stories).";
  }
  return msg.length > 180 ? fallback : msg;
}

async function fetchJson(
  url: string,
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const res = await fetch(url);
  const data = await res.json().catch(() => ({}));
  return {
    ok: res.ok,
    status: res.status,
    data: data && typeof data === "object" ? data as Record<string, unknown> : {},
  };
}

async function listStories(
  igUserId: string,
  token: string,
): Promise<{ countForDay: (day: string) => number; username?: string }> {
  const items: Array<{ id?: string; timestamp?: string }> = [];
  let next: string | null =
    `${encodeURIComponent(igUserId)}/stories?fields=id,timestamp&limit=50`;
  let relative = true;
  for (let page = 0; page < 6 && next; page++) {
    const got = relative
      ? await graphGet(next, token)
      : await fetchJson(next);
    if (!got.ok) {
      throw new Error(graphError(got.data, "Gagal membaca story Instagram."));
    }
    const dataList = Array.isArray(got.data.data)
      ? got.data.data as Array<{ id?: string; timestamp?: string }>
      : [];
    items.push(...dataList);
    const paging = got.data.paging as { next?: string } | undefined;
    next = paging?.next ?? null;
    relative = false;
  }

  const me = await graphGet(
    `${encodeURIComponent(igUserId)}?fields=id,username`,
    token,
  );
  const username = me.ok
    ? cleanUsername((me.data as { username?: string }).username)
    : "";

  return {
    username: username || undefined,
    countForDay: (day: string) => {
      let n = 0;
      for (const it of items) {
        const ts = String(it.timestamp ?? "").trim();
        if (!ts) continue;
        const t = Date.parse(ts);
        if (!Number.isFinite(t)) continue;
        if (jakartaYmd(new Date(t)) === day) n += 1;
      }
      return n;
    },
  };
}

async function resolveIgUserId(
  token: string,
  username: string,
): Promise<IgAccount | null> {
  const want = cleanUsername(username);
  if (!want) return null;

  const fromAccounts = await graphGet(
    "me/accounts?fields=id,name,instagram_business_account{id,username}&limit=100",
    token,
  );
  if (fromAccounts.ok) {
    const pages = Array.isArray(fromAccounts.data.data)
      ? fromAccounts.data.data as Array<{
        instagram_business_account?: IgAccount;
      }>
      : [];
    for (const p of pages) {
      const ig = p.instagram_business_account;
      if (!ig?.id) continue;
      if (cleanUsername(ig.username) === want) {
        return { id: String(ig.id), username: cleanUsername(ig.username) };
      }
    }
  }

  const me = await graphGet(
    "me?fields=user_id,username,id,instagram_business_account{id,username}",
    token,
  );
  if (me.ok) {
    const d = me.data as {
      user_id?: string;
      username?: string;
      id?: string;
      instagram_business_account?: IgAccount;
    };
    if (cleanUsername(d.username) === want && (d.user_id || d.id)) {
      return { id: String(d.user_id || d.id), username: want };
    }
    const ig = d.instagram_business_account;
    if (ig?.id && cleanUsername(ig.username) === want) {
      return { id: String(ig.id), username: want };
    }
  }
  return null;
}

async function callerMayReadToko(
  userClient: ReturnType<typeof createClient>,
  userId: string,
  aliases: string[],
): Promise<boolean> {
  const { data: kary } = await userClient
    .from("karyawan")
    .select("toko_id")
    .eq("id", userId)
    .maybeSingle();
  const kToko = String(kary?.toko_id ?? "").trim();
  if (kToko && aliases.includes(kToko)) return true;

  const { data: prof } = await userClient
    .from("profiles")
    .select("role, toko_id")
    .eq("id", userId)
    .maybeSingle();
  const role = String(prof?.role ?? "").toLowerCase();
  if (
    role === "owner" ||
    role === "super_admin" ||
    role === "admin_pusat" ||
    role === "platform"
  ) {
    return true;
  }
  const pToko = String(prof?.toko_id ?? "").trim();
  if (
    (role === "admin_toko" || role === "kasir") &&
    pToko &&
    aliases.includes(pToko)
  ) {
    return true;
  }
  return false;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json(401, { error: "Unauthorized" });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseAnon) {
      throw new Error("SUPABASE_URL / SUPABASE_ANON_KEY missing.");
    }

    const userClient = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: authData, error: authError } = await userClient.auth
      .getUser();
    if (authError || !authData.user) {
      return json(401, { error: "JWT tidak valid. Login ulang." });
    }

    const body = (await req.json().catch(() => ({}))) as Body;
    const tokoId = String(body.toko_id ?? "").trim();
    if (!tokoId) return json(400, { error: "toko_id wajib." });
    const day = String(body.tanggal ?? "").trim() || jakartaYmd();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) {
      return json(400, { error: "tanggal harus YYYY-MM-DD." });
    }
    const force = body.force === true;
    const aliases = aliasesOf(tokoId);

    const allowed = await callerMayReadToko(
      userClient,
      authData.user.id,
      aliases,
    );
    if (!allowed) {
      return json(403, { error: "Bukan cabang Anda." });
    }

    const { data: tokoRows, error: tokoErr } = await userClient
      .from("toko_id")
      .select("id, ig_user_id, ig_username, tenant_id")
      .in("id", aliases);
    if (tokoErr) {
      return json(400, {
        error:
          "Kolom Instagram toko belum ada. Jalankan SQL sop_ig_story dulu.",
      });
    }
    const tokos = (tokoRows ?? []) as Array<{
      id?: string;
      ig_user_id?: string;
      ig_username?: string;
      tenant_id?: string;
    }>;
    if (tokos.length === 0) {
      return json(404, { error: "Toko tidak ditemukan." });
    }

    let igUserId = "";
    let igUsername = "";
    let tenantId: string | null = null;
    for (const row of tokos) {
      const id = String(row.ig_user_id ?? "").replace(/\D/g, "");
      const un = cleanUsername(row.ig_username);
      if (!igUserId && id) igUserId = id;
      if (!igUsername && un) igUsername = un;
      if (!tenantId && row.tenant_id) tenantId = String(row.tenant_id);
    }

    if (!igUserId && !igUsername) {
      return json(200, {
        ok: true,
        configured: false,
        count: 0,
        tanggal: day,
      });
    }

    const admin = serviceKey
      ? createClient(supabaseUrl, serviceKey)
      : null;

    if (!force && admin) {
      const { data: cached } = await admin
        .from("sop_ig_story_cache")
        .select("story_count, ig_username, ig_user_id, fetched_at")
        .eq("toko_id", tokoId)
        .eq("tanggal", day)
        .maybeSingle();
      const fetchedAt = cached?.fetched_at
        ? Date.parse(String(cached.fetched_at))
        : NaN;
      if (
        cached &&
        Number.isFinite(fetchedAt) &&
        Date.now() - fetchedAt < CACHE_MS
      ) {
        return json(200, {
          ok: true,
          configured: true,
          cached: true,
          count: Number(cached.story_count) || 0,
          tanggal: day,
          ig_user_id: cached.ig_user_id ?? igUserId,
          ig_username: cached.ig_username ?? igUsername,
        });
      }
    }

    const token = graphToken();
    if (!token) {
      return json(500, {
        error:
          "META_PAGE_ACCESS_TOKEN belum di-set di Edge Function Secrets.",
      });
    }

    if (!igUserId && igUsername) {
      const resolved = await resolveIgUserId(token, igUsername);
      if (!resolved) {
        return json(422, {
          error:
            "Username IG tidak ketemu di Page yang terhubung. Isi IG User ID (angka) di Admin.",
        });
      }
      igUserId = resolved.id;
      igUsername = resolved.username || igUsername;
    }

    const stories = await listStories(igUserId, token);
    if (stories.username) igUsername = stories.username;
    const count = stories.countForDay(day);

    if (admin) {
      await admin.from("sop_ig_story_cache").upsert({
        toko_id: tokoId,
        tanggal: day,
        story_count: count,
        ig_user_id: igUserId,
        ig_username: igUsername || null,
        fetched_at: new Date().toISOString(),
        tenant_id: tenantId,
      }, { onConflict: "toko_id,tanggal" });

      if (igUsername) {
        for (const row of tokos) {
          const id = String(row.id ?? "");
          if (!id) continue;
          const patch: Record<string, string> = {};
          if (!String(row.ig_user_id ?? "").replace(/\D/g, "")) {
            patch.ig_user_id = igUserId;
          }
          if (!cleanUsername(row.ig_username) && igUsername) {
            patch.ig_username = igUsername;
          }
          if (Object.keys(patch).length === 0) continue;
          await admin.from("toko_id").update(patch).eq("id", id);
        }
      }
    }

    return json(200, {
      ok: true,
      configured: true,
      cached: false,
      count,
      tanggal: day,
      ig_user_id: igUserId,
      ig_username: igUsername || null,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json(500, { error: msg || "Gagal cek story Instagram." });
  }
});
