// @ts-ignore
declare const Deno: any;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function digitsPhone(raw: string): string {
  let d = (raw || "").replace(/\D/g, "");
  if (d.startsWith("0")) d = "62" + d.slice(1);
  if (d.startsWith("8")) d = "62" + d;
  return d;
}

function money(n: unknown): string {
  const v = Number(n) || 0;
  return v.toLocaleString("id-ID");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const invoice = String(body.invoice || "").trim();
    const phone = digitsPhone(String(body.phone || ""));
    const customerName = String(body.customerName || "Pelanggan");
    const netTotal = body.netTotal;
    const qrPayload = String(body.qrPayload || "").trim();
    const qrPhase = String(body.qrPhase || "").trim().toUpperCase();
    const hubUrl = String(body.hubUrl || "").trim();
    const phaseTip = String(body.phaseTip || "").trim();
    const sisa = Number(body.sisaTagihan) || 0;
    const tokoId = String(body.tokoId || "").trim();

    if (!invoice || phone.length < 10) {
      throw new Error("invoice / phone wajib");
    }

    const phaseLabel =
      qrPhase === "DP"
        ? "DP (pelunasan)"
        : qrPhase === "LUNAS"
        ? "LUNAS / serah terima"
        : qrPhase === "CLAIM"
        ? "CLAIM garansi"
        : qrPhase || "Nota";

    const cabang = (tokoId || "").toUpperCase();
    const lines = [
      `*Optik B. Riski — Nota digital*`,
      ``,
      `Halo *${customerName}*,`,
      `Nota *${invoice}*${cabang ? ` · cabang *${cabang}*` : ""} sudah siap.`,
      `Total: Rp ${money(netTotal)}`,
      sisa > 0 ? `Sisa tagihan: Rp ${money(sisa)}` : `Status: LUNAS`,
      ``,
      `*QR fase: ${phaseLabel}*`,
      phaseTip || "Tunjukkan QR ke kasir/petugas.",
      cabang
        ? `⚠️ Scan QR di POS cabang *${cabang}* (tempat beli). Kode sama di email, WhatsApp, dan APK Member.`
        : null,
      ``,
      hubUrl ? `Buka nota: ${hubUrl}` : null,
      ``,
      `APK Member (login nomor WA yang sama) → Pesanan → Nota digital.`,
      qrPayload ? `\nKode QR (untuk kasir):\n${qrPayload}` : null,
    ].filter((x) => x != null);

    const msg = lines.join("\n");

    const fonnte = Deno.env.get("FONNTE_TOKEN");
    if (fonnte) {
      const form = new FormData();
      form.append("target", phone);
      form.append("message", msg);
      // Gambar QR publik agar pelanggan bisa scan dari chat
      if (qrPayload.startsWith("OBRINV|")) {
        const qrUrl =
          `https://api.qrserver.com/v1/create-qr-code/?size=280x280&data=${
            encodeURIComponent(qrPayload)
          }`;
        form.append("url", qrUrl);
      }
      const res = await fetch("https://api.fonnte.com/send", {
        method: "POST",
        headers: { Authorization: fonnte },
        body: form,
      });
      const text = await res.text();
      if (!res.ok) throw new Error(`Fonnte: ${text}`);
      return new Response(JSON.stringify({ ok: true, channel: "fonnte", detail: text }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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
        body: JSON.stringify({
          phone,
          message: msg,
          qrPayload,
          qrPhase,
          invoice,
        }),
      });
      const text = await res.text();
      if (!res.ok) throw new Error(`WA gateway: ${text}`);
      return new Response(JSON.stringify({ ok: true, channel: "gateway", detail: text }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    throw new Error("FONNTE_TOKEN / WA_GATEWAY_URL belum di-set");
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
