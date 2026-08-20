// Member help bot — Gemini Flash grounded answers + WA escalate.
//
// Secrets (Supabase Dashboard → Edge Functions → Secrets, or CLI):
//   GEMINI_API_KEY          — Google AI Studio / Gemini API key (server only)
//   GEMINI_MODEL            — optional preferred model (tried first)
//   SUPABASE_URL            — auto-injected
//   SUPABASE_SERVICE_ROLE_KEY — auto-injected
//
// Deploy:
//   supabase secrets set GEMINI_API_KEY=your_key_here
//   supabase functions deploy member-help-bot --no-verify-jwt
//   (Member app uses anon + custom session, not Supabase Auth JWT.)

// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { fallbackBrand, loadBrand } from "../_shared/brand.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_MESSAGE = 500;
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 20;

/**
 * Prefer Flash Lite first (higher free-tier headroom, little/no thinking).
 * gemini-2.0-flash was shut down (2026-06-01). Avoid retired IDs.
 */
const DEFAULT_GEMINI_MODELS = [
  "gemini-2.5-flash-lite",
  "gemini-2.5-flash",
  "gemini-3-flash-preview",
  "gemini-3.5-flash",
  "gemini-3.6-flash",
];

/** In-memory soft rate limit (per isolate). */
const rateBucket = new Map<string, { count: number; resetAt: number }>();

function faqFor(brand: string): string {
  return `
FAQ ${brand} (Member):
- Perawatan: cuci air + sabun lembut lensa; keringkan microfiber; lepas saat olahraga kontak/berenang.
- Garansi aktif 7 hari sejak diambil di toko (hari diambil s/d hari ke-7). Lebih dari 7 hari → garansi mati, tidak bisa klaim. Klaim wajib datang membawa barang; maks. 1× per transaksi. Batal jika: benturan/terjatuh/disengaja, modifikasi sendiri, kehilangan (bukan tanggung jawab toko).
- Jam umum: 09:00–21:00 (bisa beda per cabang / libur). Jam hari ini berubah / konfirmasi rak fisik sekarang / nego / keluhan fisik / jumlah orang di lobby → WhatsApp cabang.
- Antrean pengerjaan/lab cabang (menunggu / sedang dikerjakan / siap diambil) tersedia dari agregat data sistem invoice — bukan jumlah orang di lobby. Jangan mengarang menit tunggu lobby.
- Stok sistem cabang (ringkasan kategori / SKU available_qty = stock − reserved) tersedia dari data produk aplikasi — bukan audit rak fisik. Pertanyaan ready/stok/frame tersedia dijawab dari stok sistem tanpa WhatsApp. Hanya konfirmasi rak fisik eksplisit / data tidak ada → WhatsApp.
- Poin Reward bisa ditukar voucher; Status Poin menentukan grade (Basic/Silver/Gold/Platinum/Diamond).
- Status pesanan hanya dari data sistem yang diberikan; jangan mengarang.
`.trim();
}

/** True lobby / physical-shelf confirm / nego / physical / today's hours — WA only. */
const LIVE_HINTS = [
  "nego",
  "negoisasi",
  "tawar",
  "stok rak",
  "stok di rak",
  "ada di rak",
  "di rak sekarang",
  "fisik",
  "retak",
  "patah",
  "baret",
  "komplain",
  "complaint",
  "keluhan",
  "hari ini buka",
  "masih buka",
  "masih tutup",
  "jam berapa tutup",
  "jam tutup hari ini",
  "berapa orang",
  "orang di toko",
  "orang di lobby",
  "antrean lobby",
  "antrian lobby",
  "lobby queue",
];

/** Production / lab / RO pipeline load from invoices (aggregates). */
const LAB_QUEUE_HINTS = [
  "antre",
  "antrian",
  "antrean",
  "queue",
  "rame",
  "sepi",
  "lagi full",
  "berapa lama",
  "lama pengerjaan",
  "lama dikerjakan",
  "beban lab",
  "beban pengerjaan",
  "antrean lab",
  "antrian lab",
  "lab queue",
  "pengerjaan lab",
  "pengerjaan kacamata",
  "sedang dikerjakan",
  "belum dikerjakan",
  "menunggu dikerjakan",
  "job lab",
];

/** System stock / availability from products (not physical shelf audit). */
const STOK_HINTS = [
  "cek stok",
  "cek stock",
  "stok frame",
  "stok lensa",
  "stock frame",
  "stock lensa",
  "ada stok",
  "ada stock",
  "sisa stok",
  "sisa stock",
  "stok cabang",
  "stok toko",
  "stock cabang",
  "stock toko",
  "stok tersedia",
  "stock tersedia",
  "berapa stok",
  "berapa stock",
  "masih ada stok",
  "masih ada stock",
  "ready stock",
  "ready stok",
  "stock ready",
  "stok ready",
  // Colloquial "what's ready / available" (system stock, not shelf audit).
  "yang ready",
  "ready apa",
  "apa yang ready",
  "frame ready",
  "ready frame",
  "lensa ready",
  "ready lensa",
  "barang ready",
  "ready barang",
  "yang tersedia",
  "barang di toko",
  "available stock",
  "availability",
  "in stock",
];

/** Free-text asking for WA / branch contact — escalate; never list phones. */
const WA_CONTACT_HINTS = [
  "nomor wa",
  "nomer wa",
  "no wa",
  "no. wa",
  "no.wa",
  "nomor whatsapp",
  "nomer whatsapp",
  "whatsapp",
  "whats app",
  "bagi nomor",
  "minta nomor",
  "bagi wa",
  "minta wa",
  "kasih nomor",
  "kasih wa",
  "share nomor",
  "hubungi cabang",
  "hubungi toko",
  "chat toko",
  "chat cabang",
  "chat wa",
  "wa toko",
  "wa cabang",
  "kontak wa",
  "kontak cabang",
  "contact wa",
  "contact branch",
  "customer service",
  "hubungi cs",
  "nomor cs",
  "admin wa",
];

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function needsLive(text: string): boolean {
  const t = text.toLowerCase();
  return LIVE_HINTS.some((p) => t.includes(p));
}

function needsLabQueue(text: string): boolean {
  const t = text.toLowerCase().trim();
  if (!t) return false;
  // Longer phrases — substring OK.
  const phrases = LAB_QUEUE_HINTS.filter((p) =>
    !["antre", "queue", "rame", "sepi"].includes(p)
  );
  if (phrases.some((p) => t.includes(p))) return true;
  // Short tokens — word boundary only ("rame" must not match "frame"/"rayban").
  for (const w of ["antre", "queue", "rame", "sepi"]) {
    if (new RegExp(`(^|[^a-z])${w}([^a-z]|$)`).test(t)) return true;
  }
  return false;
}

