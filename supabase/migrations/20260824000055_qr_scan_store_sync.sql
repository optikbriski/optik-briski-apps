-- =============================================================================
-- 000055 — Scan QR toko: tenant wajib, toko sama (PUSAT = CABANG-PUSAT).
-- Apply di SQL Editor live SETELAH 000054. Idempotent.
--
-- Celah saat toko jalan:
-- - issue_attendance_qr_token expire exact toko_id → token PUSAT tetap hidup
--   saat Admin di CABANG-PUSAT (atau sebaliknya)
-- - token absensi tanpa tenant_id → expire/validate bisa nyentuh merek lain
--   yang kebetulan memakai kode toko yang sama
-- - validate_attendance_qr_token / issue tanpa p_tenant_id
-- - scan QR pelanggan (OBRINV) hanya dicek di HP — no_invoice lintas merek
-- - scan NIK karyawan tanpa tenant + toko nota
-- =============================================================================

alter table public.attendance_qr_tokens
  add column if not exists tenant_id uuid references public.tenants (id);

update public.attendance_qr_tokens t
set tenant_id = p.tenant_id
from public.profiles p
where t.tenant_id is null
  and p.id = t.created_by
  and p.tenant_id is not null;

create index if not exists attendance_qr_tokens_tenant_toko_expires_idx
  on public.attendance_qr_tokens (tenant_id, toko_id, expires_at desc);

-- -----------------------------------------------------------------------------
-- QR absensi: issue. Expire alias PUSAT ↔ CABANG-PUSAT di tenant sendiri.
-- -----------------------------------------------------------------------------
drop function if exists public.issue_attendance_qr_token(text, integer, uuid);
drop function if exists public.issue_attendance_qr_token(text, integer);

