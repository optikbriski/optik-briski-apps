// @ts-ignore
declare const Deno: any;

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const {
      invoice,
      email,
      customerName,
      netTotal,
      pdfBase64,
      qrPayload,
      qrPhase,
      hubUrl,
      phaseTip,
      tokoId,
      headlineMessage,
      includeQr,
    } = body;

    if (!email || !String(email).includes("@")) {
      throw new Error("email pelanggan kosong / tidak valid");
    }

    const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
    if (!RESEND_API_KEY) {
      throw new Error("RESEND_API_KEY belum terpasang di Secrets Supabase!");
    }

    const from = Deno.env.get("RESEND_FROM") ||
      "Optik B. Riski <onboarding@resend.dev>";
    const phase = String(qrPhase || "").toUpperCase();
    const wantQr = includeQr !== false;
    const phaseLabel =
      phase === "DP"
        ? "DP — pelunasan"
        : phase === "LUNAS"
        ? "LUNAS — pengambilan"
        : phase === "CLAIM"
        ? "CLAIM — garansi"
        : phase === "DP_CONFIRM"
        ? "Konfirmasi DP"
        : phase === "PENDING_CONFIRM"
        ? "Konfirmasi pembayaran"
        : "Nota";
    const payload = wantQr ? String(qrPayload || "").trim() : "";
    const tip = String(phaseTip ||
      "QR sama dengan yang di APK Member (login nomor WA yang sama).");
    const headline = String(headlineMessage || "").trim();
    const link = String(hubUrl || "").trim();
    const cabang = String(tokoId || "").trim().toUpperCase();
    const qrImg = payload.startsWith("OBRINV|")
      ? `https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=${
        encodeURIComponent(payload)
      }`
      : "";
    const subject = qrImg
      ? `Nota ${invoice} · QR ${phaseLabel} — Optik B. Riski`
      : `Nota ${invoice} · ${phaseLabel} — Optik B. Riski`;

    const emailPayload: Record<string, unknown> = {
      from,
      to: [email],
      subject,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 28px; border: 1px solid #e8eef8; border-radius: 14px; color: #0f172a; background: #ffffff;">
          <div style="text-align: center; margin-bottom: 20px;">
            <h2 style="margin: 0; color: #0B3D8C; font-size: 22px; letter-spacing: 0.5px;">OPTIK B. RISKI</h2>
            <p style="margin: 6px 0 0; font-size: 12px; color: #64748b; text-transform: uppercase;">Nota digital</p>
          </div>

          <div style="background: #F3F7FF; padding: 14px 16px; border-radius: 10px; margin-bottom: 18px; font-size: 14px;">
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 4px 0; color: #64748b;">No. Invoice</td>
                <td style="padding: 4px 0; text-align: right; font-weight: 700;">${invoice}</td>
              </tr>
              <tr>
                <td style="padding: 4px 0; color: #64748b;">Pelanggan</td>
                <td style="padding: 4px 0; text-align: right; font-weight: 700;">${customerName || "Pelanggan"}</td>
              </tr>
              <tr>
                <td style="padding: 4px 0; color: #64748b;">Total</td>
                <td style="padding: 4px 0; text-align: right; font-weight: 800; color: #0B3D8C;">Rp ${netTotal || "0"}</td>
              </tr>
              ${
        cabang
          ? `<tr>
                <td style="padding: 4px 0; color: #64748b;">Cabang POS</td>
                <td style="padding: 4px 0; text-align: right; font-weight: 800; color: #0B3D8C;">${cabang}</td>
              </tr>`
          : ""
      }
            </table>
          </div>

          <p style="font-size: 14.5px; line-height: 1.55; color: #334155; margin: 0 0 16px;">
            ${
        headline ||
          `Halo <b>${
            customerName || "Pelanggan"
          }</b>, nota Anda sudah terbit.`
      }
          </p>

          ${
        qrImg
          ? `
          <div style="text-align:center; padding: 18px; border: 1px solid #dbe7ff; border-radius: 14px; background: linear-gradient(180deg,#F3F7FF,#ffffff); margin-bottom: 14px;">
            <div style="font-size: 12px; font-weight: 800; color: #0B3D8C; letter-spacing: 0.6px; margin-bottom: 8px;">QR FASE · ${phaseLabel}${cabang ? ` · ${cabang}` : ""}</div>
            <img src="${qrImg}" width="220" height="220" alt="QR Invoice" style="display:block;margin:0 auto 10px;border-radius:8px;" />
            <p style="margin:0;font-size:12.5px;color:#475569;line-height:1.45;">${tip}${cabang ? `<br/><b>Scan di POS ${cabang}</b>` : ""}</p>
            <p style="margin:10px 0 0;font-size:11px;color:#94a3b8;word-break:break-all;">${payload}</p>
          </div>`
          : `
          <div style="padding:14px;border-radius:10px;background:#eff6ff;color:#1e3a8a;font-size:13px;margin-bottom:14px;line-height:1.45;">
            ${tip || "QR akan dikirim saat pesanan siap (setelah konfirmasi admin)."}
          </div>`
      }

          ${
        link
          ? `<p style="text-align:center;margin:0 0 16px;">
              <a href="${link}" style="display:inline-block;background:#0B3D8C;color:#fff;text-decoration:none;padding:12px 18px;border-radius:10px;font-weight:700;font-size:13px;">
                Buka nota digital
              </a>
            </p>`
          : ""
      }

          <p style="font-size: 12px; color: #94a3b8; text-align: center; line-height: 1.5; margin: 0;">
            PDF terlampir (jika ada). Login APK Member dengan nomor WhatsApp yang sama agar QR selalu terbaru setelah pelunasan / serah terima.
          </p>
        </div>
      `,
    };

    if (pdfBase64) {
      emailPayload.attachments = [
        {
          filename: `Invoice-${invoice}.pdf`,
          content: pdfBase64,
        },
      ];
    }

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify(emailPayload),
    });

    const resendResult = await resendResponse.json();
    if (!resendResponse.ok) {
      throw new Error(`Ditolak Resend: ${JSON.stringify(resendResult)}`);
    }

    return new Response(
      JSON.stringify({
        message: "Email nota + QR terkirim",
        details: resendResult,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error: unknown) {
    const errorMessage = error instanceof Error
      ? error.message
      : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json",
      },
      status: 400,
    });
  }
});
