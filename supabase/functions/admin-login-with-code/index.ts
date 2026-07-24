// Login Admin via kode TOTP unik per karyawan (APK).
// Resolve kode → karyawan (audit), lalu buat sesi untuk akun Admin yang cocok.
// @ts-ignore
declare const Deno: any;

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const PUSAT_ROLES = new Set(['owner', 'admin_pusat', 'super_admin']);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function roleAllowedForActor(
  role: string,
  adminToko: string,
  actorToko: string,
): boolean {
  const r = role.toLowerCase();
  const aToko = adminToko.toUpperCase();
  const kToko = actorToko.toUpperCase();

  // Karyawan PUSAT → hanya akun pusat
  if (kToko === 'PUSAT') {
    return PUSAT_ROLES.has(r);
  }

  // Kepala Toko / Kepala Area cabang → admin_toko cabang yang sama, atau pusat
  if (PUSAT_ROLES.has(r)) return true;
  if (r === 'admin_toko' && aToko === kToko) return true;
  return false;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) {
      return json({ error: 'Server misconfigured' }, 500);
    }

    const body = await req.json();
    const email = String(body?.email ?? '')
      .trim()
      .toLowerCase();
    const code = String(body?.code ?? '').replace(/\D/g, '');

    if (!email || code.length !== 6) {
      return json({ error: 'Email dan kode 6 angka wajib diisi.' }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: allowed, error: allowErr } = await admin.rpc(
      'admin_login_totp_allow_attempt',
      { p_email: email },
    );
    if (allowErr) {
      console.error('allow_attempt', allowErr);
      return json({ error: 'Gagal cek rate limit.' }, 500);
    }
    if (allowed !== true) {
      return json(
        {
          error:
            'Terlalu banyak percobaan gagal. Tunggu 5 menit lalu coba lagi.',
        },
        429,
      );
    }

    const { data: actor, error: resolveErr } = await admin.rpc(
      'resolve_admin_login_totp',
      { p_code: code },
    );
    if (resolveErr) {
      console.error('resolve', resolveErr);
      return json({ error: 'Gagal verifikasi kode.' }, 500);
    }
    if (!actor || !actor.karyawan_id) {
      await admin.rpc('admin_login_totp_record_attempt', {
        p_email: email,
        p_success: false,
      });
      return json(
        {
          error:
            'Kode salah atau sudah kedaluwarsa. Ambil kode terbaru di APK (akun Anda).',
        },
        401,
      );
    }

    const actorToko = String(actor.toko_id ?? '')
      .trim()
      .toUpperCase();
    const actorNama = String(actor.nama ?? '').trim();
    const actorJabatan = String(actor.jabatan ?? '').trim();
    const actorId = String(actor.karyawan_id);

    const { data: profile, error: profileErr } = await admin
      .from('profiles')
      .select('id, email, role, toko_id')
      .ilike('email', email)
      .maybeSingle();

    if (profileErr) {
      console.error('profile', profileErr);
      return json({ error: 'Gagal membaca profil admin.' }, 500);
    }
    if (!profile) {
      await admin.rpc('admin_login_totp_record_attempt', {
        p_email: email,
        p_success: false,
      });
      return json({ error: 'Akun admin tidak ditemukan.' }, 401);
    }

    const role = String(profile.role ?? '')
      .trim()
      .toLowerCase();
    const adminToko = String(profile.toko_id ?? '')
      .trim()
      .toUpperCase();

    if (!roleAllowedForActor(role, adminToko, actorToko)) {
      await admin.rpc('admin_login_totp_record_attempt', {
        p_email: email,
        p_success: false,
      });
      return json(
        {
          error: actorToko === 'PUSAT'
            ? 'Kode karyawan PUSAT hanya untuk login akun Admin Pusat (owner / admin_pusat).'
            : `Kode Kepala Toko/Area ${actorToko} hanya untuk admin toko ${actorToko} (atau Admin Pusat).`,
        },
        403,
      );
    }

    const { data: karyawanEmailClash } = await admin
      .from('karyawan')
      .select('id')
      .ilike('email', email)
      .maybeSingle();
    if (karyawanEmailClash) {
      await admin.rpc('admin_login_totp_record_attempt', {
        p_email: email,
        p_success: false,
      });
      return json(
        {
          error:
            'Akun Karyawan tidak boleh masuk Admin. Pakai akun Admin + kode dari APK.',
        },
        403,
      );
    }

    const authEmail = String(profile.email ?? email).trim();
    const { data: linkData, error: linkErr } = await admin.auth.admin
      .generateLink({
        type: 'magiclink',
        email: authEmail,
      });

    if (linkErr || !linkData?.properties?.hashed_token) {
      console.error('generateLink', linkErr);
      await admin.rpc('admin_login_totp_record_attempt', {
        p_email: email,
        p_success: false,
      });
      return json(
        {
          error:
            'Gagal membuat sesi. Pastikan email admin cocok dengan Auth users.',
        },
        500,
      );
    }

    const tokenHash = linkData.properties.hashed_token as string;
    let { data: sessionData, error: otpErr } = await admin.auth.verifyOtp({
      token_hash: tokenHash,
      type: 'magiclink',
    });

    if (otpErr || !sessionData?.session) {
      const again = await admin.auth.admin.generateLink({
        type: 'magiclink',
        email: authEmail,
      });
      const hash2 = again.data?.properties?.hashed_token;
      if (hash2) {
        const fallback = await admin.auth.verifyOtp({
          token_hash: hash2,
          type: 'email',
        });
        sessionData = fallback.data;
        otpErr = fallback.error;
      }
    }

    if (otpErr || !sessionData?.session) {
      console.error('verifyOtp', otpErr);
      await admin.rpc('admin_login_totp_record_attempt', {
        p_email: email,
        p_success: false,
      });
      return json({ error: 'Gagal menukar token sesi.' }, 500);
    }

    const session = sessionData.session;
    await admin.rpc('admin_login_totp_record_attempt', {
      p_email: email,
      p_success: true,
    });

    const { data: auditId, error: auditErr } = await admin.rpc(
      'admin_login_code_record_success',
      {
        p_karyawan_id: actorId,
        p_admin_user_id: session.user?.id ?? profile.id,
        p_admin_email: authEmail,
        p_admin_role: role,
        p_admin_toko_id: adminToko,
      },
    );
    if (auditErr) {
      console.error('audit', auditErr);
    }

    return json({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      expires_in: session.expires_in,
      token_type: session.token_type ?? 'bearer',
      user: {
        id: session.user?.id,
        email: session.user?.email,
      },
      actor: {
        karyawan_id: actorId,
        nama: actorNama,
        toko_id: actorToko,
        jabatan: actorJabatan,
        audit_id: auditId ?? null,
      },
    });
  } catch (e) {
    console.error('admin-login-with-code', e);
    return json(
      { error: e instanceof Error ? e.message : 'Terjadi kesalahan server.' },
      500,
    );
  }
});