function needsStok(text: string): boolean {
  const t = text.toLowerCase().trim();
  if (!t) return false;
  if (STOK_HINTS.some((p) => t.includes(p))) return true;
  if (/(^|[^a-z])stok([^a-z]|$)/.test(t)) return true;
  if (/(^|[^a-z])stock([^a-z]|$)/.test(t)) return true;
  // "ada/ready/tersedia + frame|lensa|…" → system availability (not WA).
  const hasProduct =
    /(^|[^a-z])(frame|lensa|kacamata|barang|sku|produk)([^a-z]|$)/.test(t);
  const hasAvail =
    /(^|[^a-z])(ready|tersedia|available|sisa|ada)([^a-z]|$)/.test(t);
  if (hasProduct && hasAvail) return true;
  return false;
}

function extractStockQuery(raw: string): string {
  let t = raw.toLowerCase().trim();
  if (!t) return "";
  // Longer phrases first so colloquial summary asks collapse to empty query.
  const dropPhrases = [
    "cek stok",
    "cek stock",
    "stok frame",
    "stok lensa",
    "stock frame",
    "stock lensa",
    "ada stok",
    "ada stock",
    "stok ada",
    "stock ada",
    "ada apa aja",
    "apa aja",
    "ada apa",
    "sisa stok",
    "sisa stock",
    "stok cabang",
    "stok toko",
    "stock cabang",
    "stock toko",
    "stok tersedia",
    "stock tersedia",
    "berapa stok",
    "berapa stock",
    "masih ada stok",
    "masih ada stock",
    "ready stock",
    "ready stok",
    "stock ready",
    "stok ready",
    "yang ready",
    "ready apa",
    "apa yang ready",
    "frame ready",
    "ready frame",
    "lensa ready",
    "ready lensa",
    "barang ready",
    "ready barang",
    "yang tersedia",
    "barang di toko",
    "available stock",
    "availability",
    "in stock",
    "optik b. riski",
    "optik b riski",
  ];
  for (const p of dropPhrases) t = t.split(p).join(" ");
  const dropWords = new Set([
    "stok",
    "stock",
    "cek",
    "ada",
    "apakah",
    "apa",
    "aja",
    "ajah",
    "ajahh",
    "sih",
    "nih",
    "deh",
    "lah",
    "kah",
    "dong",
    "ya",
    "yuk",
    "tolong",
    "minta",
    "lihat",
    "cari",
    "berapa",
    "sisa",
    "ready",
    "available",
    "availability",
    "barang",
    "yang",
    "di",
    "untuk",
    "cabang",
    "toko",
    "masih",
    "tersedia",
    "sistem",
    "app",
    "aplikasi",
    "kak",
    "min",
    "bang",
    "bro",
    "sis",
    "mas",
    "mbak",
    "gak",
    "ga",
    "nggak",
    "ngga",
    "please",
    "the",
    "a",
    "an",
    "is",
    "are",
    "any",
    "have",
    "has",
    "do",
    "does",
    "you",
    "what",
  ]);
  // Cabang tokens (e.g. "singaparna" from "stok di Singaparna") are location,
  // not product names — strip so summary mode runs at the overridden toko.
  const namedDrop = new Set(
    extractNamedTokoQuery(raw).split(/\s+/).filter((w) => w.length >= 2),
  );
  return t
    .replace(/[^\w\s\-+/]/g, " ")
    .split(/\s+/)
    .filter((w) => w && !dropWords.has(w) && !namedDrop.has(w))
    .join(" ")
    .trim();
}

function looksLikeOwnOrder(text: string): boolean {
  const t = text.toLowerCase();
  const keys = [
    "status pesanan",
    "cek pesanan",
    "pesanan saya",
    "order status",
    "invoice",
    "nota",
    "lacak",
    "tracking",
  ];
  return keys.some((p) => t.includes(p));
}

function formatLabQueueReply(
  locale: string,
  tokoId: string,
  waiting: number,
  inProgress: number,
  ready: number,
  shopName?: string | null,
) {
  const en = locale.toLowerCase().startsWith("en");
  const tid = (tokoId || "").trim().toUpperCase();
  const name = (shopName || "").trim();
  const label = name ? `${tid} (${name})` : tid;
  if (en) {
    return (
      `Estimated lab/production load at ${label} from system data ` +
      `(invoice pipeline — not people standing in the lobby):\n` +
      `• Waiting to be worked: ${waiting} invoice(s)\n` +
      `• In progress: ${inProgress} invoice(s)\n` +
      `• Ready for pickup: ${ready} invoice(s)\n\n` +
      `This is the branch work queue from invoices/lab jobs, not lobby wait minutes. ` +
      `For physical shelf confirmation right now, negotiation, or physical complaints — WhatsApp the branch. ` +
      `For app/system stock by SKU or category, use the stock chip or ask “cek stok …”.`
    );
  }
  return (
    `Estimasi beban pengerjaan lab di cabang ${label} dari data sistem ` +
    `(pipeline invoice — bukan jumlah orang di lobby):\n` +
    `• Menunggu dikerjakan: ${waiting} invoice\n` +
    `• Sedang dikerjakan: ${inProgress} invoice\n` +
    `• Siap diambil: ${ready} invoice\n\n` +
    `Ini antrean pengerjaan/lab dari invoice, bukan antrean orang di toko. ` +
    `Estimasi menit tunggu di lobby tidak tersedia. ` +
    `Untuk konfirmasi rak fisik sekarang, nego, atau keluhan fisik — WhatsApp cabang. ` +
    `Untuk stok sistem (SKU/kategori) pakai chip stok atau tanya “cek stok …”.`
  );
}

