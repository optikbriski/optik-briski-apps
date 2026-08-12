// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

/**
 * Buat order Biteship saat barang jadi / admin tekan Kirim.
 * Secret: BITESHIP_API_KEY
 *
 * Body: { online_order_id: uuid }
 *
 * Flow:
 * 1) Load online_orders + koordinat toko
 * 2) Rates ulang (harga Instant bisa berubah)
 * 3) POST /v1/orders dengan courier_company + courier_type
 * 4) Simpan biteship_order_id / waybill + status shipped
 */
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed" }, 405);
  }

  try {
    const apiKey = (Deno.env.get("BITESHIP_API_KEY") ?? "").trim();
    if (!apiKey) {
      return json({
        ok: false,
        error: "BITESHIP_API_KEY belum di-set di Supabase Secrets",
      }, 500);
    }

    const body = await req.json();
    const orderId = String(body.online_order_id ?? "").trim();
    if (!orderId) {
      return json({ ok: false, error: "online_order_id wajib" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const db = createClient(supabaseUrl, serviceKey);

    // Auth: pastikan caller staff cabang / pusat
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: userData } = await userClient.auth.getUser();
    const uid = userData?.user?.id;
    if (!uid) {
      return json({ ok: false, error: "Login staf wajib" }, 401);
    }

    const { data: order, error: orderErr } = await db
      .from("online_orders")
      .select("*")
      .eq("id", orderId)
      .maybeSingle();
    if (orderErr || !order) {
      return json({ ok: false, error: "Order tidak ditemukan" }, 404);
    }

    if ((order.fulfillment ?? "") !== "delivery") {
      return json({
        ok: false,
        error: "Order ini bukan pengiriman (pickup)",
      }, 400);
    }

    if (order.is_obr === true || String(order.courier ?? "").toLowerCase() === "obr") {
      return json({
        ok: false,
        error: "Order OBR diantar anak toko — jangan panggil Biteship",
      }, 400);
    }

    const st = String(order.status ?? "");
    if (!["paid", "packing", "ready"].includes(st)) {
      return json({
        ok: false,
        error:
          `Status order belum bisa dipanggil kurir (${st || "—"}). Lunasi & proses dulu.`,
      }, 400);
    }

    if (order.biteship_order_id) {
      return json({
        ok: true,
        already: true,
        biteship_order_id: order.biteship_order_id,
        waybill: order.biteship_waybill,
        courier_tracking: order.courier_tracking,
      });
    }

    const { data: profile } = await db
      .from("profiles")
      .select("role, toko_id")
      .eq("id", uid)
      .maybeSingle();
    const role = String(profile?.role ?? "").toLowerCase();
    const staffToko = String(profile?.toko_id ?? "").trim().toUpperCase();
    const orderToko = String(order.toko_id ?? "").trim().toUpperCase();
    // Hanya role pusat yang boleh panggil kurir untuk cabang lain.
    const isPusat = ["owner", "admin_pusat", "super_admin"].includes(role);
    if (!isPusat && (!staffToko || staffToko !== orderToko)) {
      return json({
        ok: false,
        error:
          `Tidak berwenang: order ${orderToko || "-"}, staf ${staffToko || "-"}`,
      }, 403);
    }

    const { data: toko } = await db
      .from("toko_id")
      .select("id, toko_id, latitude, longitude")
      .eq("id", order.toko_id)
      .maybeSingle();

    const originLat = Number(toko?.latitude);
    const originLng = Number(toko?.longitude);
    const destLat = Number(order.address_lat);
    const destLng = Number(order.address_lng);
    if (![originLat, originLng, destLat, destLng].every((n) =>
      Number.isFinite(n)
    )) {
      return json({
        ok: false,
        error:
          "Koordinat cabang / alamat member belum lengkap untuk panggil kurir",
      }, 400);
    }

    let company = String(order.courier_company ?? "").trim().toLowerCase();
    let serviceCode = String(order.courier_service_code ?? "").trim();
    if (!company || company === "obr" || !serviceCode) {
      return json({
        ok: false,
        error:
          "Meta kurir Biteship belum tersimpan di order. Member perlu checkout ulang setelah update app.",
      }, 400);
    }

    // Map service OBR category → real service jika masih tersimpan category
    const cat = String(order.shipping_category ?? "").toLowerCase();
    if (["instant", "sameday", "nextday", "regular"].includes(serviceCode)) {
      if (cat === "instant" || serviceCode === "instant") {
        serviceCode = "instant";
      } else if (cat === "sameday" || serviceCode === "sameday") {
        serviceCode = "same_day";
      }
    }

    const itemsRaw = Array.isArray(order.items) ? order.items : [];
    const items = (itemsRaw.length > 0 ? itemsRaw : [{
      nama: "Paket Optik",
      harga: Number(order.subtotal) || 100000,
      qty: 1,
    }]).map((it: Record<string, unknown>) => ({
      name: String(it.nama ?? it.name ?? "Item"),
      description: String(it.kategori ?? it.sku ?? ""),
      value: Math.max(1000, Number(it.harga ?? it.value) || 100000),
      quantity: Math.max(1, Number(it.qty ?? it.quantity) || 1),
      weight: 500,
      length: 25,
      width: 20,
      height: 12,
    }));

    const { data: storeInv } = await db
      .from("invoice_settings")
      .select("shop_name, phone, address")
      .eq("toko_id", order.toko_id)
      .maybeSingle();
    const storePhoneRaw = String(storeInv?.phone ?? "").replace(/[^\d+]/g, "");
    const storePhone = storePhoneRaw && storePhoneRaw !== "-"
      ? storePhoneRaw
      : (Deno.env.get("BITESHIP_ORIGIN_PHONE") ?? "080000000000");
    const originName = String(
      storeInv?.shop_name || toko?.toko_id || order.toko_id || "Optik B. Riski",
    );
    const originAddress = String(
      storeInv?.address || originName,
    ).trim() || originName;
    const destName = String(order.customer_name ?? "Member");
    const destPhone = String(order.phone_e164 ?? "");

    const createBody = {
      shipper_contact_name: originName,
      shipper_contact_phone: storePhone,
      shipper_organization: "Optik B. Riski",
      origin_contact_name: originName,
      origin_contact_phone: storePhone,
      origin_address: originAddress,
      origin_coordinate: {
        latitude: originLat,
        longitude: originLng,
      },
      destination_contact_name: destName,
      destination_contact_phone: destPhone || "080000000000",
      destination_address: String(order.address_text ?? ""),
      destination_coordinate: {
        latitude: destLat,
        longitude: destLng,
      },
      courier_company: company,
      courier_type: serviceCode,
      delivery_type: "now",
      order_note: `OBR online ${order.midtrans_order_id ?? orderId}`,
      reference_id: String(orderId),
      metadata: {
        online_order_id: orderId,
        is_obr: order.is_obr === true,
        shipping_category: order.shipping_category,
      },
      items,
    };

    const biteshipRes = await fetch("https://api.biteship.com/v1/orders", {
      method: "POST",
      headers: {
        Authorization: apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(createBody),
    });
    const payload = await biteshipRes.json().catch(() => ({}));
    if (!biteshipRes.ok) {
      return json({
        ok: false,
        error: payload?.error || payload?.message ||
          `Biteship HTTP ${biteshipRes.status}`,
        biteship: payload,
      }, 400);
    }

    const biteshipId = String(payload?.id ?? "");
    const waybill = String(
      payload?.courier?.waybill_id ?? payload?.courier?.tracking_id ?? "",
    );
    if (!biteshipId) {
      return json({
        ok: false,
        error: "Biteship tidak mengembalikan order id",
        biteship: payload,
      }, 400);
    }

    // Update langsung via service role (RPC attach butuh auth.uid staf).
    const { error: updErr } = await db.from("online_orders").update({
      biteship_order_id: biteshipId,
      biteship_waybill: waybill || null,
      courier_tracking: waybill || order.courier_tracking,
      status: "shipped",
      updated_at: new Date().toISOString(),
    }).eq("id", orderId).in("status", ["paid", "packing", "ready"]);
    if (updErr) {
      return json({ ok: false, error: updErr.message }, 400);
    }

    if (order.sale_id) {
      await db.from("sales").update({
        tracking_status: "DIKIRIM",
      }).eq("id", order.sale_id);
    }

    // Alert Member (best-effort) — selaras update_online_order_fulfillment.
    try {
      const { data: sale } = order.sale_id
        ? await db.from("sales").select("no_invoice").eq("id", order.sale_id)
          .maybeSingle()
        : { data: null };
      const inv = String(sale?.no_invoice ?? "");
      const phone = String(order.phone_e164 ?? "");
      if (inv && phone) {
        await db.rpc("create_member_order_alert", {
          p_no_invoice: inv,
          p_phone: phone,
          p_title: "Pesanan dalam pengiriman",
          p_body: waybill
            ? `Resi ${waybill}`
            : "Kurir sudah membawa pesanan Anda.",
          p_kind: "status",
          p_online_order_id: orderId,
        });
      }
    } catch (_) {
      /* non-fatal */
    }

    return json({
      ok: true,
      biteship_order_id: biteshipId,
      waybill: waybill || null,
      courier_tracking: waybill || null,
      price: payload?.price ?? null,
      status: payload?.status ?? "confirmed",
      biteship: payload,
    });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
