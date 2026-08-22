-- =============================================================================
-- Klaim owner setelah beli etalase.
-- User daftar/masuk Auth sendiri, lalu ikat profiles ke tenant pesanan.
-- Tidak membuat auth.users (tanpa service_role). Bukan kasir.
-- Apply setelah 000012. Jangan dari agent ke live.
-- =============================================================================

create or replace function public.claim_store_owner(
  p_slug text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.email(), '')));
  v_slug text := public.normalize_tenant_slug(p_slug);
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  v_tid uuid;
  v_ord_phone text;
  v_ord_email text;
  v_pusat text;
  v_other uuid;
  v_mine uuid;
begin
  if public.is_platform_user() then
    return jsonb_build_object(
      'ok', false,
      'reason', 'platform',
      'error', 'Akun operator Rekasa tidak boleh diklaim sebagai owner toko.'
    );
  end if;
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'anon', 'error', 'Login dulu');
  end if;
  if v_slug is null or length(v_slug) < 3 then
    return jsonb_build_object('ok', false, 'reason', 'slug', 'error', 'Kode usaha tidak valid');
  end if;
  if v_phone is null or length(v_phone) < 8 then
    return jsonb_build_object('ok', false, 'reason', 'phone', 'error', 'Nomor WA / HP tidak cocok');
  end if;

  select o.tenant_id, o.phone, o.email
    into v_tid, v_ord_phone, v_ord_email
  from public.store_orders o
  where o.slug = v_slug
  order by o.created_at desc
  limit 1;

  if v_tid is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'not_found',
      'error', 'Pesanan kode usaha ini tidak ada. Beli dulu di etalase.'
    );
  end if;

  if right(regexp_replace(coalesce(v_ord_phone, ''), '[^0-9]', '', 'g'), 9)
     is distinct from right(regexp_replace(v_phone, '[^0-9]', '', 'g'), 9) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'phone',
      'error', 'Nomor HP tidak sama dengan yang dipakai saat beli.'
    );
  end if;

  if nullif(trim(coalesce(v_ord_email, '')), '') is not null
     and v_email <> ''
     and lower(trim(v_ord_email)) is distinct from v_email then
    return jsonb_build_object(
      'ok', false,
      'reason', 'email',
      'error', 'Pakai email yang sama dengan pesanan etalase.'
    );
  end if;

  select p.id into v_other
  from public.profiles p
  where p.tenant_id = v_tid
    and p.id is distinct from v_uid
    and coalesce(p.is_platform, false) = false
    and lower(coalesce(p.role, '')) in ('owner', 'super_admin', 'admin_pusat')
  limit 1;
  if v_other is not null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'taken',
      'error', 'Usaha ini sudah punya owner. Masuk pakai akun yang sudah diikat.'
    );
  end if;

  select p.tenant_id into v_mine from public.profiles p where p.id = v_uid;
  if v_mine is not null and v_mine is distinct from v_tid then
    return jsonb_build_object(
      'ok', false,
      'reason', 'bound',
      'error', 'Akun ini sudah terikat usaha lain.'
    );
  end if;

  select t.pusat_toko_id into v_pusat from public.tenants t where t.id = v_tid;
  if v_pusat is null or v_pusat = '' then
    return jsonb_build_object('ok', false, 'reason', 'toko', 'error', 'Pusat usaha belum siap');
  end if;

  insert into public.profiles (id, email, role, toko_id, tenant_id, updated_at)
  values (v_uid, nullif(v_email, ''), 'owner', v_pusat, v_tid, now())
  on conflict (id) do update
    set email = excluded.email,
        role = 'owner',
        toko_id = excluded.toko_id,
        tenant_id = excluded.tenant_id,
        updated_at = now();

  return public.my_tenant_account();
end;
$$;

grant execute on function public.claim_store_owner(text, text) to authenticated;

comment on function public.claim_store_owner(text, text) is
  'Ikat auth user ke tenant pesanan etalase (slug + HP). Bukan provision kasir.';
