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

async function sendEmailResend(opts: {
  to: string;
  otp: string;
  nama?: string;
  brand: string;
}): Promise<{ ok: boolean; detail?: string }> {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return { ok: false, detail: "RESEND_API_KEY belum di-set" };

  const from = Deno.env.get("RESEND_FROM") ||
    `${opts.brand} <onboarding@resend.dev>`;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [opts.to],
      subject: `${opts.otp} — Kode OTP daftar Member ${opts.brand}`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#0f172a">
          <h2 style="margin:0 0 8px;color:#0B3D8C">${opts.brand}</h2>
          <p>Halo${opts.nama ? ` <b>${opts.nama}</b>` : ""},</p>
          <p>Kode OTP untuk mendaftar akun Member:</p>
          <p style="font-size:32px;font-weight:800;letter-spacing:6px;color:#1565C0;margin:16px 0">${opts.otp}</p>
          <p style="color:#64748b;font-size:13px">Berlaku 15 menit. Jangan bagikan kode ini.</p>
        </div>
      `,
    }),
  });
  const json = await res.json();
  if (!res.ok) {
    return { ok: false, detail: JSON.stringify(json) };
  }
  return { ok: true, detail: "email sent" };
}

/** Fonnte (umum di ID) — set FONNTE_TOKEN. Fallback: WA_GATEWAY_URL JSON POST. */
async function sendWhatsApp(opts: {
  phoneE164: string;
  otp: string;
  nama?: string;
  brand: string;
}): Promise<{ ok: boolean; detail?: string }> {
  const msg =
    `*${opts.brand}*\nKode OTP daftar Member: *${opts.otp}*\nBerlaku 15 menit. Jangan bagikan.`;

  const fonnte = Deno.env.get("FONNTE_TOKEN");
  if (fonnte) {
    const form = new FormData();
    form.append("target", opts.phoneE164);
    form.append("message", msg);
    const res = await fetch("https://api.fonnte.com/send", {
      method: "POST",
      headers: { Authorization: fonnte },
      body: form,
    });
    const text = await res.text();
    if (!res.ok) return { ok: false, detail: text };
    return { ok: true, detail: text };
  }

  const gatewayUrl = Deno.env.get("WA_GATEWAY_URL");
  const gatewayToken = Deno.env.get("WA_GATEWAY_TOKEN");
  if (gatewayUrl) {
    const res = await fetch(gatewayUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(gatewayToken ? { Authorization: `Bearer ${gatewayToken}` } : {}),
      },
      body: JSON.stringify({
        phone: opts.phoneE164,
        message: msg,
        nama: opts.nama,
      }),
    });
    const text = await res.text();
    if (!res.ok) return { ok: false, detail: text };
    return { ok: true, detail: text };
  }

  return {
    ok: false,
    detail: "FONNTE_TOKEN / WA_GATEWAY_URL belum di-set",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const db = createClient(supabaseUrl, serviceKey);
    if (!body.tenant_id) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "tenant_id wajib. Pakai member-send-channel-otp.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const brand = (await loadBrand(db, body.tenant_id)).displayName;

    const { data, error } = await db.rpc("member_begin_register", {
      p_phone: body.phone,
      p_password: body.password,
      p_nama: body.nama ?? null,
      p_email: body.email ?? null,
      p_tanggal_lahir: body.tanggal_lahir ?? null,
    });
    if (error) throw error;
    const result = data as Record<string, unknown>;
    if (!result?.ok) {
      return new Response(JSON.stringify(result), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const otp = String(result.otp ?? "");
    const phone = String(result.phone_e164 ?? "");
    const email = String(result.email ?? "");
    const nama = body.nama ? String(body.nama) : undefined;

    const [wa, mail] = await Promise.all([
      sendWhatsApp({ phoneE164: phone, otp, nama, brand }),
      sendEmailResend({ to: email, otp, nama, brand }),
    ]);

    return new Response(
      JSON.stringify({
        ok: true,
        phone_e164: phone,
        email,
        sent_whatsapp: wa.ok,
        sent_email: mail.ok,
        whatsapp_detail: wa.detail,
        email_detail: mail.detail,
        // Ditampilkan di app hanya jika pengiriman gagal (dev)
        debug_otp: wa.ok && mail.ok ? null : otp,
        message: wa.ok || mail.ok
          ? "OTP dikirim. Cek WhatsApp dan/atau email."
          : "Gateway WA/email belum siap — pakai kode debug sementara.",
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
