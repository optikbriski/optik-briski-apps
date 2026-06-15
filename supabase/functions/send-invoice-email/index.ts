// @ts-ignore
declare const Deno: any;

Deno.serve(async (req: Request) => {
  
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Menangkap lemparan data dari Flutter, termasuk file PDF berbentuk string Base64
    const { invoice, email, customerName, netTotal, pdfBase64 } = await req.json();
    console.log(`[Resend Sandbox] Memproses kirim email ke: ${email} untuk Invoice: ${invoice}`);

    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
    if (!RESEND_API_KEY) {
      throw new Error("Eror: RESEND_API_KEY belum terpasang di Secrets Supabase!");
    }

    // Menyiapkan paket data email
    const emailPayload: any = {
      from: 'Optik B. Riski <onboarding@resend.dev>',
      to: [email], // Selama uji coba, ini harus bernilai risctonn@gmail.com
      subject: `Nota Pembelian Resmi ${invoice} - Optik B. Riski`,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 30px; border: 1px solid #eaeaee; border-radius: 12px; color: #333333; background-color: #ffffff;">
          <div style="text-align: center; margin-bottom: 25px;">
            <h2 style="margin: 0; color: #111111; font-size: 24px; letter-spacing: 1px;">OPTIK B. RISKI</h2>
            <p style="margin: 5px 0 0 0; font-size: 12px; color: #888888; text-transform: uppercase;">Digital Purchase Invoice</p>
          </div>
          
          <div style="background-color: #f9f9f9; padding: 15px; border-radius: 8px; margin-bottom: 20px; font-size: 14px;">
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 4px 0; color: #777777;">No. Invoice</td>
                <td style="padding: 4px 0; text-align: right; font-weight: bold; color: #111111;">${invoice}</td>
              </tr>
              <tr>
                <td style="padding: 4px 0; color: #777777;">Pelanggan</td>
                <td style="padding: 4px 0; text-align: right; font-weight: bold; color: #111111;">${customerName || 'Pelanggan Setia'}</td>
              </tr>
            </table>
          </div>

          <p style="font-size: 15px; line-height: 1.6; color: #444444;">
            Halo <b>${customerName || 'Pelanggan'}</b>,<br>
            Terima kasih telah memercayakan kebutuhan optik Anda kepada kami. Dokumen nota digital resmi Anda telah kami lampirkan dalam bentuk PDF pada email ini.
          </p>

          <hr style="border: none; border-top: 1px dashed #dddddd; margin: 20px 0;" />

          <div style="display: flex; justify-content: space-between; align-items: center; margin: 15px 0;">
            <span style="font-size: 16px; font-weight: bold; color: #111111;">TOTAL PEMBAYARAN</span>
            <span style="font-size: 20px; font-weight: bold; color: #2e7d32; text-align: right; display: block; width: 100%;">Rp ${netTotal || '0'}</span>
          </div>

          <hr style="border: none; border-top: 1px dashed #dddddd; margin: 20px 0;" />

          <p style="font-size: 12px; color: #999999; text-align: center; line-height: 1.5; margin-top: 25px;">
            Nota fisik dan rekam medis lensa digital Anda dapat divalidasi langsung di toko via QR Code kapan saja.<br>
            <br>
            <b>Thank You for Your Visit!</b>
          </p>
        </div>
      `,
    };

    // 📎 JALUR LAMPIRAN PDF: Jika Flutter mengirimkan data base64, pasang ke Resend
    if (pdfBase64) {
      emailPayload.attachments = [
        {
          filename: `Invoice-${invoice}.pdf`,
          content: pdfBase64, // Resend otomatis membaca string Base64 ini menjadi file fisik PDF
        }
      ];
    }

    // Eksekusi tembakan HTTP ke Resend API
    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify(emailPayload),
    });

    const resendResult = await resendResponse.json();

    if (!resendResponse.ok) {
      throw new Error(`Ditolak Resend: ${JSON.stringify(resendResult)}`);
    }

    return new Response(
      JSON.stringify({ message: 'Email beserta Lampiran PDF sukses terkirim!', details: resendResult }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    );

  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error("🔴 LOG EROR UTAMA:", errorMessage);
    
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    );
  }
});