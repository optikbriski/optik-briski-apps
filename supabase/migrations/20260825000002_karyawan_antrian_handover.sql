-- Antrian toko Karyawan: identity RPC + serah terima LUNAS (bukan checkout kasir).
-- Bloquer sebelumnya: sales_pos_guard / sales_items_pos_guard hanya can_pos_checkout
-- (profiles kasir) — karyawan Aktif + shift OPEN tetap ditolak saat handover.

-- -----------------------------------------------------------------------------
-- Helper: patch sales oleh karyawan = hanya fulfillment / QR serah terima
-- -----------------------------------------------------------------------------
create or replace function public.invoice_staff_handover_patch_ok(
  p_old public.sales,
  p_new public.sales
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    -- Identitas & bayar terkunci
    p_old.toko_id is not distinct from p_new.toko_id
    and p_old.tenant_id is not distinct from p_new.tenant_id
    and p_old.no_invoice is not distinct from p_new.no_invoice
    and p_old.kasir_karyawan_id is not distinct from p_new.kasir_karyawan_id
    and coalesce(p_old.channel, '') is not distinct from coalesce(p_new.channel, '')
    and p_old.online_order_id is not distinct from p_new.online_order_id
    and p_old.status_pembayaran is not distinct from p_new.status_pembayaran
    and p_old.dibayarkan is not distinct from p_new.dibayarkan
    and p_old.sisa_tagihan is not distinct from p_new.sisa_tagihan
    and p_old.total_harga is not distinct from p_new.total_harga
    and p_old.voucher_code is not distinct from p_new.voucher_code
    and p_old.voucher_discount is not distinct from p_new.voucher_discount
    -- Jangan mint / ganti token QR (hanya used_* + claim reuse)
    and p_old.qr_dp_token is not distinct from p_new.qr_dp_token
    and p_old.qr_lunas_token is not distinct from p_new.qr_lunas_token;
$$;

comment on function public.invoice_staff_handover_patch_ok(public.sales, public.sales) is
  'True jika UPDATE sales hanya field serah terima (tracking/diambil/QR used/claim), bukan bayar/kasir.';

revoke all on function public.invoice_staff_handover_patch_ok(public.sales, public.sales)
  from public, anon;
grant execute on function public.invoice_staff_handover_patch_ok(public.sales, public.sales)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- sales_pos_guard: izinkan karyawan hub + duty untuk patch handover
-- -----------------------------------------------------------------------------
create or replace function public.sales_pos_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jwt_role text;
  v_was_dp boolean;
  v_now_dp boolean;
  v_all_taken boolean;
  v_pay_changed boolean;
  v_dibayar_up boolean;
  v_kid uuid;
begin
  if tg_op = 'DELETE' then
    if auth.uid() is not null
       and not public.can_pos_checkout_for_toko(old.toko_id)
       and not public.is_platform_user() then
      raise exception 'Hanya kasir toko ini yang boleh batalkan nota.'
        using errcode = '42501';
    end if;
    return old;
  end if;

  if new.toko_id is null or trim(new.toko_id) = '' then
    raise exception 'toko_id nota wajib.' using errcode = '42501';
  end if;
  if new.tenant_id is null then
    new.tenant_id := public.current_tenant_id();
  end if;

  if coalesce(new.channel, '') = 'member_online'
     or new.online_order_id is not null then
    return new;
  end if;

  v_jwt_role := coalesce(auth.jwt() ->> 'role', '');

  if auth.uid() is not null then
    if public.can_pos_checkout_for_toko(new.toko_id) then
      null; -- kasir / admin toko: full write
    elsif tg_op = 'UPDATE'
       and public.invoice_can_staff_hub(new.toko_id) then
      v_kid := public.current_karyawan_id();
      if v_kid is null or not public.pos_duty_ok(v_kid, new.toko_id) then
        raise exception
          'Serah terima hanya untuk karyawan aktif yang sudah absen masuk (shift OPEN).'
          using errcode = '42501';
      end if;
      if not public.invoice_staff_handover_patch_ok(old, new) then
        raise exception
          'Karyawan hanya boleh serah terima pickup (bukan ubah bayar/kasir/nota).'
          using errcode = '42501';
      end if;
    else
      raise exception 'Hanya kasir toko/cabang ini yang boleh menulis nota.'
        using errcode = '42501';
    end if;
  elsif v_jwt_role is distinct from 'service_role' then
    raise exception 'Login kasir dulu.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      if new.kasir_karyawan_id is null then
        raise exception 'Kasir bertugas wajib sebelum checkout.'
          using errcode = '42501';
      end if;
      if not public.pos_duty_ok(new.kasir_karyawan_id, new.toko_id) then
        raise exception
          'Kasir harus sudah absen masuk (shift OPEN) di toko ini.'
          using errcode = '42501';
      end if;
    end if;
    if coalesce(new.voucher_code, '') = '' then
      new.voucher_discount := 0;
    end if;
    return new;
  end if;

  -- UPDATE: identitas terkunci. Duty kasir asli tidak wajib (shift sudah tutup).
  if not public.same_store_toko(old.toko_id, new.toko_id) then
    raise exception 'toko_id nota tidak boleh dipindah' using errcode = '42501';
  end if;
  if old.tenant_id is distinct from new.tenant_id then
    raise exception 'tenant_id nota tidak boleh diganti' using errcode = '42501';
  end if;
  if old.no_invoice is distinct from new.no_invoice then
    raise exception 'Nomor nota tidak boleh diganti' using errcode = '42501';
  end if;
  if old.kasir_karyawan_id is not null
     and new.kasir_karyawan_id is distinct from old.kasir_karyawan_id then
    raise exception 'kasir nota tidak boleh diganti' using errcode = '42501';
  end if;
  if coalesce(old.channel, '') is distinct from coalesce(new.channel, '')
     or old.online_order_id is distinct from new.online_order_id then
    raise exception 'channel nota tidak boleh diganti' using errcode = '42501';
  end if;

  if public.invoice_is_cancelled(new.tracking_status, new.status_pembayaran) then
    return new;
  end if;

  v_was_dp := public.invoice_is_dp(old.status_pembayaran, old.sisa_tagihan);
  v_now_dp := public.invoice_is_dp(new.status_pembayaran, new.sisa_tagihan);

  if not public.invoice_tracking_ok(
    old.tracking_status,
    new.tracking_status,
    v_was_dp,
    v_now_dp,
    new.status_pembayaran
  ) then
    raise exception
      'Status board tidak boleh lompat. DP: PENDING ↔ siap pelunasan. '
      'Lunas: PENDING → READY → CLEAR.'
      using errcode = '42501';
  end if;

  if upper(trim(coalesce(old.status_pembayaran, ''))) = 'LUNAS'
     and upper(trim(coalesce(new.status_pembayaran, ''))) = 'DP' then
    raise exception 'Nota lunas tidak boleh dibuka ulang jadi DP.'
      using errcode = '42501';
  end if;

  if coalesce(new.dibayarkan, 0) < coalesce(old.dibayarkan, 0)
     and not (
       coalesce(new.dibayarkan, 0) <= coalesce(new.total_harga, 0)
       and coalesce(new.sisa_tagihan, 0)
         = greatest(0, coalesce(new.total_harga, 0) - coalesce(new.dibayarkan, 0))
     ) then
    raise exception 'dibayarkan tidak boleh diturunkan semena-mena.'
      using errcode = '42501';
  end if;

  v_pay_changed :=
    upper(trim(coalesce(old.status_pembayaran, ''))) is distinct from
    upper(trim(coalesce(new.status_pembayaran, '')));
  v_dibayar_up := coalesce(new.dibayarkan, 0) > coalesce(old.dibayarkan, 0);

  if (v_pay_changed or v_dibayar_up)
     and upper(trim(coalesce(new.status_pembayaran, ''))) = 'LUNAS' then
    if coalesce(new.dibayarkan, 0) < coalesce(new.total_harga, 0)
       or coalesce(new.sisa_tagihan, 0) <> 0 then
      raise exception 'Pelunasan wajib dibayar penuh dan sisa 0.'
        using errcode = '42501';
    end if;
    if public.invoice_finance_credited(new) < coalesce(new.dibayarkan, 0) then
      raise exception
        'Pelunasan wajib jurnal Pelunasan/Penjualan Kasir sebesar yang dibayar.'
        using errcode = '42501';
    end if;
  end if;

  if public.invoice_norm_track(new.tracking_status) = 'DIAMBIL' then
    select not exists (
      select 1
      from public.sales_items i
      where i.sale_id = new.id
        and public.invoice_norm_line(i.fulfillment_status) <> 'DIAMBIL'
    ) into v_all_taken;
    if exists (select 1 from public.sales_items i where i.sale_id = new.id)
       and not v_all_taken then
      raise exception 'CLEAR hanya jika semua item sudah DIAMBIL.'
        using errcode = '42501';
    end if;
  end if;

  if coalesce(new.qr_dp_token, '') is distinct from coalesce(old.qr_dp_token, '')
     and nullif(trim(coalesce(new.qr_dp_token, '')), '') is not null
     and upper(trim(coalesce(new.tracking_status, ''))) <> 'SIAP_PELUNASAN' then
    raise exception 'QR DP hanya di fase siap pelunasan.' using errcode = '42501';
  end if;
  if coalesce(new.qr_lunas_token, '') is distinct from coalesce(old.qr_lunas_token, '')
     and nullif(trim(coalesce(new.qr_lunas_token, '')), '') is not null then
    if v_now_dp
       or public.invoice_norm_track(new.tracking_status) <> 'SIAP_DIAMBIL' then
      raise exception 'QR pengambilan hanya setelah lunas + Barang Ready.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- sales_items: fulfill-only (READY↔DIAMBIL) boleh karyawan hub + duty
-- -----------------------------------------------------------------------------
create or replace function public.sales_items_pos_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_harga bigint;
  v_fulfill_only boolean;
  v_kid uuid;
  v_is_kasir boolean;
  v_is_staff boolean;
begin
  if tg_op = 'DELETE' then
    if auth.uid() is not null then
      select * into v_sale from public.sales where id = old.sale_id;
      if found and not public.can_pos_checkout_for_toko(v_sale.toko_id) then
        raise exception 'Hanya kasir toko ini yang boleh hapus item nota.'
          using errcode = '42501';
      end if;
    end if;
    return old;
  end if;

  select * into v_sale from public.sales where id = new.sale_id;
  if not found then
    raise exception 'Nota penjualan tidak ditemukan.' using errcode = '42501';
  end if;

  if coalesce(v_sale.channel, '') = 'member_online'
     or v_sale.online_order_id is not null then
    new.qty := least(99, greatest(1, coalesce(new.qty, 1)));
    return new;
  end if;

  v_is_kasir := public.can_pos_checkout_for_toko(v_sale.toko_id);
  v_is_staff := public.invoice_can_staff_hub(v_sale.toko_id);

  if tg_op = 'INSERT' then
    if auth.uid() is not null and not v_is_kasir then
      raise exception 'Hanya kasir toko ini yang boleh menambah item nota.'
        using errcode = '42501';
    end if;
  elsif tg_op = 'UPDATE' then
    if not public.invoice_line_status_ok(
      old.fulfillment_status, new.fulfillment_status
    ) then
      raise exception
        'Status item hanya PENDING_RO → READY → DIAMBIL.'
        using errcode = '42501';
    end if;

    v_fulfill_only :=
      old.product_id is not distinct from new.product_id
      and old.qty is not distinct from new.qty
      and old.harga_satuan is not distinct from new.harga_satuan
      and old.subtotal is not distinct from new.subtotal;

    if v_fulfill_only then
      if v_is_kasir then
        return new;
      end if;
      if v_is_staff then
        v_kid := public.current_karyawan_id();
        if v_kid is null or not public.pos_duty_ok(v_kid, v_sale.toko_id) then
          raise exception
            'Update item serah terima hanya untuk karyawan yang sudah absen masuk.'
            using errcode = '42501';
        end if;
        return new;
      end if;
      raise exception 'Hanya kasir toko ini yang boleh mengubah item nota.'
        using errcode = '42501';
    end if;

    -- Bukan fulfill-only → wajib kasir (ubah harga/qty/produk)
    if auth.uid() is not null and not v_is_kasir then
      raise exception 'Hanya kasir toko ini yang boleh mengubah item nota.'
        using errcode = '42501';
    end if;
  end if;

  if new.product_id is null then
    raise exception 'product_id item wajib.' using errcode = '42501';
  end if;

  v_harga := public.pos_catalog_unit_price(new.product_id);
  if v_harga is null then
    raise exception 'Produk item bukan milik usaha ini.' using errcode = '42501';
  end if;

  new.qty := least(99, greatest(1, coalesce(new.qty, 1)));
  new.harga_satuan := v_harga;
  new.subtotal := v_harga * new.qty;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC antrian: resolve via current_karyawan_id + wajib duty OPEN
-- -----------------------------------------------------------------------------
create or replace function public.karyawan_antrian_action(
  p_kind text,
  p_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_kid uuid;
  v_toko text;
  v_tenant uuid;
  v_aktif text;
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_action text := lower(trim(coalesce(p_action, '')));
  v_row_toko text;
  v_row_tenant uuid;
  v_fulfill text;
  v_status text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_id is null or v_kind = '' or v_action = '' then
    return jsonb_build_object('ok', false, 'error', 'Parameter tidak lengkap');
  end if;

  v_kid := public.current_karyawan_id();
  if v_kid is null then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;

  select k.toko_id, k.tenant_id, lower(coalesce(k.status_approval, ''))
    into v_toko, v_tenant, v_aktif
  from public.karyawan k
  where k.id = v_kid
  limit 1;

  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;
  if v_aktif <> '' and v_aktif not in ('aktif', 'active') then
    return jsonb_build_object('ok', false, 'error', 'Karyawan tidak aktif');
  end if;

  if not public.pos_duty_ok(v_kid, v_toko) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Absen masuk dulu (shift OPEN) sebelum aksi antrian'
    );
  end if;

  if v_kind = 'booking' then
    if v_action not in ('checked_in', 'done', 'no_show') then
      return jsonb_build_object('ok', false, 'error', 'Aksi booking tidak valid');
    end if;
    select b.toko_id, b.tenant_id into v_row_toko, v_row_tenant
    from public.member_bookings b where b.id = p_id for update;
    if v_row_toko is null then
      return jsonb_build_object('ok', false, 'error', 'Booking tidak ditemukan');
    end if;
    if v_tenant is not null and v_row_tenant is not null and v_tenant <> v_row_tenant then
      return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
    end if;
    if not public.same_store_toko(v_toko, v_row_toko) then
      return jsonb_build_object('ok', false, 'error', 'Beda cabang');
    end if;
    update public.member_bookings set status = v_action where id = p_id;
    return jsonb_build_object('ok', true, 'status', v_action);
  end if;

  if v_kind = 'klaim' then
    if v_action <> 'diproses_toko' then
      return jsonb_build_object('ok', false, 'error', 'Aksi klaim tidak valid');
    end if;
    select r.toko_id, r.tenant_id into v_row_toko, v_row_tenant
    from public.garansi_klaim_request r where r.id = p_id for update;
    if v_row_toko is null then
      return jsonb_build_object('ok', false, 'error', 'Klaim tidak ditemukan');
    end if;
    if v_tenant is not null and v_row_tenant is not null and v_tenant <> v_row_tenant then
      return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
    end if;
    if not public.same_store_toko(v_toko, v_row_toko) then
      return jsonb_build_object('ok', false, 'error', 'Beda cabang');
    end if;
    update public.garansi_klaim_request
      set status = 'diproses_toko'
    where id = p_id;
    return jsonb_build_object('ok', true, 'status', 'diproses_toko');
  end if;

  if v_kind = 'online' then
    if v_action not in ('ready', 'fulfilled') then
      return jsonb_build_object('ok', false, 'error', 'Aksi online tidak valid');
    end if;
    select o.toko_id, o.tenant_id, o.fulfillment, o.status
      into v_row_toko, v_row_tenant, v_fulfill, v_status
    from public.online_orders o
    where o.id = p_id
    for update;
    if v_row_toko is null then
      return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
    end if;
    if v_tenant is not null and v_row_tenant is not null and v_tenant <> v_row_tenant then
      return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
    end if;
    if not public.same_store_toko(v_toko, v_row_toko) then
      return jsonb_build_object('ok', false, 'error', 'Beda cabang');
    end if;
    if lower(coalesce(v_fulfill, '')) <> 'pickup' then
      return jsonb_build_object('ok', false, 'error', 'Hanya order pickup');
    end if;
    if v_action = 'ready' and lower(coalesce(v_status, '')) not in ('paid', 'packing', 'ready') then
      return jsonb_build_object('ok', false, 'error', 'Status order belum bisa siap diambil');
    end if;
    if v_action = 'fulfilled' and lower(coalesce(v_status, '')) not in ('ready', 'fulfilled') then
      return jsonb_build_object('ok', false, 'error', 'Tandai siap diambil dulu');
    end if;
    update public.online_orders
      set status = v_action,
          updated_at = now()
    where id = p_id;
    return jsonb_build_object('ok', true, 'status', v_action);
  end if;

  return jsonb_build_object('ok', false, 'error', 'Jenis tidak dikenal');
end;
$$;

comment on function public.karyawan_antrian_action(text, uuid, text) is
  'Aksi inbox lantai toko: booking / klaim / online. Wajib current_karyawan_id + shift OPEN.';
