// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

async function sha512Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-512", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db = createClient(supabaseUrl, serviceKey);
  const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY") ?? "";

  try {
    // Dev shortcut: GET ?dev_pay=ORDER_ID (hanya jika tidak ada Midtrans key)
    if (req.method === "GET") {
      const url = new URL(req.url);
      const devPay = url.searchParams.get("dev_pay");
      if (devPay && !serverKey.trim()) {
        const { data, error } = await db.rpc("fulfill_online_order_payment", {
          p_midtrans_order_id: devPay,
          p_payment_method: "DEV_MOCK",
          p_gross_amount: null,
        });
        if (error) throw error;
        return new Response(JSON.stringify(data), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true, service: "online-midtrans-webhook" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = await req.json();
    const orderId = String(payload.order_id ?? "");
    const statusCode = String(payload.status_code ?? "");
    const grossAmount = String(payload.gross_amount ?? "");
    const signature = String(payload.signature_key ?? "");
    const transactionStatus = String(payload.transaction_status ?? "");
    const fraudStatus = String(payload.fraud_status ?? "");
    const paymentType = String(payload.payment_type ?? "Midtrans");

    if (!orderId) {
      return new Response(JSON.stringify({ ok: false, error: "order_id missing" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (serverKey.trim()) {
      const expected = await sha512Hex(
        `${orderId}${statusCode}${grossAmount}${serverKey}`,
      );
      if (signature && signature !== expected) {
        console.error("Invalid Midtrans signature");
        return new Response(JSON.stringify({ ok: false, error: "invalid signature" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const paid =
      transactionStatus === "capture" && fraudStatus === "accept" ||
      transactionStatus === "settlement";

    if (transactionStatus === "expire" || transactionStatus === "cancel") {
      await db
        .from("online_orders")
        .update({
          status: transactionStatus === "expire" ? "expired" : "cancelled",
          updated_at: new Date().toISOString(),
        })
        .eq("midtrans_order_id", orderId)
        .eq("status", "pending_payment");
      return new Response(JSON.stringify({ ok: true, skipped: transactionStatus }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!paid) {
      return new Response(JSON.stringify({ ok: true, skipped: transactionStatus }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const gross = Math.round(parseFloat(grossAmount) || 0);
    const { data, error } = await db.rpc("fulfill_online_order_payment", {
      p_midtrans_order_id: orderId,
      p_payment_method: paymentType || "Midtrans",
      p_gross_amount: gross > 0 ? gross : null,
    });
    if (error) throw error;

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
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
