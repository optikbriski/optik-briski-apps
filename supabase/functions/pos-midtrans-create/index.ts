// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.toLowerCase().startsWith("bearer ")) {
      return new Response(
        JSON.stringify({ ok: false, error: "Login kasir dulu" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json();
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const userDb = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: auth } },
    });
    const adminDb = createClient(supabaseUrl, serviceKey);

    const amount = Math.round(Number(body.amount_idr) || 0);
    const purpose = String(body.purpose ?? "sale");
    const { data: created, error: createErr } = await userDb.rpc(
      "create_pos_payment",
      {
        p_amount_idr: amount,
        p_purpose: purpose,
        p_toko_id: body.toko_id ?? null,
        p_sale_id: body.sale_id ?? null,
        p_invoice_no: body.invoice_no ?? null,
        p_customer_name: body.customer_name ?? null,
        p_phone: body.phone ?? null,
      },
    );
    if (createErr) throw createErr;
    const order = created as Record<string, unknown>;
    if (!order?.ok) {
      return new Response(JSON.stringify(order), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const midtransOrderId = String(order.midtrans_order_id);
    const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY") ?? "";
    const isProd =
      (Deno.env.get("MIDTRANS_IS_PRODUCTION") ?? "false").toLowerCase() ===
        "true";
    const clientKey = Deno.env.get("MIDTRANS_CLIENT_KEY") ?? "";

    if (!serverKey.trim()) {
      const redirect =
        `${supabaseUrl}/functions/v1/online-midtrans-webhook?dev_pay=${
          encodeURIComponent(midtransOrderId)
        }`;
      await adminDb.rpc("attach_pos_payment_snap", {
        p_midtrans_order_id: midtransOrderId,
        p_snap_token: "DEV_NO_MIDTRANS",
        p_redirect_url: redirect,
      });
      return new Response(
        JSON.stringify({
          ok: true,
          ...order,
          snap_token: "DEV_NO_MIDTRANS",
          redirect_url: null,
          client_key: null,
          is_production: false,
          mock_payment: true,
          message:
            "MIDTRANS_SERVER_KEY belum di-set. Kasir pakai Bayar uji.",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const basic = btoa(`${serverKey}:`);
    const snapHost = isProd
      ? "https://app.midtrans.com"
      : "https://app.sandbox.midtrans.com";
    const name = String(body.customer_name || "Pelanggan").slice(0, 40);
    const invoice = String(body.invoice_no || "POS").slice(0, 40);

    const snapRes = await fetch(`${snapHost}/snap/v1/transactions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `Basic ${basic}`,
      },
      body: JSON.stringify({
        transaction_details: {
          order_id: midtransOrderId,
          gross_amount: amount,
        },
        customer_details: {
          first_name: name,
          phone: String(body.phone || ""),
        },
        item_details: [
          {
            id: purpose === "pelunasan" ? "POS-PELUNASAN" : "POS-SALE",
            price: amount,
            quantity: 1,
            name: `${purpose === "pelunasan" ? "Pelunasan" : "Kasir"} ${invoice}`
              .slice(0, 50),
          },
        ],
      }),
    });
    const snapJson = await snapRes.json();
    if (!snapRes.ok || !snapJson?.token) {
      console.error("Midtrans POS error", snapJson);
      return new Response(
        JSON.stringify({
          ok: false,
          error: "Gagal membuat transaksi Midtrans kasir",
          detail: snapJson,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const redirectUrl = String(snapJson.redirect_url ?? "");
    await adminDb.rpc("attach_pos_payment_snap", {
      p_midtrans_order_id: midtransOrderId,
      p_snap_token: String(snapJson.token),
      p_redirect_url: redirectUrl,
    });

    return new Response(
      JSON.stringify({
        ok: true,
        ...order,
        snap_token: snapJson.token,
        redirect_url: redirectUrl,
        client_key: clientKey,
        is_production: isProd,
        mock_payment: false,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error(e);
    return new Response(
      JSON.stringify({ ok: false, error: String(e?.message || e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
