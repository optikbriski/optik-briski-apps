// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { loadBrand } from "../_shared/brand.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function sendEmail(
  to: string,
  otp: string,
  nama: string | undefined,
  brand: string,
) {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return { ok: false, detail: "RESEND_API_KEY belum di-set" };
  const from = Deno.env.get("RESEND_FROM") ||
    `${brand} <onboarding@resend.dev>`;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: `Kode OTP ${brand}`,
      html: `<div style="font-family:Arial,sans-serif;padding:24px;max-width:480px">
        <h2 style="color:#0B3D8C;margin:0 0 12px">${brand}</h2>
        <p style="color:#334155;margin:0 0 8px">Halo${nama ? ` <b>${nama}</b>` : ""},</p>
        <p style="color:#334155;margin:0 0 16px">Kode OTP email untuk daftar Member:</p>
        <p style="font-size:36px;font-weight:800;letter-spacing:8px;color:#1565C0;margin:0 0 16px">${otp}</p>
        <p style="color:#64748b;font-size:13px;margin:0">Berlaku 15 menit. Jangan bagikan kode ini.</p>
      </div>`,
    }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { ok: false, detail: JSON.stringify(json) };
  }
  return { ok: true, detail: "sent" };
}

async function sendWa(phone: string, otp: string, brand: string) {
  const msg =
    `*${brand}*\nKode OTP WhatsApp daftar Member: *${otp}*\nBerlaku 15 menit.`;
  const fonnte = Deno.env.get("FONNTE_TOKEN");
  if (fonnte) {
    const form = new FormData();
    form.append("target", phone);
    form.append("message", msg);
    const res = await fetch("https://api.fonnte.com/send", {
      method: "POST",
      headers: { Authorization: fonnte },
      body: form,
    });
    const text = await res.text();
    return res.ok ? { ok: true, detail: text } : { ok: false, detail: text };
  }
  const url = Deno.env.get("WA_GATEWAY_URL");
  if (url) {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(Deno.env.get("WA_GATEWAY_TOKEN")
          ? { Authorization: `Bearer ${Deno.env.get("WA_GATEWAY_TOKEN")}` }
          : {}),
      },
      body: JSON.stringify({ phone, message: msg }),
    });
    const text = await res.text();
    return res.ok ? { ok: true, detail: text } : { ok: false, detail: text };
  }
  return { ok: false, detail: "FONNTE_TOKEN / WA_GATEWAY_URL belum di-set" };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const body = await req.json();
    const channel = String(body.channel || "").toLowerCase(); // wa | email
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const brand = (await loadBrand(db, body.tenant_id)).displayName;

    // Pastikan draft tersimpan
    const draft = await db.rpc("member_save_register_draft", {
      p_phone: body.phone,
      p_password: body.password,
      p_nama: body.nama ?? null,
      p_email: body.email ?? null,
      p_tanggal_lahir: body.tanggal_lahir ?? null,
    });
    if (draft.error) throw draft.error;
    if (!(draft.data as any)?.ok) {
      return new Response(JSON.stringify(draft.data), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const issued = await db.rpc("member_issue_register_otp", {
      p_phone: body.phone,
      p_channel: channel,
    });
    if (issued.error) throw issued.error;
    const result = issued.data as Record<string, unknown>;
    if (!result?.ok) {
      return new Response(JSON.stringify(result), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const otp = String(result.otp);
    let sent = { ok: false, detail: "" };
    if (channel === "wa") {
      sent = await sendWa(String(result.phone_e164), otp, brand);
    } else if (channel === "email") {
      sent = await sendEmail(
        String(result.email),
        otp,
        body.nama ? String(body.nama) : undefined,
        brand,
      );
    } else {
      return new Response(
        JSON.stringify({ ok: false, error: "channel harus wa atau email" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        channel,
        sent: sent.ok,
        send_detail: sent.detail,
        debug_otp: sent.ok ? null : otp,
        message: sent.ok
          ? `OTP dikirim ke ${channel === "wa" ? "WhatsApp" : "email"}`
          : "Gateway belum siap — pakai kode debug sementara",
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