create or replace function public.issue_attendance_qr_token(
  p_toko_id text,
  p_ttl_seconds integer default 5,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_ttl integer;
  v_token text;
  v_expires timestamptz;
  v_id uuid;
  v_payload text;
  v_toko text := trim(coalesce(p_toko_id, ''));
  v_tenant uuid;
begin
  if v_uid is null then
    raise exception 'Login diperlukan untuk menampilkan QR absensi.';
  end if;
  v_tenant := public.require_member_tenant(
    coalesce(p_tenant_id, public.current_tenant_id())
  );
  if public.current_tenant_id() is not null
     and v_tenant is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    raise exception 'QR absensi bukan milik usaha ini.';
  end if;
  if v_toko = '' then
    raise exception 'toko_id wajib diisi.';
  end if;
  if not public.can_open_store_kiosk_for_toko(v_toko) then
    raise exception 'QR absensi hanya untuk toko Anda di usaha ini.';
  end if;
  if not exists (
    select 1
    from public.toko_id s
    where s.tenant_id = v_tenant
      and public.same_store_toko(s.id, v_toko)
  ) then
    raise exception 'Toko bukan milik usaha ini.';
  end if;

  v_ttl := greatest(5, least(coalesce(p_ttl_seconds, 5), 120));

  update public.attendance_qr_tokens
     set expires_at = now()
   where expires_at > now()
     and public.same_store_toko(toko_id, v_toko)
     and (
       tenant_id is not distinct from v_tenant
       or (
         tenant_id is null
         and public.toko_belongs_to_current_tenant(toko_id)
       )
     );

  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires := now() + make_interval(secs => v_ttl);

  insert into public.attendance_qr_tokens (
    toko_id, token, expires_at, created_by, tenant_id
  )
  values (v_toko, v_token, v_expires, v_uid, v_tenant)
  returning id into v_id;

  v_payload := 'OBRATT|v1|' || v_toko || '|' || v_token;

  return jsonb_build_object(
    'id', v_id,
    'toko_id', v_toko,
    'token', v_token,
    'payload', v_payload,
    'expires_at', v_expires,
    'ttl_seconds', v_ttl
  );
end;
$$;

revoke all on function public.issue_attendance_qr_token(text, integer, uuid)
  from public, anon;
grant execute on function public.issue_attendance_qr_token(text, integer, uuid)
  to authenticated, service_role;

comment on function public.issue_attendance_qr_token(text, integer, uuid) is
  'Kiosk: token QR absensi. Tenant wajib. Expire PUSAT = CABANG-PUSAT.';

-- -----------------------------------------------------------------------------
-- QR absensi: validate. Tenant + alias toko.
-- -----------------------------------------------------------------------------
drop function if exists public.validate_attendance_qr_token(text, uuid);
drop function if exists public.validate_attendance_qr_token(text);

create or replace function public.validate_attendance_qr_token(
  p_payload text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text := trim(coalesce(p_payload, ''));
  v_parts text[];
  v_toko text;
  v_token text;
  v_row public.attendance_qr_tokens%rowtype;
  v_karyawan_toko text;
  v_karyawan_tenant uuid;
  v_tenant uuid;
begin
  if v_uid is null then
    raise exception 'Login karyawan diperlukan untuk scan QR absensi.';
  end if;
  v_tenant := public.require_member_tenant(
    coalesce(p_tenant_id, public.current_tenant_id())
  );
  if public.current_tenant_id() is not null
     and v_tenant is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    raise exception 'QR absensi bukan milik usaha ini.';
  end if;

  if length(v_raw) = 0 then
    raise exception 'QR kosong / tidak terbaca.';
  end if;

  if position('|' in v_raw) > 0 then
    v_parts := string_to_array(v_raw, '|');
    if array_length(v_parts, 1) < 4
       or v_parts[1] <> 'OBRATT'
       or v_parts[2] <> 'v1' then
      raise exception 'Format QR absensi tidak dikenali. Scan QR di layar Admin toko.';
    end if;
    v_toko := trim(v_parts[3]);
    v_token := trim(v_parts[4]);
  else
    v_token := v_raw;
    v_toko := null;
  end if;

  if v_token is null or length(v_token) < 16 then
    raise exception 'Token QR tidak valid.';
  end if;

  select k.toko_id, k.tenant_id
    into v_karyawan_toko, v_karyawan_tenant
  from public.karyawan k
  where k.id = v_uid
     or (k.email is not null and k.email = (auth.jwt() ->> 'email'))
  order by case when k.id = v_uid then 0 else 1 end
  limit 1;

  if v_karyawan_toko is null or length(trim(v_karyawan_toko)) = 0 then
    raise exception 'Data karyawan tidak ditemukan untuk akun ini.';
  end if;

  if v_karyawan_tenant is null
     or v_karyawan_tenant is distinct from v_tenant then
    raise exception 'Akun karyawan bukan milik usaha ini.';
  end if;

  select * into v_row
  from public.attendance_qr_tokens t
  where t.token = v_token
    and (
      t.tenant_id is not distinct from v_tenant
      or (
        t.tenant_id is null
        and public.toko_belongs_to_current_tenant(t.toko_id)
      )
    )
  order by t.created_at desc
  limit 1;

  if not found then
    raise exception 'QR tidak dikenali. Pastikan scan QR Absensi di layar Admin.';
  end if;

  if v_row.expires_at <= now() then
    raise exception 'QR sudah kedaluwarsa. Minta Admin tampilkan QR terbaru.';
  end if;

  if not public.toko_belongs_to_current_tenant(v_row.toko_id) then
    raise exception 'QR absensi bukan milik usaha ini.';
  end if;

  if v_toko is not null
     and not public.same_store_toko(v_toko, v_row.toko_id) then
    raise exception 'QR tidak cocok dengan toko pada kode.';
  end if;

  if not public.same_store_toko(v_karyawan_toko, v_row.toko_id) then
    raise exception 'QR milik toko % — akun Anda terdaftar di %. Scan QR toko Anda.',
      v_row.toko_id, trim(v_karyawan_toko);
  end if;

  return jsonb_build_object(
    'ok', true,
    'token_id', v_row.id,
    'toko_id', v_row.toko_id,
    'expires_at', v_row.expires_at
  );
end;
$$;

revoke all on function public.validate_attendance_qr_token(text, uuid)
  from public, anon;
grant execute on function public.validate_attendance_qr_token(text, uuid)
  to authenticated, service_role;

comment on function public.validate_attendance_qr_token(text, uuid) is
  'Karyawan: validasi QR absensi. Tenant wajib. PUSAT = CABANG-PUSAT. Tidak consume.';

-- -----------------------------------------------------------------------------
-- QR pelanggan OBRINV: baca saja. Tidak hanguskan token.
-- -----------------------------------------------------------------------------
drop function if exists public.validate_invoice_customer_qr(text, uuid);

create or replace function public.validate_invoice_customer_qr(
  p_payload text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_raw text := trim(coalesce(p_payload, ''));
  v_parts text[];
  v_invoice text;
  v_phase text;
  v_token text;
  v_sale public.sales%rowtype;
  v_expected text;
  v_track text;
  v_dp boolean;
  v_diambil boolean;
  v_claim_ready boolean;
  v_ready integer;
begin
  if v_uid is null then
    raise exception 'Login kasir dulu.' using errcode = '42501';
  end if;
  v_tenant := public.require_member_tenant(
    coalesce(p_tenant_id, public.current_tenant_id())
  );
  if public.current_tenant_id() is not null
     and v_tenant is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    raise exception 'Nota bukan milik usaha ini.' using errcode = '42501';
  end if;
  if v_raw = '' then
    raise exception 'payload wajib' using errcode = 'P0001';
  end if;

  v_parts := string_to_array(v_raw, '|');
  if coalesce(array_length(v_parts, 1), 0) < 5
     or v_parts[1] <> 'OBRINV'
     or v_parts[2] <> 'v1' then
    return jsonb_build_object('ok', false, 'reason', 'bukan_qr_invoice');
  end if;

  v_invoice := trim(v_parts[3]);
  v_phase := upper(trim(v_parts[4]));
  if v_phase = 'KLAIM' then
    v_phase := 'CLAIM';
  elsif v_phase in ('PAID', 'FULL') then
    v_phase := 'LUNAS';
  end if;
  v_token := trim(v_parts[5]);

  if v_invoice = '' or length(v_token) < 8 then
    return jsonb_build_object('ok', false, 'reason', 'bukan_qr_invoice');
  end if;
  if v_phase not in ('DP', 'LUNAS', 'CLAIM') then
    return jsonb_build_object('ok', false, 'reason', 'fase_tidak_valid');
  end if;

  select * into v_sale
  from public.sales
  where tenant_id = v_tenant
    and no_invoice = v_invoice
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'invoice_tidak_ditemukan');
  end if;

  if not public.invoice_can_staff_hub(v_sale.toko_id)
     and not public.is_platform_user() then
    return jsonb_build_object('ok', false, 'reason', 'bukan_kasir_toko_ini');
  end if;

  v_dp := public.invoice_is_dp(v_sale.status_pembayaran, v_sale.sisa_tagihan);
  v_track := upper(trim(coalesce(v_sale.tracking_status, '')));
  v_diambil := v_sale.diambil_at is not null or v_track = 'DIAMBIL';
  v_claim_ready := length(trim(coalesce(v_sale.qr_claim_token, ''))) >= 8;

  if v_phase = 'DP' then
    if not v_dp then
      return jsonb_build_object('ok', false, 'reason', 'qr_dp_sudah_lunas');
    end if;
    if v_track <> 'SIAP_PELUNASAN' then
      return jsonb_build_object('ok', false, 'reason', 'qr_dp_belum_ready');
    end if;
    if v_sale.qr_dp_used_at is not null then
      return jsonb_build_object('ok', false, 'reason', 'qr_dp_sudah_dipakai');
    end if;
    v_expected := v_sale.qr_dp_token;
  elsif v_phase = 'LUNAS' then
    if v_dp then
      return jsonb_build_object('ok', false, 'reason', 'qr_lunas_masih_dp');
    end if;
    if v_diambil then
      return jsonb_build_object('ok', false, 'reason', 'qr_lunas_sudah_serah_terima');
    end if;
    if v_sale.qr_lunas_used_at is not null then
      return jsonb_build_object('ok', false, 'reason', 'qr_lunas_sudah_dipakai');
    end if;
    if v_track not in ('SIAP_DIAMBIL', 'CLEAR') then
      return jsonb_build_object('ok', false, 'reason', 'qr_lunas_belum_ready');
    end if;
    select count(*)::int into v_ready
    from public.sales_items i
    where i.sale_id = v_sale.id
      and public.invoice_norm_line(i.fulfillment_status) = 'READY';
    if coalesce(v_ready, 0) <= 0 then
      return jsonb_build_object('ok', false, 'reason', 'qr_lunas_belum_ada_ready');
    end if;
    v_expected := v_sale.qr_lunas_token;
  else
    if not v_diambil and not v_claim_ready then
      return jsonb_build_object('ok', false, 'reason', 'qr_claim_belum_berlaku');
    end if;
    if v_sale.qr_claim_used_at is not null then
      return jsonb_build_object('ok', false, 'reason', 'qr_claim_sudah_dipakai');
    end if;
    v_expected := v_sale.qr_claim_token;
  end if;

  if v_expected is null or trim(v_expected) <> v_token then
    return jsonb_build_object('ok', false, 'reason', 'token_tidak_cocok');
  end if;

  return jsonb_build_object(
    'ok', true,
    'sale_id', v_sale.id,
    'no_invoice', v_sale.no_invoice,
    'phase', v_phase,
    'toko_id', v_sale.toko_id,
    'tenant_id', v_sale.tenant_id
  );
end;
$$;

revoke all on function public.validate_invoice_customer_qr(text, uuid)
  from public, anon;
grant execute on function public.validate_invoice_customer_qr(text, uuid)
  to authenticated, service_role;

comment on function public.validate_invoice_customer_qr(text, uuid) is
  'Kasir: cek QR OBRINV vs nota tenant+toko. Baca saja — tidak consume token.';

-- -----------------------------------------------------------------------------
-- Barcode NIK karyawan: tenant + toko nota (PUSAT = CABANG-PUSAT).
-- -----------------------------------------------------------------------------
drop function if exists public.lookup_staff_by_nik(text, text, uuid);

create or replace function public.lookup_staff_by_nik(
  p_nik text,
  p_nota_toko_id text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_nik text := trim(coalesce(p_nik, ''));
  v_nota text := trim(coalesce(p_nota_toko_id, ''));
  v_row public.karyawan%rowtype;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Login kasir dulu.' using errcode = '42501';
  end if;
  v_tenant := public.require_member_tenant(
    coalesce(p_tenant_id, public.current_tenant_id())
  );
  if public.current_tenant_id() is not null
     and v_tenant is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    raise exception 'Karyawan bukan milik usaha ini.' using errcode = '42501';
  end if;
  if v_nik = '' then
    return jsonb_build_object('ok', false, 'reason', 'nik_kosong');
  end if;

  select * into v_row
  from public.karyawan k
  where k.tenant_id = v_tenant
    and trim(k.nik) = v_nik
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'nik_tidak_ditemukan');
  end if;

  v_status := lower(trim(coalesce(v_row.status_approval, '')));
  if v_status <> '' and v_status <> 'aktif' then
    return jsonb_build_object('ok', false, 'reason', 'karyawan_tidak_aktif');
  end if;

  if v_nota <> ''
     and not public.same_store_toko(v_row.toko_id, v_nota) then
    return jsonb_build_object('ok', false, 'reason', 'karyawan_beda_toko');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'nik', v_row.nik,
    'nama', v_row.nama,
    'jabatan', v_row.jabatan,
    'toko_id', v_row.toko_id,
    'status_approval', v_row.status_approval,
    'tenant_id', v_row.tenant_id
  );
end;
$$;

revoke all on function public.lookup_staff_by_nik(text, text, uuid)
  from public, anon;
grant execute on function public.lookup_staff_by_nik(text, text, uuid)
  to authenticated, service_role;

comment on function public.lookup_staff_by_nik(text, text, uuid) is
  'Kasir: cari karyawan by NIK di tenant + toko nota. PUSAT = CABANG-PUSAT.';
