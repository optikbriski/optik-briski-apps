-- =============================================================================
-- 000050 — Adjust Invoice / hub nota: tenant wajib + toko yang sama.
-- Apply di SQL Editor live SETELAH 000049.
--
-- Celah saat toko kelola nota:
-- - get_invoice_hub default UUID Optik → merek lain / tanpa tenant jatuh ke #1
-- - set_invoice_pembuat masih bisa dipanggil anon (400 login, bukan revoke)
-- - footer PUSAT exact (PUSAT ≠ CABANG-PUSAT)
-- =============================================================================

create or replace function public.get_invoice_hub(
  p_no_invoice text,
  p_phone text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sale public.sales%rowtype;
  v_items jsonb;
  v_garansi jsonb;
  v_ratings jsonb;
  v_is_staff boolean := false;
  v_can_mint boolean := false;
  v_uid uuid := auth.uid();
  v_claimable boolean := false;
  v_review text;
  v_bisa_rating boolean := false;
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_owner boolean := false;
  v_is_dp boolean := false;
  v_diambil boolean := false;
  v_phase text;
  v_token text;
  v_payload text;
  v_token_col text;
  v_channel text;
  v_tenant uuid;
begin
  if p_no_invoice is null or length(trim(p_no_invoice)) = 0 then
    return null;
  end if;

  if public.is_platform_user() then
    v_tenant := null;
  else
    v_tenant := coalesce(
      public.current_tenant_id(),
      public.require_member_tenant(p_tenant_id)
    );
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
    and (v_tenant is null or tenant_id = v_tenant)
  limit 1;
  if not found then return null; end if;

  v_is_staff := public.invoice_can_staff_hub(v_sale.toko_id);
  v_can_mint := public.can_pos_checkout_for_toko(v_sale.toko_id);

  if v_phone is not null then
    v_alt := case
      when v_phone like '62%' then '0' || substr(v_phone, 3)
      else v_phone
    end;
    v_owner := (
      public.wa_digits(v_sale.no_wa) = v_phone
      or regexp_replace(coalesce(v_sale.no_wa, ''), '\D', '', 'g')
        in (v_phone, v_alt)
    );
  end if;

  if not v_is_staff and not v_owner then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', si.id,
    'nama_produk', si.nama_produk,
    'tipe_produk', si.tipe_produk,
    'qty', si.qty,
    'subtotal', si.subtotal,
    'detail_resep', si.detail_resep,
    'needs_fulfillment', coalesce(si.needs_fulfillment, false),
    'fulfillment_status', coalesce(si.fulfillment_status, 'READY'),
    'diambil_at', si.diambil_at
  ) order by si.nama_produk), '[]'::jsonb)
  into v_items
  from public.sales_items si
  where si.sale_id = v_sale.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id,
    'jenis_garansi', g.jenis_garansi,
    'nama_produk', g.nama_produk,
    'status', g.status,
    'tanggal_mulai', g.tanggal_mulai,
    'tanggal_akhir', g.tanggal_akhir,
    'klaim_digunakan', g.klaim_digunakan,
    'spesifikasi_produk', g.spesifikasi_produk,
    'no_invoice', g.no_invoice,
    'sale_id', g.sale_id,
    'toko_id', g.toko_id
  )), '[]'::jsonb)
  into v_garansi
  from public.garansi_kartu g
  where g.sale_id = v_sale.id;

  select exists (
    select 1 from public.garansi_kartu g
    where g.sale_id = v_sale.id
      and g.status = 'aktif'
      and coalesce(g.klaim_digunakan, false) = false
      and g.tanggal_akhir is not null
      and g.tanggal_akhir::date >= (timezone('Asia/Jakarta', now()))::date
  ) into v_claimable;

  select coalesce(i.google_review_url, p.google_review_url)
  into v_review
  from (select 1) _
  left join public.invoice_settings i
    on public.same_store_toko(i.toko_id, v_sale.toko_id)
  left join public.invoice_settings p
    on public.same_store_toko(p.toko_id, 'PUSAT');

  v_bisa_rating := (
    v_sale.diambil_at is not null
    or upper(trim(coalesce(v_sale.tracking_status, ''))) = 'DIAMBIL'
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'peran', r.peran,
    'skor', r.skor,
    'komentar', r.komentar,
    'created_at', r.created_at
  )), '[]'::jsonb)
  into v_ratings
  from public.invoice_rating r
  where r.sale_id = v_sale.id;

  v_is_dp := public.invoice_is_dp(v_sale.status_pembayaran, v_sale.sisa_tagihan);
  v_diambil := (
    v_sale.diambil_at is not null
    or upper(trim(coalesce(v_sale.tracking_status, ''))) = 'DIAMBIL'
  );
  v_channel := case
    when lower(trim(coalesce(v_sale.channel, ''))) = 'online' then 'ONLINE'
    else 'OFFLINE'
  end;

  if v_is_dp then
    if v_sale.qr_dp_used_at is null
       and upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
    then
      v_phase := 'DP';
      v_token := nullif(trim(coalesce(v_sale.qr_dp_token, '')), '');
      v_token_col := 'qr_dp_token';
    end if;
  elsif not v_diambil then
    if upper(trim(coalesce(v_sale.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR') then
      v_phase := 'LUNAS';
      v_token := nullif(trim(coalesce(v_sale.qr_lunas_token, '')), '');
      v_token_col := 'qr_lunas_token';
      if v_sale.qr_lunas_used_at is not null then
        v_phase := null;
        v_token := null;
        v_token_col := null;
      end if;
    end if;
  else
    v_phase := 'CLAIM';
    v_token := nullif(trim(coalesce(v_sale.qr_claim_token, '')), '');
    v_token_col := 'qr_claim_token';
    if v_sale.qr_claim_used_at is not null then
      v_phase := null;
      v_token := null;
      v_token_col := null;
    end if;
  end if;

  if v_phase is null
     and v_sale.qr_claim_used_at is null
     and length(trim(coalesce(v_sale.qr_claim_token, ''))) >= 8
  then
    v_phase := 'CLAIM';
    v_token := nullif(trim(coalesce(v_sale.qr_claim_token, '')), '');
    v_token_col := 'qr_claim_token';
  end if;

  if v_can_mint
     and v_phase is not null
     and v_token_col is not null
     and (v_token is null or length(v_token) < 8)
  then
    v_token := encode(extensions.gen_random_bytes(16), 'hex');
    if v_token_col = 'qr_dp_token' then
      update public.sales set qr_dp_token = v_token where id = v_sale.id;
    elsif v_token_col = 'qr_lunas_token' then
      update public.sales set qr_lunas_token = v_token where id = v_sale.id;
    else
      update public.sales set qr_claim_token = v_token where id = v_sale.id;
    end if;
  end if;

  if (v_owner or v_is_staff)
     and v_phase is not null
     and v_token is not null
     and length(v_token) >= 8
  then
    v_payload := 'OBRINV|v1|' || trim(v_sale.no_invoice) || '|' || v_phase
      || '|' || v_token || '|' || v_channel;
  else
    v_payload := null;
  end if;

  return jsonb_build_object(
    'role_view', case when v_is_staff then 'staff' else 'customer' end,
    'sale_id', v_sale.id,
    'no_invoice', v_sale.no_invoice,
    'toko_id', v_sale.toko_id,
    'nama_pelanggan', v_sale.nama_pelanggan,
    'nama_kasir', v_sale.nama_kasir,
    'nama_pembuat_kacamata', v_sale.nama_pembuat_kacamata,
    'kasir_karyawan_id', v_sale.kasir_karyawan_id,
    'pembuat_kacamata_id', v_sale.pembuat_kacamata_id,
    'status_pembayaran', v_sale.status_pembayaran,
    'tracking_status', v_sale.tracking_status,
    'diambil_at', v_sale.diambil_at,
    'foto_hasil_url', v_sale.foto_hasil_url,
    'created_at', v_sale.created_at,
    'lunas_at', v_sale.lunas_at,
    'total_harga', v_sale.total_harga,
    'dibayarkan', v_sale.dibayarkan,
    'sisa_tagihan', v_sale.sisa_tagihan,
    'metode_pembayaran', v_sale.metode_pembayaran,
    'channel', v_sale.channel,
    'fulfillment', v_sale.fulfillment,
    'courier', v_sale.courier,
    'online_order_id', v_sale.online_order_id,
    'no_wa', case when v_is_staff then v_sale.no_wa else null end,
    'email_pelanggan', case when v_is_staff then v_sale.email_pelanggan else null end,
    'alamat', case when v_is_staff then v_sale.alamat else null end,
    'items', v_items,
    'garansi', v_garansi,
    'garansi_claimable', v_claimable,
    'google_review_url', v_review,
    'bisa_rating', v_bisa_rating,
    'ratings', coalesce(v_ratings, '[]'::jsonb),
    'qr_dp_ready',
      upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
      and v_sale.qr_dp_token is not null
      and v_sale.qr_dp_used_at is null,
    'qr_lunas_ready',
      upper(trim(coalesce(v_sale.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR')
      and v_sale.qr_lunas_token is not null
      and v_sale.qr_lunas_used_at is null,
    'qr_claim_ready', (v_sale.qr_claim_token is not null and v_sale.qr_claim_used_at is null)
      or (v_phase = 'CLAIM' and v_payload is not null),
    'qr_dp_used', (v_sale.qr_dp_used_at is not null),
    'qr_lunas_used', (v_sale.qr_lunas_used_at is not null),
    'qr_claim_used', (v_sale.qr_claim_used_at is not null),
    'qr_phase', v_phase,
    'qr_payload', v_payload,
    'qr_owner_verified', v_owner
  );
end;
$$;

comment on function public.get_invoice_hub(text, text, uuid) is
  'Hub nota. Tenant wajib (bukan default Optik). Anon + HP cocok. Footer PUSAT = CABANG-PUSAT.';

revoke all on function public.get_invoice_hub(text, text, uuid) from public;
grant execute on function public.get_invoice_hub(text, text, uuid)
  to anon, authenticated, service_role;

create or replace function public.set_invoice_pembuat(
  p_no_invoice text,
  p_karyawan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nama text;
  v_sale_id uuid;
  v_tenant uuid;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if auth.uid() is null then
    raise exception 'Login diperlukan';
  end if;
  v_tenant := public.current_tenant_id();
  if v_tenant is null and not public.is_platform_user() then
    raise exception 'tenant wajib — nota tidak boleh lintas merek';
  end if;

  select nama into v_nama
  from public.karyawan
  where id = p_karyawan_id
    and (v_tenant is null or tenant_id is not distinct from v_tenant)
  limit 1;

  if v_nama is null then
    raise exception 'Karyawan tidak ditemukan';
  end if;

  update public.sales
  set
    pembuat_kacamata_id = p_karyawan_id,
    nama_pembuat_kacamata = v_nama
  where no_invoice = trim(p_no_invoice)
    and (v_tenant is null or tenant_id is not distinct from v_tenant)
  returning id into v_sale_id;

  if v_sale_id is null then
    raise exception 'Invoice tidak ditemukan';
  end if;

  update public.lab_jobs
     set status = case when status = 'DONE' then 'DONE' else 'CLAIMED' end,
         claimed_by = p_karyawan_id,
         claimed_at = coalesce(claimed_at, now())
   where sale_id = v_sale_id
     and status in ('OPEN', 'CLAIMED');

  perform public.ensure_lab_job_for_sale(v_sale_id);
  update public.lab_jobs
     set status = case when status = 'DONE' then 'DONE' else 'CLAIMED' end,
         claimed_by = p_karyawan_id,
         claimed_at = coalesce(claimed_at, now())
   where sale_id = v_sale_id
     and status in ('OPEN', 'CLAIMED');

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'pembuat_kacamata_id', p_karyawan_id,
    'nama_pembuat_kacamata', v_nama
  );
end;
$$;

comment on function public.set_invoice_pembuat(text, uuid) is
  'Set pembuat kacamata. Bukan anon. Bukan merek lain.';

revoke all on function public.set_invoice_pembuat(text, uuid) from public, anon;
grant execute on function public.set_invoice_pembuat(text, uuid)
  to authenticated, service_role;
