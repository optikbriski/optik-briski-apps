// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { loadBrand } from "../_shared/brand.ts";

/**
 * Proxy Rates API Biteship (cek ongkir).
 * Secret: BITESHIP_API_KEY (biteship_test... / biteship_live...)
 *
 * Body:
 * {
 *   origin_lat, origin_lng,
 *   destination_lat, destination_lng,
 *   couriers?: "grab,gojek" | string,
 *   courier?: "grab" | "gojek" | "other",  // filter opsional
 *   items?: [{ name, value, weight, quantity, length?, width?, height? }]
 * }
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

/**
 * Kurir yang di-query:
 * - Instant / Same Day difilter di client: Grab + Gojek
 * - Next Day + Reguler: ekspedisi paket
 * - Tanpa Borzo / Paxel / Lalamove / kargo berat
 */
const ALL_COURIERS = [
  "grab",
  "gojek",
  "jne",
  "tiki",
  "sicepat",
  "jnt",
  "anteraja",
  "idexpress",
  "ninja",
  "lion",
  "wahana",
  "pos",
  "sap",
  "rpx",
].join(",");

function mapCourierFilter(courier: string | undefined): string {
  const c = (courier ?? "").trim().toLowerCase();
  if (c === "grab") return "grab";
  if (c === "gojek") return "gojek";
  if (c === "other") {
    return "jne,tiki,sicepat,jnt,anteraja,idexpress,ninja,lion,wahana,pos,sap,rpx";
  }
  return ALL_COURIERS;
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
    const originLat = Number(body.origin_lat ?? body.origin_latitude);
    const originLng = Number(body.origin_lng ?? body.origin_longitude);
    const destLat = Number(body.destination_lat ?? body.destination_latitude);
    const destLng = Number(body.destination_lng ?? body.destination_longitude);

    if (
      ![originLat, originLng, destLat, destLng].every((n) =>
        Number.isFinite(n)
      )
    ) {
      return json({
        ok: false,
        error:
          "Butuh origin_lat/lng dan destination_lat/lng (koordinat cabang + alamat member)",
      }, 400);
    }

    const couriers = (body.couriers as string | undefined)?.trim() ||
      mapCourierFilter(body.courier as string | undefined);

    const brandDb = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const brand = (await loadBrand(brandDb)).displayName;

    const rawItems = Array.isArray(body.items) ? body.items : [];
    const items = (rawItems.length > 0 ? rawItems : [{
      name: "Paket Optik",
      description: `Belanja Online ${brand}`,
      value: Number(body.order_value) || 100000,
      weight: Number(body.weight) || 500,
      quantity: 1,
      length: 25,
      width: 20,
      height: 12,
    }]).map((it: Record<string, unknown>) => ({
      name: String(it.name ?? "Item"),
      description: String(it.description ?? ""),
      value: Math.max(1000, Number(it.value) || 100000),
      weight: Math.max(100, Number(it.weight) || 500),
      quantity: Math.max(1, Number(it.quantity) || 1),
      length: Math.max(1, Number(it.length) || 25),
      width: Math.max(1, Number(it.width) || 20),
      height: Math.max(1, Number(it.height) || 12),
    }));

    const biteshipRes = await fetch(
      "https://api.biteship.com/v1/rates/couriers",
      {
        method: "POST",
        headers: {
          Authorization: apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          origin_latitude: originLat,
          origin_longitude: originLng,
          destination_latitude: destLat,
          destination_longitude: destLng,
          couriers,
          items,
        }),
      },
    );

    const payload = await biteshipRes.json().catch(() => ({}));
    if (!biteshipRes.ok) {
      return json({
        ok: false,
        error: payload?.error || payload?.message ||
          `Biteship HTTP ${biteshipRes.status}`,
        biteship: payload,
      }, 400);
    }

    const pricing = Array.isArray(payload?.pricing) ? payload.pricing : [];
    const options = pricing.map((p: Record<string, unknown>) => {
      const range = String(
        p.shipment_duration_range ?? p.duration ?? "",
      ).trim();
      const unit = String(p.shipment_duration_unit ?? "").trim();
      const duration = [range, unit].filter(Boolean).join(" ");
      return {
        company: String(p.company ?? ""),
        courier_name: String(p.courier_name ?? p.company ?? ""),
        courier_code: String(p.courier_code ?? p.company ?? ""),
        courier_service_code: String(p.courier_service_code ?? ""),
        courier_service_name: String(p.courier_service_name ?? ""),
        description: String(p.description ?? ""),
        duration,
        shipment_duration_range: range,
        shipment_duration_unit: unit,
        price: Number(p.price ?? p.final_price ?? 0) || 0,
        available_collection_method: p.available_collection_method ?? [],
      };
    });

    // Prefer harga termurah untuk filter courier tunggal.
    let shippingFee = 0;
    if (options.length > 0) {
      shippingFee = options.reduce(
        (min: number, o: { price: number }) =>
          min === 0 ? o.price : Math.min(min, o.price),
        0,
      );
    }

    return json({
      ok: true,
      source: "biteship",
      shipping_fee: shippingFee,
      options,
      origin: payload?.origin ?? null,
      destination: payload?.destination ?? null,
    });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