function formatStokReply(
  locale: string,
  row: Record<string, unknown>,
  shopName?: string | null,
) {
  const en = locale.toLowerCase().startsWith("en");
  const tid = String(row.toko_id ?? "").trim().toUpperCase();
  const name = (shopName || "").trim();
  const label = name ? `${tid} (${name})` : tid;
  const mode = String(row.mode ?? "summary").toLowerCase();
  const query = String(row.query ?? "").trim();
  const skusInStock = Number(row.skus_in_stock ?? 0) || 0;
  const byKat = Array.isArray(row.by_kategori) ? row.by_kategori : [];
  const matches = Array.isArray(row.matches) ? row.matches : [];
  const lines: string[] = [];

  let offerWaNote = false;
  const disclaimerBase = en
    ? "This is app/system availability (stock − reserved), not a physical shelf audit."
    : "Ini stok sistem aplikasi (stock − reserved), bukan audit rak fisik.";
  const disclaimerWa = en
    ? " For a live shelf check, chat the branch on WhatsApp."
    : " Untuk cek rak langsung, chat cabang via WhatsApp.";

  if (mode === "search") {
    if (matches.length === 0) {
      offerWaNote = true;
      lines.push(
        en
          ? `No matching SKU in system stock at ${label}${
            query ? ` for “${query}”` : ""
          }.`
          : `Tidak ketemu SKU cocok di stok sistem cabang ${label}${
            query ? ` untuk “${query}”` : ""
          }.`,
      );
      lines.push(
        en
          ? "Try a clearer product name/SKU, or ask the branch for a shelf check."
          : "Coba nama/SKU lebih spesifik, atau tanya cabang untuk cek rak.",
      );
    } else {
      lines.push(
        en
          ? `System stock at ${label}${query ? ` for “${query}”` : ""}:`
          : `Stok sistem di cabang ${label}${query ? ` untuk “${query}”` : ""}:`,
      );
      for (const raw of matches) {
        const m = raw as Record<string, unknown>;
        const sku = String(m.sku ?? "").trim();
        const nama = String(m.nama ?? "").trim();
        const kat = String(m.kategori ?? "").trim();
        const warna = String(m.warna ?? "").trim();
        const avail = clampNonNegQty(Number(m.available_qty ?? 0));
        const meta = [kat, warna].filter(Boolean).join(" · ");
        const status = en
          ? (avail > 0 ? `available: ${avail}` : "out of stock (0)")
          : (avail > 0 ? `tersedia: ${avail}` : "habis (0)");
        const title = sku ? `${sku} — ${nama}` : nama;
        lines.push(meta ? `• ${title} (${meta}) — ${status}` : `• ${title} — ${status}`);
      }
    }
  } else {
    lines.push(
      en
        ? `System stock summary at ${label} (${skusInStock} SKU(s) with available qty > 0):`
        : `Ringkasan stok sistem cabang ${label} (${skusInStock} SKU tersedia):`,
    );
    const cats = byKat.filter((raw) => {
      const c = raw as Record<string, unknown>;
      const n = clampNonNegQty(Number(c.skus_in_stock ?? 0));
      const tot = clampNonNegQty(Number(c.total_available ?? 0));
      return n > 0 || tot > 0;
    });
    if (cats.length === 0 || skusInStock <= 0) {
      offerWaNote = true;
      lines.push(
        en
          ? "• No sellable SKUs with available qty right now in the system."
          : "• Belum ada SKU sellable dengan qty tersedia di sistem saat ini.",
      );
    } else {
      for (const raw of cats) {
        const c = raw as Record<string, unknown>;
        const kat = String(c.kategori ?? "Lainnya");
        const n = clampNonNegQty(Number(c.skus_in_stock ?? 0));
        const tot = clampNonNegQty(Number(c.total_available ?? 0));
        lines.push(
          en
            ? `• ${kat}: ${n} SKU in stock (total available qty ~${tot})`
            : `• ${kat}: ${n} SKU tersedia (total qty ~${tot})`,
        );
      }
    }
    if (matches.length > 0) {
      lines.push(
        en
          ? "Products in stock (tap in app for details, or ask with a name/SKU):"
          : "Produk tersedia (ketuk di app untuk detail, atau tanya nama/SKU):",
      );
      for (const raw of matches.slice(0, 15)) {
        const m = raw as Record<string, unknown>;
        const sku = String(m.sku ?? "").trim();
        const nama = String(m.nama ?? "").trim();
        const avail = clampNonNegQty(Number(m.available_qty ?? 0));
        const title = sku ? `${sku} — ${nama}` : nama;
        lines.push(
          en
            ? `• ${title} — available: ${avail}`
            : `• ${title} — tersedia: ${avail}`,
        );
      }
    } else {
      lines.push(
        en
          ? "Ask with a product name/SKU (e.g. “cek stok Rayban hitam”) for SKU-level qty."
          : "Tanya dengan nama/SKU produk (mis. “cek stok Rayban hitam”) untuk qty per SKU.",
      );
    }
  }

  const disclaimer = offerWaNote
    ? `${disclaimerBase}${disclaimerWa}`
    : disclaimerBase;
  return `${lines.join("\n")}\n\n${disclaimer}`;
}

async function answerLabQueue(
  db: ReturnType<typeof createClient>,
  opts: { locale: string; tokoId: string | null; message: string },
) {
  const en = opts.locale.toLowerCase().startsWith("en");
  const { toko, shopName } = await resolveTokoFromMessage(db, opts);

  if (!toko) {
    return {
      reply: en
        ? "Name a branch (e.g. Depok) or set a preferred store, then ask again about lab/work queue."
        : "Sebut nama cabang (mis. Depok) atau set cabang pilihan, lalu tanya lagi tentang antrean lab/pengerjaan.",
      escalate_wa: false,
      intent: "labQueue",
      suggested_chips: ["labQueue", "storeInfo", "contactWa"],
      error_code: null,
    };
  }

  try {
    const { data, error } = await db.rpc("get_toko_lab_queue_counts", {
      p_toko_id: toko,
    });
    if (error) {
      console.error("get_toko_lab_queue_counts", error);
      return {
        reply: en
          ? `Could not load lab/work queue for ${toko}. Try again or WhatsApp the branch.`
          : `Gagal memuat antrean lab/pengerjaan cabang ${toko}. Coba lagi atau WhatsApp cabang.`,
        escalate_wa: true,
        intent: "labQueue",
        suggested_chips: ["labQueue", "contactWa"],
        error_code: null,
      };
    }
    const row = (data && typeof data === "object" ? data : {}) as Record<
      string,
      unknown
    >;
    const waiting = Number(row.waiting ?? 0) || 0;
    const inProgress = Number(row.in_progress ?? 0) || 0;
    const ready = Number(row.ready ?? 0) || 0;
    return {
      reply: formatLabQueueReply(
        opts.locale,
        String(row.toko_id ?? toko),
        waiting,
        inProgress,
        ready,
        shopName,
      ),
      escalate_wa: false,
      intent: "labQueue",
      suggested_chips: ["orderStatus", "contactWa"],
      error_code: null,
    };
  } catch (e) {
    console.error("lab queue answer", e);
    return {
      reply: en
        ? "Could not load lab/work queue. Please try WhatsApp."
        : "Gagal memuat antrean lab/pengerjaan. Silakan coba via WhatsApp.",
      escalate_wa: true,
      intent: "labQueue",
      suggested_chips: ["contactWa"],
      error_code: null,
    };
  }
}

