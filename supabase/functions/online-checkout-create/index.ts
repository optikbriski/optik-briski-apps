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
    const body = await req.json();
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const db = createClient(supabaseUrl, serviceKey);

    const {
      phone,
      member_id,
      customer_name,
      toko_id,
      fulfillment,
      courier,
      address_text,
      address_lat,
      address_lng,
      items,
    } = body;

    const { data: created, error: createErr } = await db.rpc(
      "create_online_order",
      {
        p_phone: phone,
        p_member_id: member_id ?? null,
        p_customer_name: customer_name ?? null,
        p_toko_id: toko_id,
        p_fulfillment: fulfillment,
        p_courier: courier ?? null,
        p_address_text: address_text ?? null,
        p_address_lat: address_lat ?? null,
        p_address_lng: address_lng ?? null,
        p_items: items ?? [],
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

    const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY") ?? "";
    const isProd =
      (Deno.env.get("MIDTRANS_IS_PRODUCTION") ?? "false").toLowerCase() ===
      "true";
    const clientKey = Deno.env.get("MIDTRANS_CLIENT_KEY") ?? "";
    const midtransOrderId = String(order.midtrans_order_id);
    const gross = Number(order.total) || 0;

    // Tanpa Midtrans key: mode dev — kembalikan order + flag mock bayar
    if (!serverKey.trim()) {
      const redirect =
        `${supabaseUrl}/functions/v1/online-midtrans-webhook?dev_pay=${encodeURIComponent(midtransOrderId)}`;
      await db.rpc("attach_online_order_snap", {
        p_online_order_id: order.online_order_id,
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
            "MIDTRANS_SERVER_KEY belum di-set. Gunakan tombol Bayar uji (dev) di app.",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const auth = btoa(`${serverKey}:`);
    const snapHost = isProd
      ? "https://app.midtrans.com"
      : "https://app.sandbox.midtrans.com";

    const snapRes = await fetch(`${snapHost}/snap/v1/transactions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `Basic ${auth}`,
      },
      body: JSON.stringify({
        transaction_details: {
          order_id: midtransOrderId,
          gross_amount: gross,
        },
        customer_details: {
          first_name: customer_name || "Member",
          phone: phone,
        },
        item_details: [
          ...((order.items as Array<Record<string, unknown>>) || []).map((it) => ({
            id: String(it.sku ?? "item"),
            price: Number(it.harga) || 0,
            quantity: Number(it.qty) || 1,
            name: String(it.nama ?? it.sku ?? "Item").slice(0, 50),
          })),
          ...(Number(order.shipping_fee) > 0
            ? [{
              id: "SHIPPING",
              price: Number(order.shipping_fee),
              quantity: 1,
              name: `Ongkir ${courier || ""}`.slice(0, 50),
            }]
            : []),
        ],
        callbacks: {
          finish: Deno.env.get("MIDTRANS_FINISH_URL") ??
            "https://optikbriski.com/member-pay-done",
        },
      }),
    });

    const snapJson = await snapRes.json();
    if (!snapRes.ok) {
      console.error("Midtrans error", snapJson);
      throw new Error(
        snapJson?.error_messages?.join?.(", ") ||
          snapJson?.status_message ||
          "Gagal membuat transaksi Midtrans",
      );
    }

    const snapToken = snapJson.token as string;
    const redirectUrl = snapJson.redirect_url as string;

    await db.rpc("attach_online_order_snap", {
      p_online_order_id: order.online_order_id,
      p_snap_token: snapToken,
      p_redirect_url: redirectUrl,
    });

    return new Response(
      JSON.stringify({
        ok: true,
        ...order,
        snap_token: snapToken,
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
