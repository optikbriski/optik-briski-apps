-- =============================================================================
-- 000025 — DP · PENDING · READY · CLEAR end-to-end.
-- Apply di SQL Editor live SETELAH 000024.
--
-- Celah saat toko jalan:
-- - get_invoice_hub grant anon + staff = siapa pun login (merek lain)
--   → baca nota + auto-mint QR
-- - sales UPDATE 000024 masih wajib kasir asli on-duty → board Ready/Clear
--   macet setelah shift tutup
-- - PATCH tracking/status_pembayaran bebas: skip Barang Ready, LUNAS palsu
-- - pelunasan percaya sisa/dibayar dari HP; finance "Pelunasan Kasir" belum
--   di-seal (000024 hanya "Penjualan Kasir")
-- - sales_items bisa lompat PENDING_RO → DIAMBIL
-- =============================================================================

create or replace function public.invoice_is_dp(p_pay text, p_sisa numeric)
returns boolean
language sql
immutable
as $$
  select upper(trim(coalesce(p_pay, ''))) = 'DP'
    or coalesce(p_sisa, 0) > 0;
$$;

create or replace function public.invoice_norm_track(p_track text)
returns text
language sql
immutable
as $$
  select case upper(trim(coalesce(p_track, '')))
    when 'CLEAR' then 'SIAP_DIAMBIL'
    when '' then 'PENDING_PO'
    else upper(trim(coalesce(p_track, '')))
  end;
$$;

create or replace function public.invoice_is_cancelled(p_track text, p_pay text)
returns boolean
language sql
immutable
as $$
  select upper(trim(coalesce(p_track, ''))) in ('BATAL', 'BATAL_VOUCHER', 'CANCELLED')
    or upper(trim(coalesce(p_pay, ''))) = 'BATAL';
$$;

create or replace function public.invoice_norm_line(p_status text)
returns text
language sql
immutable
as $$
  select case upper(trim(coalesce(p_status, 'READY')))
    when 'PENDING_RO' then 'PENDING_RO'
    when 'PENDING' then 'PENDING_RO'
    when 'DIAMBIL' then 'DIAMBIL'
    else 'READY'
  end;
$$;

create or replace function public.invoice_line_status_ok(p_old text, p_new text)
returns boolean
language sql
immutable
as $$
  select
    case
      when public.invoice_norm_line(p_old) = public.invoice_norm_line(p_new)
        then true
      when public.invoice_norm_line(p_old) = 'PENDING_RO'
        and public.invoice_norm_line(p_new) = 'READY' then true
      when public.invoice_norm_line(p_old) = 'READY'
        and public.invoice_norm_line(p_new) in ('PENDING_RO', 'DIAMBIL') then true
      when public.invoice_norm_line(p_old) = 'DIAMBIL'
        and public.invoice_norm_line(p_new) = 'READY' then true
      else false
    end;
$$;

create or replace function public.invoice_tracking_ok(
  p_old text,
  p_new text,
  p_was_dp boolean,
  p_now_dp boolean,
  p_pay text
)
returns boolean
language sql
immutable
as $$
  select
    case
      when public.invoice_is_cancelled(p_old, p_pay)
        or public.invoice_is_cancelled(p_new, p_pay) then true
      when public.invoice_norm_track(p_old) = public.invoice_norm_track(p_new)
        then true
      when coalesce(p_now_dp, false) then
        public.invoice_norm_track(p_old) in ('PENDING_PO', 'SIAP_PELUNASAN')
        and public.invoice_norm_track(p_new) in ('PENDING_PO', 'SIAP_PELUNASAN')
      when coalesce(p_was_dp, false) and not coalesce(p_now_dp, false) then
        (
          public.invoice_norm_track(p_old) = 'SIAP_PELUNASAN'
          and public.invoice_norm_track(p_new) in ('SIAP_DIAMBIL', 'PENDING_PO')
        )
        or (
          public.invoice_norm_track(p_old) = 'PENDING_PO'
          and public.invoice_norm_track(p_new) = 'PENDING_PO'
        )
      when public.invoice_norm_track(p_old) = 'PENDING_PO'
        and public.invoice_norm_track(p_new) = 'SIAP_DIAMBIL' then true
      when public.invoice_norm_track(p_old) = 'SIAP_DIAMBIL'
        and public.invoice_norm_track(p_new) in ('PENDING_PO', 'DIAMBIL') then true
      when public.invoice_norm_track(p_old) = 'DIAMBIL'
        and public.invoice_norm_track(p_new) = 'SIAP_DIAMBIL' then true
      when public.invoice_norm_track(p_old) = 'SIAP_PELUNASAN'
        and public.invoice_norm_track(p_new) = 'SIAP_DIAMBIL' then true
      else false
    end;