/** Stock/lab/filler stripped before treating leftovers as an explicit cabang. */
const NAMED_TOKO_DROP_PHRASES = [
  "cek stok",
  "cek stock",
  "stok frame",
  "stok lensa",
  "stock frame",
  "stock lensa",
  "ada stok",
  "ada stock",
  "sisa stok",
  "sisa stock",
  "stok cabang",
  "stok toko",
  "stock cabang",
  "stock toko",
  "stok tersedia",
  "stock tersedia",
  "berapa stok",
  "berapa stock",
  "masih ada stok",
  "masih ada stock",
  "ready stock",
  "ready stok",
  "stock ready",
  "stok ready",
  "yang ready",
  "ready apa",
  "apa yang ready",
  "frame ready",
  "ready frame",
  "lensa ready",
  "ready lensa",
  "barang ready",
  "ready barang",
  "yang tersedia",
  "barang di toko",
  "available stock",
  "availability",
  "in stock",
  "antrean lab",
  "antrian lab",
  "lab queue",
  "beban lab",
  "beban pengerjaan",
  "pengerjaan lab",
  "pengerjaan kacamata",
  "lama pengerjaan",
  "lama dikerjakan",
  "sedang dikerjakan",
  "belum dikerjakan",
  "menunggu dikerjakan",
  "berapa lama",
  "lagi full",
  "job lab",
  "optik b. riski",
  "optik b riski",
];

const NAMED_TOKO_STOPWORDS = new Set([
  "dong",
  "ya",
  "yuk",
  "please",
  "tolong",
  "bang",
  "kak",
  "bro",
  "sis",
  "minta",
  "bagi",
  "kasih",
  "share",
  "kirim",
  "nomor",
  "nomer",
  "no",
  "hp",
  "telepon",
  "telp",
  "wa",
  "whatsapp",
  "whats",
  "app",
  "chat",
  "hubungi",
  "kontak",
  "contact",
  "customer",
  "service",
  "cs",
  "admin",
  "cabang",
  "toko",
  "branch",
  "store",
  "outlet",
  "ke",
  "di",
  "sama",
  "dengan",
  "yang",
  "untuk",
  "nya",
  "the",
  "a",
  "an",
  "to",
  "me",
  "my",
  "of",
  "and",
  "atau",
  "lah",
  "sih",
  "aja",
  "ajah",
  "nih",
  "deh",
  "stok",
  "stock",
  "cek",
  "apakah",
  "apa",
  "lihat",
  "cari",
  "berapa",
  "sisa",
  "ready",
  "available",
  "availability",
  "barang",
  "frame",
  "lensa",
  "kacamata",
  "sku",
  "produk",
  "sistem",
  "aplikasi",
  "antre",
  "antrean",
  "antrian",
  "queue",
  "rame",
  "sepi",
  "full",
  "lab",
  "pengerjaan",
  "dikerjakan",
  "menunggu",
  "sedang",
  "belum",
  "lama",
  "job",
  "beban",
  "estimasi",
  "info",
  "alamat",
  "jam",
  "buka",
  "tutup",
  "is",
  "are",
  "any",
  "have",
  "has",
  "do",
  "does",
  "you",
  "what",
  "which",
  "ada",
  "kah",
]);

function extractNamedTokoQuery(raw: string): string {
  let t = raw
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!t) return "";
  const phrases = [...NAMED_TOKO_DROP_PHRASES].sort((a, b) => b.length - a.length);
  for (const p of phrases) t = t.split(p).join(" ");
  t = t.replace(/\s+/g, " ").trim();
  if (!t) return "";
  return t
    .split(" ")
    .filter((tok) => tok.length >= 2 && !NAMED_TOKO_STOPWORDS.has(tok))
    .join(" ");
}

function clampNonNegQty(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return n < 0 ? 0 : Math.floor(n);
}

/**
 * Honor body toko_id for the session. Only override when the message clearly
 * names a different cabang after stripping stock/lab filler. Never fall back
 * to the first directory row while a selected toko_id is present.
 */
async function resolveTokoFromMessage(
  db: ReturnType<typeof createClient>,
  opts: { tokoId: string | null; message: string },
): Promise<{ toko: string; shopName: string | null }> {
  const selected = (opts.tokoId ?? "").trim().toUpperCase();
  let toko = selected;
  let shopName: string | null = null;

  try {
    const { data: stores } = await db
      .from("invoice_settings")
      .select("toko_id, shop_name, address")
      .order("toko_id")
      .limit(40);
    if (!Array.isArray(stores) || stores.length === 0) {
      return { toko, shopName };
    }

    const hint = extractNamedTokoQuery(opts.message);
    let named: { id: string; name: string; score: number } | null = null;
    if (hint) {
      for (const s of stores as Array<Record<string, unknown>>) {
        const id = String(s.toko_id ?? "").trim().toUpperCase();
        const name = String(s.shop_name ?? "").trim();
        const addr = String(s.address ?? "").toLowerCase();
        if (!id) continue;
        let score = 0;
        const idLower = id.toLowerCase();
        const nameLower = name.toLowerCase();
        if (hint === idLower || hint.includes(idLower) || idLower.includes(hint)) {
          score += 100;
        }
        if (nameLower && (nameLower.includes(hint) || hint.includes(nameLower))) {
          score += 80;
        }
        for (const tok of hint.split(/\s+/)) {
          if (tok.length < 3) continue;
          if (idLower.includes(tok)) score += 40;
          else if (nameLower.includes(tok)) score += 35;
          else if (addr.includes(tok)) score += 20;
        }
        // Distinctive slug from CABANG-X
        const slug = idLower.replace(/^cabang-/, "");
        if (slug.length >= 4 && (hint === slug || hint.includes(slug))) {
          score += 90;
        }
        if (score >= 70 && (!named || score > named.score)) {
          named = { id, name, score };
        }
      }
    }

    if (selected) {
      if (named && named.id !== selected) {
        toko = named.id;
        shopName = named.name || null;
      } else {
        toko = selected;
        for (const s of stores as Array<Record<string, unknown>>) {
          if (String(s.toko_id ?? "").trim().toUpperCase() === selected) {
            shopName = String(s.shop_name ?? "").trim() || null;
            break;
          }
        }
      }
      return { toko, shopName };
    }

    // No body toko_id — only explicit named cabang (never silent first-store).
    if (named) {
      toko = named.id;
      shopName = named.name || null;
    }
  } catch (_) {
    /* optional */
  }
  return { toko, shopName };
}

