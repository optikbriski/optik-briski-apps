// @ts-ignore
declare const Deno: any;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PLAN_IDR: Record<string, number> = {
  paket_c: 250000,
  paket_b: 450000,
  paket_a: 750000,
};

const ADDON_IDR: Record<string, number> = {
  pos: 50000,
  master_data: 50000,
  member_app: 75000,
  history_dp: 40000,
  logistics: 60000,
  warranty: 50000,
  attendance: 60000,
  finance: 80000,
  online_orders: 80000,
};

const INCLUDED: Record<string, Record<string, string[]>> = {
  optik: {
    paket_c: ["pos", "master_data", "member_app"],
    paket_b: ["pos", "master_data", "member_app", "logistics", "warranty", "attendance", "history_dp"],
    paket_a: ["pos", "master_data", "member_app", "logistics", "warranty", "attendance", "history_dp", "finance", "online_orders"],
  },
  retail: {
    paket_c: ["pos", "master_data", "member_app"],
    paket_b: ["pos", "master_data", "member_app", "logistics", "history_dp", "attendance"],
    paket_a: ["pos", "master_data", "member_app", "logistics", "history_dp", "attendance", "finance", "online_orders"],
  },
  fnb: {
    paket_c: ["pos", "master_data", "member_app"],
    paket_b: ["pos", "master_data", "member_app", "attendance", "history_dp", "logistics"],
    paket_a: ["pos", "master_data", "member_app", "attendance", "history_dp", "logistics", "finance", "online_orders"],
  },
  jasa: {
    paket_c: ["pos", "master_data", "member_app"],
    paket_b: ["pos", "master_data", "member_app", "history_dp", "attendance"],
    paket_a: ["pos", "master_data", "member_app", "history_dp", "attendance", "finance"],
  },
  bengkel: {
    paket_c: ["pos", "master_data", "history_dp"],
    paket_b: ["pos", "master_data", "history_dp", "warranty", "attendance", "logistics"],
    paket_a: ["pos", "master_data", "history_dp", "warranty", "attendance", "logistics", "member_app", "finance"],
  },
  klinik: {
    paket_c: ["pos", "master_data", "member_app"],
    paket_b: ["pos", "master_data", "member_app", "history_dp", "attendance"],
    paket_a: ["pos", "master_data", "member_app", "history_dp", "attendance", "finance"],
  },
  grosir: {
    paket_c: ["pos", "master_data", "logistics"],
    paket_b: ["pos", "master_data", "logistics", "history_dp", "attendance", "finance"],
    paket_a: ["pos", "master_data", "logistics", "history_dp", "attendance", "finance", "member_app", "online_orders"],
  },
  umum: {
    paket_c: ["pos", "master_data"],
    paket_b: ["pos", "master_data", "member_app", "attendance", "history_dp"],
    paket_a: ["pos", "master_data", "member_app", "attendance", "history_dp", "finance", "logistics", "online_orders"],
  },
};

const WL_IDR = 200000;

function quote(body: Record<string, unknown>) {
  const plan = String(body.plan_key || "paket_c");
  const industry = String(body.industry_key || "umum");
  const base = PLAN_IDR[plan];
  if (!base) throw new Error("Paket tidak dikenal");
  const included =
    (INCLUDED[industry] && INCLUDED[industry][plan]) ||
    (INCLUDED.umum[plan] ?? []);
  const mods = (body.modules || {}) as Record<string, unknown>;
  let add = 0;
  for (const [key, on] of Object.entries(mods)) {
    if (!on) continue;
    if (included.includes(key)) continue;
    add += ADDON_IDR[key] ?? 50000;
  }
  const wantWl = body.white_label === true;
  const wl = wantWl && plan !== "paket_a" ? WL_IDR : 0;
  return {
    plan,
    industry,
    baseIdr: base,
    addOnIdr: add,
    whiteLabelIdr: wl,
    amountIdr: base + add + wl,
    whiteLabel: wantWl || plan === "paket_a",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: false, error: "POST only" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const q = quote(body);
    const name = String(body.display_name || "UMKM").slice(0, 40);
    const phone = String(body.phone || "").slice(0, 20);
    const email = String(body.email || "").slice(0, 80);
    const orderId = `RKS-${Date.now()}-${
      crypto.randomUUID().replace(/-/g, "").slice(0, 8)
    }`;
    const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY") ?? "";
    const isProd =
      (Deno.env.get("MIDTRANS_IS_PRODUCTION") ?? "false").toLowerCase() ===
        "true";
    const clientKey = Deno.env.get("MIDTRANS_CLIENT_KEY") ?? "";
    const finish =
      "https://rekasa-karya-indonesia.vercel.app/perusahaan/?bayar=selesai";

    if (!serverKey.trim()) {
      return new Response(
        JSON.stringify({
          ok: true,
          mock_payment: true,
          amount_idr: q.amountIdr,
          order_id: orderId,
          message:
            "MIDTRANS_SERVER_KEY belum di-set. Pesanan lisensi belum dipungut otomatis.",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const basic = btoa(`${serverKey}:`);
    const snapHost = isProd
      ? "https://app.midtrans.com"
      : "https://app.sandbox.midtrans.com";
    const snapRes = await fetch(`${snapHost}/snap/v1/transactions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `Basic ${basic}`,
      },
      body: JSON.stringify({
        transaction_details: {
          order_id: orderId,
          gross_amount: q.amountIdr,
        },
        customer_details: {
          first_name: name,
          phone,
          email,
        },
        item_details: [
          {
            id: q.plan,
            price: q.amountIdr,
            quantity: 1,
            name: `Lisensi Rekasa ${q.plan} ${q.industry}`.slice(0, 50),
          },
        ],
        callbacks: { finish },
        enabled_payments: [
          "credit_card",
          "bca_va",
          "bni_va",
          "bri_va",
          "permata_va",
          "other_va",
          "gopay",
          "shopeepay",
          "qris",
          "bank_transfer",
        ],
      }),
    });
    const snapJson = await snapRes.json();
    if (!snapRes.ok || !snapJson?.token) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "Gagal membuat transaksi Midtrans lisensi",
          detail: snapJson,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        mock_payment: false,
        amount_idr: q.amountIdr,
        order_id: orderId,
        snap_token: snapJson.token,
        redirect_url: snapJson.redirect_url ?? "",
        client_key: clientKey,
        is_production: isProd,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: String(e?.message || e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
