// Provision franchise Owner: create auth user + attach owners/profiles/map.
// Requires JWT of admin_pusat / super_admin / Owner Utama.
// @ts-ignore
declare const Deno: any;

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'Server misconfigured' }, 500);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(supabaseUrl, serviceKey);

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json({ error: 'Unauthorized' }, 401);
  }

  // ACL: provisioner RPC will also enforce; pre-check role here.
  const { data: profile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', userData.user.id)
    .maybeSingle();
  const role = String(profile?.role ?? '').toLowerCase();
  if (!['owner', 'admin_pusat', 'super_admin'].includes(role)) {
    return json({ error: 'Forbidden' }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const email = String(body.email ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  const nama = String(body.nama ?? '').trim();
  const ownerType = String(body.owner_type ?? 'toko').toLowerCase();
  const tokoIds = Array.isArray(body.toko_ids)
    ? body.toko_ids.map((t) => String(t))
    : [];
  const pctUtama = Number(body.pct_utama ?? 50);
  const pctToko = Number(body.pct_toko ?? 50);
  const phone = body.phone == null ? null : String(body.phone);
  const primaryToko =
    body.primary_toko == null ? null : String(body.primary_toko);

  if (!email || !password || password.length < 6 || !nama) {
    return json({ error: 'email, password (≥6), nama wajib' }, 400);
  }
  if (!['utama', 'toko'].includes(ownerType)) {
    return json({ error: 'owner_type harus utama|toko' }, 400);
  }

  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { nama, owner_type: ownerType },
  });

  if (createErr || !created.user) {
    // Maybe already exists — try lookup
    const { data: listed } = await admin.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    const existing = listed?.users?.find(
      (u) => (u.email ?? '').toLowerCase() === email,
    );
    if (!existing) {
      return json({ error: createErr?.message ?? 'createUser failed' }, 400);
    }
    const { error: rpcErr, data: rpcData } = await userClient.rpc(
      'admin_provision_owner',
      {
        p_user_id: existing.id,
        p_email: email,
        p_nama: nama,
        p_owner_type: ownerType,
        p_toko_ids: tokoIds,
        p_pct_utama: pctUtama,
        p_pct_toko: pctToko,
        p_phone: phone,
        p_primary_toko: primaryToko,
      },
    );
    if (rpcErr) return json({ error: rpcErr.message }, 400);
    return json({ ok: true, user_id: existing.id, reused: true, ...rpcData });
  }

  const userId = created.user.id;
  const { error: rpcErr, data: rpcData } = await userClient.rpc(
    'admin_provision_owner',
    {
      p_user_id: userId,
      p_email: email,
      p_nama: nama,
      p_owner_type: ownerType,
      p_toko_ids: tokoIds,
      p_pct_utama: pctUtama,
      p_pct_toko: pctToko,
      p_phone: phone,
      p_primary_toko: primaryToko,
    },
  );

  if (rpcErr) {
    // Rollback auth user if attach failed
    try {
      await admin.auth.admin.deleteUser(userId);
    } catch (_) {}
    return json({ error: rpcErr.message }, 400);
  }

  return json({ ok: true, user_id: userId, reused: false, result: rpcData });
});