async function answerStok(
  db: ReturnType<typeof createClient>,
  opts: { locale: string; tokoId: string | null; message: string },
) {
  const en = opts.locale.toLowerCase().startsWith("en");
  const { toko, shopName } = await resolveTokoFromMessage(db, opts);
  const productQuery = extractStockQuery(opts.message);

  if (!toko) {
    return {
      reply: en
        ? "Name a branch (e.g. Depok) or set a preferred store, then ask again about stock."
        : "Sebut nama cabang (mis. Depok) atau set cabang pilihan, lalu tanya lagi tentang stok.",
      escalate_wa: false,
      intent: "stok",
      suggested_chips: ["stok", "storeInfo", "contactWa"],
      error_code: null,
    };
  }

  try {
    const { data, error } = await db.rpc("search_member_toko_stock", {
      p_toko_id: toko,
      p_q: productQuery || null,
      p_limit: 30,
    });
    if (error) {
      console.error("search_member_toko_stock", error);
      return {
        reply: en
          ? `Could not load system stock for ${toko}. Try again or WhatsApp the branch.`
          : `Gagal memuat stok sistem cabang ${toko}. Coba lagi atau WhatsApp cabang.`,
        escalate_wa: true,
        intent: "stok",
        suggested_chips: ["stok", "contactWa"],
        error_code: null,
      };
    }
    const row = (data && typeof data === "object" ? data : {}) as Record<
      string,
      unknown
    >;
    if (row.ok === false) {
      return {
        reply: en
          ? `Could not load system stock for ${toko}. Try again or WhatsApp the branch.`
          : `Gagal memuat stok sistem cabang ${toko}. Coba lagi atau WhatsApp cabang.`,
        escalate_wa: true,
        intent: "stok",
        suggested_chips: ["stok", "contactWa"],
        error_code: null,
      };
    }
    const matches = Array.isArray(row.matches) ? row.matches : [];
    const mode = String(row.mode ?? "summary").toLowerCase();
    const skusInStock = Number(row.skus_in_stock ?? 0) || 0;
    const noMatch = !!productQuery && mode === "search" && matches.length === 0;
    const ambiguous = !!productQuery &&
      matches.length > 1 &&
      matches.every((m) => {
        const x = m as Record<string, unknown>;
        return !(x.in_stock === true || (Number(x.available_qty ?? 0) || 0) > 0);
      });
    // True empty branch (summary with 0 in-stock SKUs) → WA. Successful
    // summary/search with matches → no WA CTA.
    const emptyBranch = mode === "summary" && skusInStock <= 0;
    const escalate = noMatch || ambiguous || emptyBranch;
    return {
      reply: formatStokReply(opts.locale, row, shopName),
      escalate_wa: escalate,
      intent: "stok",
      suggested_chips: escalate ? ["stok", "contactWa"] : ["stok"],
      error_code: null,
    };
  } catch (e) {
    console.error("stok answer", e);
    return {
      reply: en
        ? "Could not load system stock. Please try WhatsApp."
        : "Gagal memuat stok sistem. Silakan coba via WhatsApp.",
      escalate_wa: true,
      intent: "stok",
      suggested_chips: ["contactWa"],
      error_code: null,
    };
  }
}

function wantsWhatsAppContact(text: string): boolean {
  const t = text.toLowerCase().trim();
  if (!t) return false;
  if (WA_CONTACT_HINTS.some((p) => t.includes(p))) return true;
  if (/(^|[^a-z])cs([^a-z]|$)/.test(t)) return true;
  if (/(^|[^a-z])admin([^a-z]|$)/.test(t)) return true;
  return false;
}

function waContactFallback(locale: string) {
  // Client owns XOR UX (named branch / GPS open / ask location). Keep reply minimal.
  const en = locale.toLowerCase().startsWith("en");
  return {
    reply: en ? "Connecting you to WhatsApp…" : "Menghubungkan ke WhatsApp…",
    escalate_wa: true,
    intent: "contactWa",
    suggested_chips: ["contactWa"],
    error_code: null,
  };
}

function rateLimitKey(memberId: string | null, phone: string | null, ip: string) {
  return (memberId || phone || ip || "anon").toString().slice(0, 80);
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

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

type FallbackReason = "unconfigured" | "unavailable" | "rate_limit" | "live";

function keywordFallback(message: string, locale: string, reason: FallbackReason = "unavailable") {
  const en = locale.toLowerCase().startsWith("en");
  if (needsLive(message) || reason === "live") {
    return {
      reply: en
        ? "Live lobby info (how many people in-store), physical shelf confirmation right now, negotiation, physical complaints, or whether hours changed today isn’t readable from the app. Please ask the branch on WhatsApp. For app/system stock, ask “cek stok …” or use the stock chip. For lab/production queue load from invoices, ask about “antrean lab”."
        : "Info live lobby (berapa orang di toko), konfirmasi stok rak fisik sekarang, nego, keluhan fisik, atau jam buka hari ini berubah tidak bisa dibaca dari app. Silakan tanya cabang via WhatsApp. Untuk stok sistem aplikasi, tanya “cek stok …” atau pakai chip stok. Untuk beban antrean pengerjaan/lab dari invoice, tanya “antrean lab”.",
      escalate_wa: true,
      intent: "escalateLive",
      suggested_chips: ["contactWa", "stok", "labQueue", "orderStatus"],
      error_code: null,
    };
  }
  if (reason === "unconfigured") {
    return {
      reply: en
        ? "AI help is not configured yet. Try a quick-action chip, or chat with the store on WhatsApp."
        : "Bot AI belum dikonfigurasi. Coba chip cepat, atau hubungi cabang via WhatsApp.",
      escalate_wa: true,
      intent: "unknown",
      suggested_chips: [
        "orderStatus",
        "pointsGrade",
        "storeInfo",
        "labQueue",
        "stok",
        "careWarranty",
        "contactWa",
      ],
      error_code: "gemini_unconfigured",
    };
  }
  if (reason === "rate_limit") {
    return {
      reply: en
        ? "AI is busy right now (rate limit). Wait a few seconds and try again, or use a quick-action chip / WhatsApp."
        : "AI sedang sibuk (batas kuota sementara). Tunggu beberapa detik lalu coba lagi, atau pakai chip cepat / WhatsApp.",
      escalate_wa: true,
      intent: "unknown",
      suggested_chips: [
        "orderStatus",
        "pointsGrade",
        "storeInfo",
        "labQueue",
        "stok",
        "careWarranty",
        "contactWa",
      ],
      error_code: "gemini_rate_limited",
    };
  }
  return {
    reply: en
      ? "AI help is temporarily unavailable. Try a quick-action chip, or chat with the store on WhatsApp."
      : "Bantuan AI sedang tidak tersedia. Coba chip cepat, atau hubungi cabang via WhatsApp.",
    escalate_wa: true,
    intent: "unknown",
    suggested_chips: [
      "orderStatus",
      "pointsGrade",
      "storeInfo",
      "labQueue",
      "stok",
      "careWarranty",
      "contactWa",
    ],
    error_code: "gemini_unavailable",
  };
}

function extractJsonObject(text: string): Record<string, unknown> | null {
  const trimmed = text.trim();
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object") {
      return parsed as Record<string, unknown>;
    }
  } catch (_) {
    /* fall through */
  }
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(trimmed.slice(start, end + 1)) as Record<string, unknown>;
    } catch (_) {
      return null;
    }
  }
  return null;
}