$$;

create or replace function public.invoice_finance_credited(p_sale public.sales)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(f.nominal), 0)::bigint
  from public.finance_transactions f
  where f.tenant_id is not distinct from p_sale.tenant_id
    and public.same_store_toko(f.toko_id, p_sale.toko_id)
    and upper(trim(coalesce(f.kategori, ''))) in (
      'PENJUALAN KASIR', 'PELUNASAN KASIR'
    )
    and (
      f.referensi_id = p_sale.no_invoice
      or f.referensi_id like ('SETTLE-' || p_sale.no_invoice || '-%')
    );
$$;

create or replace function public.invoice_can_staff_hub(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_platform_user()
    or public.can_pos_checkout_for_toko(p_toko)
    or exists (
      select 1
      from public.karyawan k
      where k.id = public.current_karyawan_id()
        and coalesce(k.status_approval, '') = 'Aktif'
        and public.same_store_toko(k.toko_id, p_toko)
        and k.tenant_id is not distinct from public.current_tenant_id()
    );
$$;

comment on function public.invoice_can_staff_hub(text) is
  'Lihat hub staf: kasir toko, karyawan toko yang sama, atau platform. Bukan merek lain.';

revoke all on function public.invoice_is_dp(text, numeric) from public, anon;
revoke all on function public.invoice_norm_track(text) from public, anon;
revoke all on function public.invoice_is_cancelled(text, text) from public, anon;
revoke all on function public.invoice_norm_line(text) from public, anon;
revoke all on function public.invoice_line_status_ok(text, text) from public, anon;
revoke all on function public.invoice_tracking_ok(text, text, boolean, boolean, text)
  from public, anon;
revoke all on function public.invoice_finance_credited(public.sales) from public, anon;
revoke all on function public.invoice_can_staff_hub(text) from public, anon;
grant execute on function public.invoice_can_staff_hub(text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- sales: duty hanya checkout INSERT; UPDATE lifecycle tanpa kasir asli on-duty
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
    if not public.can_pos_checkout_for_toko(new.toko_id) then
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

  -- QR: jangan terbitkan di fase yang salah.
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

drop trigger if exists trg_sales_pos_guard on public.sales;
create trigger trg_sales_pos_guard
  before insert or update or delete on public.sales
  for each row
  execute function public.sales_pos_guard();

-- -----------------------------------------------------------------------------
-- sales_items: mesin fulfillment; update READY tidak wajib product_id ulang
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

  if auth.uid() is not null
     and not public.can_pos_checkout_for_toko(v_sale.toko_id) then
    raise exception 'Hanya kasir toko ini yang boleh menambah item nota.'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
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
      return new;
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

drop trigger if exists trg_sales_items_pos_guard on public.sales_items;
create trigger trg_sales_items_pos_guard
  before insert or update on public.sales_items
  for each row
  execute function public.sales_items_pos_guard();

-- -----------------------------------------------------------------------------
-- Finance: Pelunasan Kasir = sisa nota yang sama, toko yang sama
-- -----------------------------------------------------------------------------
create or replace function public.finance_pos_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_kat text;
  v_sisa bigint;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;
  v_kat := upper(trim(coalesce(new.kategori, '')));
  if v_kat not in ('PENJUALAN KASIR', 'PELUNASAN KASIR') then
    return new;
  end if;
  if auth.uid() is null then
    return new;
  end if;
  if not public.can_pos_checkout_for_toko(new.toko_id) then
    raise exception 'Hanya kasir toko ini yang boleh catat pemasukan POS.'
      using errcode = '42501';
  end if;
  if new.tenant_id is null then
    new.tenant_id := public.current_tenant_id();
  end if;

  select * into v_sale
  from public.sales
  where public.same_store_toko(toko_id, new.toko_id)
    and tenant_id is not distinct from public.current_tenant_id()
    and (
      no_invoice = new.referensi_id
      or new.referensi_id like ('SETTLE-' || no_invoice || '-%')
    )
  limit 1;
  if not found then
    raise exception 'Pemasukan kasir wajib nota penjualan di toko yang sama.'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.sales_items i where i.sale_id = v_sale.id
  ) then
    raise exception 'Pemasukan kasir wajib nota yang sudah ada item.'
      using errcode = '42501';
  end if;
  if coalesce(new.nominal, 0) <= 0 then
    raise exception 'Nominal pemasukan kasir wajib > 0.' using errcode = '42501';
  end if;

  if v_kat = 'PENJUALAN KASIR' then
    if coalesce(new.nominal, 0) > coalesce(v_sale.dibayarkan, 0) then
      raise exception 'Nominal buku besar tidak boleh lebih dari yang dibayar.'
        using errcode = '42501';
    end if;
  else
    v_sisa := greatest(
      coalesce(v_sale.sisa_tagihan, 0),
      greatest(0, coalesce(v_sale.total_harga, 0) - coalesce(v_sale.dibayarkan, 0))
    );
    if v_sisa <= 0
       and upper(trim(coalesce(v_sale.status_pembayaran, ''))) = 'LUNAS' then
      raise exception 'Nota ini sudah lunas.' using errcode = '42501';
    end if;
    if coalesce(new.nominal, 0) > v_sisa then
      raise exception 'Pelunasan tidak boleh lebih dari sisa tagihan.'
        using errcode = '42501';
    end if;
  end if;

  new.status_konfirmasi := coalesce(nullif(trim(new.status_konfirmasi), ''), 'APPROVED');
  return new;
end;
$$;

drop trigger if exists trg_finance_pos_guard on public.finance_transactions;
create trigger trg_finance_pos_guard
  before insert on public.finance_transactions
  for each row
  execute function public.finance_pos_guard();

-- -----------------------------------------------------------------------------
-- RPC pelunasan: nominal dari baris, bukan dari HP
-- -----------------------------------------------------------------------------
create or replace function public.settle_invoice_dp(
  p_sale_id uuid,
  p_metode text,
  p_staff_nik text default null,
  p_staff_nama text default null,
  p_pos_payment_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_sisa bigint;
  v_metode text := trim(coalesce(p_metode, ''));
  v_nik text := nullif(trim(coalesce(p_staff_nik, '')), '');
  v_nama text := nullif(trim(coalesce(p_staff_nama, '')), '');
  v_ready boolean;
  v_token text;
  v_pay public.pos_payments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Login kasir dulu.' using errcode = '42501';
  end if;
  if v_metode = '' then
    raise exception 'Metode pembayaran wajib.' using errcode = '42501';
  end if;

  select * into v_sale
  from public.sales
  where id = p_sale_id
  for update;
  if not found then
    raise exception 'Transaksi tidak ditemukan.' using errcode = '42501';
  end if;
  if v_sale.tenant_id is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    raise exception 'Nota bukan milik usaha ini.' using errcode = '42501';
  end if;
  if coalesce(v_sale.channel, '') = 'member_online'
     or v_sale.online_order_id is not null then
    raise exception 'Nota online bukan board kasir DP/PENDING/READY/CLEAR.'
      using errcode = '42501';
  end if;
  if not public.can_pos_checkout_for_toko(v_sale.toko_id) then
    raise exception 'Hanya kasir toko ini yang boleh lunasi DP.'
      using errcode = '42501';
  end if;

  v_sisa := greatest(
    coalesce(v_sale.sisa_tagihan, 0),
    greatest(0, coalesce(v_sale.total_harga, 0) - coalesce(v_sale.dibayarkan, 0))
  );
  if v_sisa <= 0
     and upper(trim(coalesce(v_sale.status_pembayaran, ''))) <> 'DP' then
    raise exception 'Nota ini bukan DP / tidak ada sisa tagihan.'
      using errcode = '42501';
  end if;
  if v_sisa <= 0 then
    raise exception 'Tidak ada sisa tagihan untuk dilunasi.' using errcode = '42501';
  end if;

  if p_pos_payment_id is not null then
    select * into v_pay
    from public.pos_payments
    where id = p_pos_payment_id
      and sale_id = v_sale.id
      and tenant_id is not distinct from v_sale.tenant_id
      and lower(trim(purpose)) = 'pelunasan'
    limit 1;
    if not found or lower(trim(coalesce(v_pay.status, ''))) <> 'paid' then
      raise exception 'Pembayaran gateway pelunasan belum lunas.'
        using errcode = '42501';
    end if;
    if coalesce(v_pay.amount_idr, 0) <> v_sisa then
      raise exception 'Nominal gateway harus sama dengan sisa tagihan.'
        using errcode = '42501';
    end if;
  end if;

  insert into public.finance_transactions (
    tenant_id,
    toko_id,
    tanggal_transaksi,
    jenis_transaksi,
    kategori,
    deskripsi,
    nominal,
    status_pembayaran,
    metode_pembayaran,
    nama_kasir,
    status_konfirmasi,
    referensi_id,
    updated_at
  ) values (
    v_sale.tenant_id,
    v_sale.toko_id,
    (timezone('Asia/Jakarta', now()))::date,
    'PEMASUKAN',
    'Pelunasan Kasir',
    'Pelunasan ' || v_sale.no_invoice || ' · '
      || coalesce(v_sale.nama_pelanggan, '') || ' · oleh '
      || coalesce(v_nama, 'kasir') || ' (' || coalesce(v_nik, '-') || ')',
    v_sisa,
    'LUNAS',
    v_metode,
    v_nama,
    'APPROVED',
    v_sale.no_invoice,
    now()
  );

  v_ready := upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN';
  if v_ready then
    v_token := encode(extensions.gen_random_bytes(16), 'hex');
  end if;

  update public.sales
  set
    status_pembayaran = 'LUNAS',
    dibayarkan = coalesce(v_sale.total_harga, coalesce(v_sale.dibayarkan, 0) + v_sisa),
    sisa_tagihan = 0,
    tracking_status = case when v_ready then 'SIAP_DIAMBIL' else 'PENDING_PO' end,
    metode_pembayaran = v_metode,
    lunas_at = now(),
    qr_dp_used_at = now(),
    qr_dp_used_by = v_nik,
    qr_lunas_token = case when v_ready then v_token else qr_lunas_token end,
    qr_lunas_used_at = case when v_ready then null else qr_lunas_used_at end,
    qr_lunas_used_by = case when v_ready then null else qr_lunas_used_by end
  where id = v_sale.id;

  select * into v_sale from public.sales where id = p_sale_id;
  return to_jsonb(v_sale);
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC Barang Ready: line PENDING_RO → READY + fase board + token
-- -----------------------------------------------------------------------------
create or replace function public.mark_invoice_goods_ready(
  p_sale_id uuid,
  p_staff_nik text default null,
  p_staff_nama text default null,
  p_item_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_dp boolean;
  v_token text;
  v_existing text;
  v_all_taken boolean;
begin
  if auth.uid() is null then
    raise exception 'Login kasir dulu.' using errcode = '42501';
  end if;

  select * into v_sale
  from public.sales
  where id = p_sale_id
  for update;
  if not found then
    raise exception 'Transaksi tidak ditemukan.' using errcode = '42501';
  end if;
  if v_sale.tenant_id is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    raise exception 'Nota bukan milik usaha ini.' using errcode = '42501';
  end if;
  if coalesce(v_sale.channel, '') = 'member_online'
     or v_sale.online_order_id is not null then
    raise exception 'Nota online bukan board kasir DP/PENDING/READY/CLEAR.'
      using errcode = '42501';
  end if;
  if not public.can_pos_checkout_for_toko(v_sale.toko_id) then
    raise exception 'Hanya kasir toko ini yang boleh tandai Barang Ready.'
      using errcode = '42501';
  end if;

  select not exists (
    select 1
    from public.sales_items i
    where i.sale_id = v_sale.id
      and public.invoice_norm_line(i.fulfillment_status) <> 'DIAMBIL'
  ) and exists (
    select 1 from public.sales_items i where i.sale_id = v_sale.id
  ) into v_all_taken;
  if v_all_taken then
    raise exception 'Barang sudah diambil. Tidak perlu konfirmasi ready.'
      using errcode = '42501';
  end if;

  update public.sales_items
  set
    fulfillment_status = 'READY',
    needs_fulfillment = false
  where sale_id = v_sale.id
    and public.invoice_norm_line(fulfillment_status) = 'PENDING_RO'
    and (
      p_item_ids is null
      or cardinality(p_item_ids) = 0
      or id = any (p_item_ids)
    );

  v_dp := public.invoice_is_dp(v_sale.status_pembayaran, v_sale.sisa_tagihan);

  if v_dp then
    v_existing := nullif(trim(coalesce(v_sale.qr_dp_token, '')), '');
    if upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
       and v_existing is not null
       and length(v_existing) >= 8
       and v_sale.qr_dp_used_at is null then
      v_token := v_existing;
    else
      v_token := encode(extensions.gen_random_bytes(16), 'hex');
    end if;
    update public.sales
    set
      tracking_status = 'SIAP_PELUNASAN',
      qr_dp_token = v_token,
      qr_dp_used_at = null,
      qr_dp_used_by = null
    where id = v_sale.id;
  else
    v_existing := nullif(trim(coalesce(v_sale.qr_lunas_token, '')), '');
    if v_existing is not null
       and length(v_existing) >= 8
       and v_sale.qr_lunas_used_at is null then
      v_token := v_existing;
    else
      v_token := encode(extensions.gen_random_bytes(16), 'hex');
    end if;
    update public.sales
    set
      tracking_status = 'SIAP_DIAMBIL',
      qr_lunas_token = v_token,
      qr_lunas_used_at = null,
      qr_lunas_used_by = null
    where id = v_sale.id;
  end if;

  select * into v_sale from public.sales where id = p_sale_id;
  return to_jsonb(v_sale);
end;
$$;

revoke all on function public.settle_invoice_dp(uuid, text, text, text, uuid)
  from public, anon;
grant execute on function public.settle_invoice_dp(uuid, text, text, text, uuid)
  to authenticated, service_role;

revoke all on function public.mark_invoice_goods_ready(uuid, text, text, uuid[])
  from public, anon;
grant execute on function public.mark_invoice_goods_ready(uuid, text, text, uuid[])
  to authenticated, service_role;

comment on function public.settle_invoice_dp(uuid, text, text, text, uuid) is
  'Pelunasan DP: sisa dari baris nota + jurnal Pelunasan Kasir. Bukan nominal HP.';
comment on function public.mark_invoice_goods_ready(uuid, text, text, uuid[]) is
  'Barang Ready: line PENDING_RO→READY; DP→SIAP_PELUNASAN+QR; lunas→SIAP_DIAMBIL+QR.';

-- -----------------------------------------------------------------------------
-- Hub: staf = kasir/karyawan toko nota. Anon tidak mint token.
-- Nomor nota saja + tanpa HP = kosong.
-- -----------------------------------------------------------------------------
create or replace function public.get_invoice_hub(
  p_no_invoice text,
  p_phone text default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
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
    on upper(trim(i.toko_id)) = upper(trim(v_sale.toko_id))
  left join public.invoice_settings p on upper(trim(p.toko_id)) = 'PUSAT';

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

  -- Mint hanya kasir toko nota. Anon / HP cocok / karyawan lain: token yang sudah ada.
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

revoke all on function public.get_invoice_hub(text, text, uuid) from public;
grant execute on function public.get_invoice_hub(text, text, uuid)
  to anon, authenticated, service_role;

comment on function public.get_invoice_hub(text, text, uuid) is
  'Hub nota: staf = kasir/karyawan toko. Anon wajib HP cocok. Tidak mint QR kecuali kasir.';
