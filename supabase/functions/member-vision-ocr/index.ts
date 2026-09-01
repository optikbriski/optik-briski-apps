// @ts-ignore
declare const Deno: any;

/**
 * Cloud Vision untuk APK Member (resep dokter, form).
 * Sesi HP + member_id, bukan Auth JWT — sama pola member-help-bot.
 *
 * Secret: GOOGLE_VISION_API_KEY
 *
 * POST JSON (anon apikey):
 *   { image_base64, member_id, phone, kind?: "rx"|"handwriting"|"form" }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_BYTES = 2_500_000;
const BLOCKED_KINDS = new Set(["ktp", "ikd", "e-ktp", "ektp"]);
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 8;
const rateBucket = new Map<string, { count: number; resetAt: number }>();

type Body = {
  image_base64?: string;
  kind?: string;
  member_id?: string;
  phone?: string;
};

const MAX_TOKENS = 600;

type Vertex = { x?: number; y?: number };

function boxOf(vertices: Vertex[] | undefined) {
  if (!Array.isArray(vertices) || vertices.length === 0) return null;
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const v of vertices) {
    const x = Number(v?.x ?? 0);
    const y = Number(v?.y ?? 0);
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
    minX = Math.min(minX, x);
    minY = Math.min(minY, y);
    maxX = Math.max(maxX, x);
    maxY = Math.max(maxY, y);
  }
  if (!Number.isFinite(minX) || minX === Infinity) return null;
  return { minX, minY, maxX, maxY };
}

function extractVisionTokens(first: Record<string, unknown> | undefined) {
  const out: Array<Record<string, number | string>> = [];
  const pages = (first as { fullTextAnnotation?: { pages?: unknown[] } })
    ?.fullTextAnnotation?.pages;
  if (Array.isArray(pages)) {
    for (const page of pages) {
      const p = page as {
        width?: number;
        height?: number;
        blocks?: unknown[];
      };
      const pw = Math.max(1, Number(p.width) || 1);
      const ph = Math.max(1, Number(p.height) || 1);
      for (const block of p.blocks ?? []) {
        const paras =
          (block as { paragraphs?: unknown[] }).paragraphs ?? [];
        for (const para of paras) {
          const words = (para as { words?: unknown[] }).words ?? [];
          for (const word of words) {
            const w = word as {
              symbols?: Array<{ text?: string }>;
              boundingBox?: {
                vertices?: Vertex[];
                normalizedVertices?: Vertex[];
              };
            };
            const text = (w.symbols ?? [])
              .map((s) => String(s?.text ?? ""))
              .join("")
              .trim();
            if (!text) continue;
            const verts = w.boundingBox?.vertices ??
              w.boundingBox?.normalizedVertices ?? [];
            const box = boxOf(verts);
            if (!box) continue;
            const looksNorm = box.maxX <= 1.5 && box.maxY <= 1.5 && pw > 8;
            const x0 = looksNorm ? box.minX : box.minX / pw;
            const x1 = looksNorm ? box.maxX : box.maxX / pw;
            const y0 = looksNorm ? box.minY : box.minY / ph;
            const y1 = looksNorm ? box.maxY : box.maxY / ph;
            out.push({
              text,
              cx: (x0 + x1) / 2,
              cy: (y0 + y1) / 2,
              x0,
              x1,
              y0,
              y1,
            });
            if (out.length >= MAX_TOKENS) return out;
          }
        }
      }
    }
    if (out.length) return out;
  }

  const ann = (first as { textAnnotations?: unknown[] })?.textAnnotations;
  if (!Array.isArray(ann) || ann.length < 2) return out;
  const pageAnn = ann[0] as {
    boundingPoly?: { vertices?: Vertex[] };
  };
  const pageBox = boxOf(pageAnn.boundingPoly?.vertices);
  const pw = pageBox ? Math.max(1, pageBox.maxX) : 1;
  const ph = pageBox ? Math.max(1, pageBox.maxY) : 1;
  for (let i = 1; i < ann.length && out.length < MAX_TOKENS; i++) {
    const a = ann[i] as {
      description?: string;
      boundingPoly?: { vertices?: Vertex[] };
    };
    const text = String(a.description ?? "").trim();
    if (!text) continue;
    const box = boxOf(a.boundingPoly?.vertices);
    if (!box) continue;
    const x0 = box.minX / pw;
    const x1 = box.maxX / pw;
    const y0 = box.minY / ph;
    const y1 = box.maxY / ph;
    out.push({
      text,
      cx: (x0 + x1) / 2,
      cy: (y0 + y1) / 2,
      x0,
      x1,
      y0,
      y1,
    });
  }
  return out;
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function digits(s: string): string {
  return s.replace(/\D/g, "");
}

function checkRate(key: string): boolean {
  const now = Date.now();
  const cur = rateBucket.get(key);
  if (!cur || now >= cur.resetAt) {
    rateBucket.set(key, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  if (cur.count >= RATE_MAX) return false;
  cur.count += 1;
  return true;
}

function decodeBase64Image(imageBase64: string): Uint8Array {
  const bin = atob(imageBase64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const apiKey = (Deno.env.get("GOOGLE_VISION_API_KEY") ?? "").trim();
    if (!supabaseUrl || !serviceKey) {
      throw new Error("SUPABASE_URL / SERVICE_ROLE missing.");
    }
    if (!apiKey) {
      return json(500, {
        error:
          "GOOGLE_VISION_API_KEY belum di-set di Supabase Edge Function Secrets.",
      });
    }

    const body = (await req.json()) as Body;
    const memberId = (body.member_id ?? "").trim();
    const phone = digits(body.phone ?? "");
    if (!memberId || phone.length < 8) {
      return json(401, { error: "Login dulu." });
    }

    const db = createClient(supabaseUrl, serviceKey);
    const { data: member } = await db
      .from("members")
      .select("id, phone_e164, phone_raw")
      .eq("id", memberId)
      .maybeSingle();
    if (!member) {
      return json(401, { error: "Member tidak ditemukan." });
    }
    const stored = digits(String(member.phone_e164 || member.phone_raw || ""));
    if (!stored || stored.slice(-8) !== phone.slice(-8)) {
      return json(401, { error: "Sesi member tidak cocok." });
    }
    if (!checkRate(`m:${memberId}`)) {
      return json(429, { error: "Terlalu banyak scan. Coba sebentar lagi." });
    }

    const kind = (body.kind ?? "rx").trim().toLowerCase();
    if (BLOCKED_KINDS.has(kind)) {
      return json(400, {
        error: "KTP/IKD tidak dikirim ke Cloud Vision.",
      });
    }

    const imageBase64 = body.image_base64 || "";
    if (!imageBase64) {
      return json(400, { error: "image_base64 wajib" });
    }
    const cleanedB64 = imageBase64.includes(",")
      ? imageBase64.split(",").pop()!
      : imageBase64;
    const bytes = decodeBase64Image(cleanedB64);
    if (bytes.length < 800) {
      return json(400, { error: "Foto terlalu kecil / rusak." });
    }
    if (bytes.length > MAX_BYTES) {
      return json(413, { error: "Foto terlalu besar. Ambil ulang lebih dekat." });
    }

    const visionRes = await fetch(
      `https://vision.googleapis.com/v1/images:annotate?key=${
        encodeURIComponent(apiKey)
      }`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          requests: [
            {
              image: { content: cleanedB64 },
              features: [{ type: "DOCUMENT_TEXT_DETECTION" }],
              imageContext: { languageHints: ["id", "en"] },
            },
          ],
        }),
      },
    );
    const visionJson = await visionRes.json();
    if (!visionRes.ok) {
      const msg = visionJson?.error?.message ||
        `Cloud Vision HTTP ${visionRes.status}`;
      return json(502, { error: String(msg) });
    }
    const first = visionJson?.responses?.[0];
    if (first?.error?.message) {
      return json(422, { error: String(first.error.message) });
    }
    const text = String(
      first?.fullTextAnnotation?.text ??
        first?.textAnnotations?.[0]?.description ??
        "",
    ).trim();
    return json(200, { ok: true, text, tokens: extractVisionTokens(first) });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json(500, { error: msg || "OCR gagal." });
  }
});