function resolveModelCandidates(): string[] {
  const preferred = (Deno.env.get("GEMINI_MODEL") || "").trim();
  const out: string[] = [];
  if (preferred) out.push(preferred);
  for (const m of DEFAULT_GEMINI_MODELS) {
    if (!out.includes(m)) out.push(m);
  }
  return out;
}

/** Pull visible text from Gemini candidates; skip thought parts. */
function extractCandidateText(data: Record<string, unknown>): string | null {
  const candidates = data?.candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const content = (candidates[0] as Record<string, unknown>)?.content as
    | Record<string, unknown>
    | undefined;
  const parts = content?.parts;
  if (!Array.isArray(parts)) return null;
  const texts: string[] = [];
  for (const raw of parts) {
    const p = raw as Record<string, unknown>;
    if (p?.thought === true) continue;
    if (typeof p?.text === "string" && p.text.trim()) texts.push(p.text);
  }
  if (texts.length === 0) return null;
  return texts.join("\n").trim();
}

async function loadGrounding(db: ReturnType<typeof createClient>, opts: {
  memberId: string | null;
  phone: string | null;
  tokoId: string | null;
}) {
  const parts: string[] = [];

  if (opts.memberId) {
    try {
      const { data: member } = await db
        .from("members")
        .select("id, nama, phone_e164, phone_raw")
        .eq("id", opts.memberId)
        .maybeSingle();
      if (member) {
        parts.push(
          `Member: id=${member.id}; nama=${member.nama ?? "-"}; phone=${
            member.phone_e164 ?? member.phone_raw ?? "-"
          }`,
        );
      }
    } catch (_) {
      /* optional */
    }

    try {
      const { data: pts } = await db.rpc("get_member_points_summary", {
        p_member_id: opts.memberId,
      });
      if (pts && typeof pts === "object") {
        const m = pts as Record<string, unknown>;
        parts.push(
          `Poin: reward=${m.reward_points ?? 0}; status=${m.status_points ?? 0}`,
        );
      }
    } catch (_) {
      /* optional */
    }
  }

  const phone = (opts.phone ?? "").replace(/\D/g, "");
  if (phone) {
    try {
      const { data: sales } = await db.rpc("list_member_sales", {
        p_phone: phone,
      });
      if (Array.isArray(sales) && sales.length > 0) {
        const lines = sales.slice(0, 5).map((raw: Record<string, unknown>) => {
          const inv = raw.no_invoice ?? "-";
          const toko = raw.toko_id ?? "-";
          const track = raw.tracking_status ?? "-";
          const pay = raw.status_pembayaran ?? "-";
          return `- ${inv} | ${toko} | tracking=${track} | bayar=${pay}`;
        });
        parts.push("Pesanan terbaru:\n" + lines.join("\n"));
      } else {
        parts.push("Pesanan terbaru: (kosong / tidak ditemukan untuk nomor ini)");
      }
    } catch (_) {
      parts.push("Pesanan terbaru: (gagal dimuat)");
    }
  }

  // Store directory for grounding: name/address only — NEVER phones.
  // WA numbers are opened by the client (nearest GPS / stated location).
  const toko = (opts.tokoId ?? "").trim().toUpperCase();
  try {
    let q = db
      .from("invoice_settings")
      .select("toko_id, shop_name, address")
      .order("toko_id")
      .limit(8);
    if (toko) q = q.eq("toko_id", toko);
    const { data: stores } = await q;
    if (Array.isArray(stores) && stores.length > 0) {
      const lines = stores.map((s: Record<string, unknown>) =>
        `- ${s.toko_id}: ${s.shop_name ?? fallbackBrand.displayName} | ${
          s.address ?? "-"
        }`
      );
      parts.push("Cabang (nama/alamat saja, tanpa nomor telepon):\n" +
        lines.join("\n"));
    }
  } catch (_) {
    /* optional */
  }

  // Lab/production queue aggregates only (no invoice PII).
  if (toko) {
    try {
      const { data: q } = await db.rpc("get_toko_lab_queue_counts", {
        p_toko_id: toko,
      });
      if (q && typeof q === "object") {
        const m = q as Record<string, unknown>;
        parts.push(
          `Beban lab/pengerjaan cabang ${m.toko_id ?? toko} (agregat, bukan lobby): ` +
            `menunggu=${m.waiting ?? 0}; sedang_dikerjakan=${m.in_progress ?? 0}; siap_diambil=${m.ready ?? 0}`,
        );
      }
    } catch (_) {
      /* optional */
    }

    // System stock category summary only (no modal price / PII).
    try {
      const { data: st } = await db.rpc("search_member_toko_stock", {
        p_toko_id: toko,
        p_q: null,
        p_limit: 8,
      });
      if (st && typeof st === "object") {
        const m = st as Record<string, unknown>;
        const cats = Array.isArray(m.by_kategori)
          ? (m.by_kategori as Array<Record<string, unknown>>)
            .slice(0, 6)
            .map((c) =>
              `${c.kategori}:${c.skus_in_stock ?? 0}sku/~${c.total_available ?? 0}qty`
            )
            .join("; ")
          : "";
        parts.push(
          `Stok sistem cabang ${m.toko_id ?? toko} (available=stock−reserved, bukan rak fisik): ` +
            `skus_tersedia=${m.skus_in_stock ?? 0}` +
            (cats ? `; by_kategori=${cats}` : ""),
        );
      }
    } catch (_) {
      /* optional */
    }
  }

  return parts.join("\n\n");
}

type GeminiOnceResult =
  | { ok: true; data: Record<string, unknown> }
  | {
    ok: false;
    status: number;
    retryable: boolean;
    rateLimited: boolean;
    invalidArg: boolean;
  };

async function callGeminiOnce(opts: {
  apiKey: string;
  model: string;
  message: string;
  locale: string;
  grounding: string;
  brand: string;
  assistantName: string;
  /** When true, ask model to skip thinking tokens (2.5 Flash / Lite). */
  disableThinking: boolean;
}): Promise<GeminiOnceResult> {
  const preferId = !opts.locale.toLowerCase().startsWith("en");
  const system = `
You are ${opts.assistantName} (${opts.brand} Asisten), the ${opts.brand} Member help assistant.
Rules:
1) Answer ONLY from CONTEXT + FAQ below. Never invent live lobby foot traffic, physical shelf confirmation, negotiation, or physical complaint status. Lobby people-count is not in the app — escalate those to WhatsApp.
2) Lab/production queue: if CONTEXT includes "Beban lab/pengerjaan", you MAY quote those aggregate counts honestly as invoice/lab pipeline load (waiting / in progress / ready). Never invent lobby wait minutes.
3) System stock: if CONTEXT includes "Stok sistem cabang", you MAY quote those category aggregates as app/system availability (stock − reserved). Never claim physical shelf audit.
4) NORMAL stock / ready / availability questions (e.g. "cek stok", "frame yang ready apa", "ada frame") answered from CONTEXT system stock → escalate_wa=false. Do NOT append a WhatsApp CTA. A short note that figures are system stock (not a shelf audit) is enough — never force WA on a successful stock answer.
5) escalate_wa=true ONLY when: user explicitly asks physical shelf ("di rak sekarang", "stok rak", audit fisik), OR nego / physical complaint / lobby people-count / today's hours changed, OR stock cannot be answered from CONTEXT (no data / too ambiguous). Being "careful" about system-vs-shelf is NOT a reason to escalate.
6) Never invent order statuses not present in CONTEXT.
7) CONTACT / WHATSAPP REQUESTS: if the user asks for a WA number, store phone, "bagi nomor wa", hubungi cabang, chat toko, etc. → set escalate_wa=true, intent=contactWa, and a VERY SHORT reply (e.g. "Menghubungkan ke WhatsApp…"). The mobile client owns UX (named branch chips, GPS nearest, or ask location) — do NOT describe both GPS and ask-location paths, and do NOT paste/list/invent phone numbers.
8) Never include phone numbers, WhatsApp numbers, or wa.me links in reply text. CONTEXT has no phones for a reason — client opens WA separately.
9) Prefer Bahasa Indonesia${preferId ? " (required)" : ""}; honor locale=${opts.locale}.
10) Keep replies concise (max ~120 words).
11) Return ONLY strict JSON: {"reply":string,"escalate_wa":boolean,"intent":string,"suggested_chips":string[]}
   intent one of: orderStatus,pointsGrade,storeInfo,labQueue,stok,careWarranty,contactWa,faqGeneral,escalateLive,unknown
   suggested_chips subset of: orderStatus,pointsGrade,storeInfo,labQueue,stok,careWarranty,contactWa

FAQ:
${faqFor(opts.brand)}

CONTEXT:
${opts.grounding || "(no member context)"}
`.trim();

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${opts.model}:generateContent?key=${
      encodeURIComponent(opts.apiKey)
    }`;

  const generationConfig: Record<string, unknown> = {
    temperature: 0.2,
    // Thinking models count reasoning toward this budget; keep headroom.
    maxOutputTokens: 2048,
    responseMimeType: "application/json",
  };
  if (opts.disableThinking) {
    generationConfig.thinkingConfig = { thinkingBudget: 0 };
  }

  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [{ text: `${system}\n\nUSER MESSAGE:\n${opts.message}` }],
          },
        ],
        generationConfig,
      }),
    });
  } catch (e) {
    console.error("gemini fetch failed", opts.model, e);
    return {
      ok: false,
      status: 0,
      retryable: true,
      rateLimited: false,
      invalidArg: false,
    };
  }

  if (!res.ok) {
    const errText = await res.text();
    console.error("gemini error", opts.model, res.status, errText.slice(0, 500));
    const rateLimited = res.status === 429;
    const invalidArg = res.status === 400;
    // 404 = unknown/retired model → try next candidate
    // 429 = quota/RPM → retryable (backoff + next model)
    // 5xx = transient
    const retryable = res.status === 404 || rateLimited || res.status >= 500 ||
      invalidArg;
    return {
      ok: false,
      status: res.status,
      retryable,
      rateLimited,
      invalidArg,
    };
  }

  const data = await res.json() as Record<string, unknown>;
  const finishReason = (data?.candidates as Array<Record<string, unknown>> | undefined)
    ?.[0]?.finishReason;
  const text = extractCandidateText(data);
  if (!text) {
    console.error(
      "gemini empty candidates",
      opts.model,
      "finishReason=",
      finishReason,
      "promptFeedback=",
      JSON.stringify(data?.promptFeedback ?? null).slice(0, 200),
    );
    return {
      ok: false,
      status: res.status,
      retryable: true,
      rateLimited: false,
      invalidArg: false,
    };
  }
  const parsed = extractJsonObject(text);
  if (!parsed || typeof parsed.reply !== "string" || !String(parsed.reply).trim()) {
    console.error("gemini parse failed", opts.model, text.slice(0, 200));
    return {
      ok: false,
      status: res.status,
      retryable: true,
      rateLimited: false,
      invalidArg: false,
    };
  }
  return { ok: true, data: parsed };
}

async function callGemini(opts: {
  apiKey: string;
  message: string;
  locale: string;
  grounding: string;
  brand: string;
  assistantName: string;
}): Promise<
  | { ok: true; data: Record<string, unknown> }
  | { ok: false; reason: "rate_limit" | "unavailable" }
> {
  const models = resolveModelCandidates();
  let sawRateLimit = false;
  let hardAuthFail = false;

  for (const model of models) {
    let disableThinking = true;
    let result = await callGeminiOnce({ ...opts, model, disableThinking });

    // Some models reject thinkingConfig → retry without it.
    if (!result.ok && result.invalidArg && disableThinking) {
      disableThinking = false;
      result = await callGeminiOnce({ ...opts, model, disableThinking });
    }

    // Free-tier RPM: brief backoff then one retry on same model.
    if (!result.ok && result.rateLimited) {
      sawRateLimit = true;
      await sleep(1500);
      result = await callGeminiOnce({ ...opts, model, disableThinking });
      if (!result.ok && result.rateLimited) sawRateLimit = true;
    }

    if (result.ok) {
      console.log("gemini ok", model);
      return { ok: true, data: result.data };
    }

    if (result.rateLimited) sawRateLimit = true;

    // 401/403 = bad key / billing block — stop burning models
    if (!result.retryable || result.status === 401 || result.status === 403) {
      hardAuthFail = true;
      console.error("gemini hard fail", model, result.status);
      break;
    }
  }

  if (hardAuthFail) return { ok: false, reason: "unavailable" };
  if (sawRateLimit) return { ok: false, reason: "rate_limit" };
  return { ok: false, reason: "unavailable" };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "POST only" }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const message = String(body.message ?? "").trim();
    const locale = String(body.locale ?? "id").trim() || "id";
    const memberId = body.member_id ? String(body.member_id) : null;
    const phone = body.phone ? String(body.phone) : null;
    const tokoId = body.toko_id ? String(body.toko_id) : null;

    if (!message) {
      return jsonResponse({ error: "message required" }, 400);
    }
    if (message.length > MAX_MESSAGE) {
      return jsonResponse({
        reply: locale.startsWith("en")
          ? `Message too long (max ${MAX_MESSAGE}).`
          : `Pesan terlalu panjang (maks ${MAX_MESSAGE}).`,
        escalate_wa: false,
        intent: "unknown",
      }, 400);
    }

    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown";
    if (!checkRate(rateLimitKey(memberId, phone, ip))) {
      return jsonResponse({
        reply: locale.startsWith("en")
          ? "Too many questions. Please wait a minute, or contact WhatsApp."
          : "Terlalu banyak pertanyaan. Tunggu sebentar, atau hubungi WhatsApp.",
        escalate_wa: true,
        intent: "escalateLive",
        suggested_chips: ["contactWa"],
        error_code: "client_rate_limited",
      }, 429);
    }

    if (needsLive(message)) {
      return jsonResponse(keywordFallback(message, locale, "live"));
    }

    // WA / contact free-text → escalate only; never let Gemini list all phones.
    if (wantsWhatsAppContact(message)) {
      return jsonResponse(waContactFallback(locale));
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    // Lab/production queue → deterministic aggregates (skip Gemini).
    if (needsLabQueue(message) && !looksLikeOwnOrder(message)) {
      if (supabaseUrl && serviceKey) {
        const db = createClient(supabaseUrl, serviceKey);
        return jsonResponse(
          await answerLabQueue(db, { locale, tokoId, message }),
        );
      }
      return jsonResponse({
        reply: locale.toLowerCase().startsWith("en")
          ? "Lab/work queue data is temporarily unavailable. Try the lab-queue chip later, or WhatsApp the branch."
          : "Data antrean lab/pengerjaan sementara tidak tersedia. Coba chip antrean lab nanti, atau WhatsApp cabang.",
        escalate_wa: true,
        intent: "labQueue",
        suggested_chips: ["labQueue", "contactWa"],
        error_code: null,
      });
    }

    // System stock → deterministic catalog/branch qty (skip Gemini).
    if (needsStok(message) && !looksLikeOwnOrder(message)) {
      if (supabaseUrl && serviceKey) {
        const db = createClient(supabaseUrl, serviceKey);
        return jsonResponse(
          await answerStok(db, { locale, tokoId, message }),
        );
      }
      return jsonResponse({
        reply: locale.toLowerCase().startsWith("en")
          ? "System stock data is temporarily unavailable. Try the stock chip later, or WhatsApp the branch."
          : "Data stok sistem sementara tidak tersedia. Coba chip stok nanti, atau WhatsApp cabang.",
        escalate_wa: true,
        intent: "stok",
        suggested_chips: ["stok", "contactWa"],
        error_code: null,
      });
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return jsonResponse(keywordFallback(message, locale, "unconfigured"));
    }

    let grounding = "";
    let brand = fallbackBrand;
    if (supabaseUrl && serviceKey) {
      const db = createClient(supabaseUrl, serviceKey);
      brand = await loadBrand(db);
      grounding = await loadGrounding(db, { memberId, phone, tokoId });
    }

    const ai = await callGemini({
      apiKey: geminiKey,
      message,
      locale,
      grounding,
      brand: brand.displayName,
      assistantName: brand.assistantName,
    });

    if (!ai.ok) {
      return jsonResponse(keywordFallback(message, locale, ai.reason));
    }

    const data = ai.data;
    if (typeof data.reply !== "string" || !String(data.reply).trim()) {
      return jsonResponse(keywordFallback(message, locale, "unavailable"));
    }

    const reply = String(data.reply).trim();
    let intent = typeof data.intent === "string" ? data.intent : "faqGeneral";
    let escalate = data.escalate_wa === true;
    // Safety net: successful system-stock answers must not force WA CTA.
    const stockGrounded = grounding.includes("Stok sistem cabang");
    const looksStockAnswer =
      intent === "stok" ||
      needsStok(message) ||
      /\b(stok sistem|system stock|sku tersedia|available qty|stock − reserved|stock - reserved)\b/i
        .test(reply);
    if (
      escalate &&
      !needsLive(message) &&
      !wantsWhatsAppContact(message) &&
      stockGrounded &&
      looksStockAnswer
    ) {
      escalate = false;
      if (intent === "faqGeneral" || intent === "unknown") intent = "stok";
    }

    return jsonResponse({
      reply,
      escalate_wa: escalate,
      intent,
      suggested_chips: Array.isArray(data.suggested_chips)
        ? data.suggested_chips.map(String)
        : [],
    });
  } catch (e) {
    console.error("member-help-bot", e);
    return jsonResponse({
      reply:
        "Maaf, bantuan AI sedang bermasalah. Silakan coba chip cepat atau WhatsApp cabang.",
      escalate_wa: true,
      intent: "unknown",
      suggested_chips: ["contactWa"],
      error_code: "gemini_unavailable",
    }, 500);
  }
});
