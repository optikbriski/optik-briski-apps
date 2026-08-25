-- Lab E2E Karyawan: CLAIMED → Selesai = Barang Ready (PENDING_RO→READY + QR)
-- + izinkan sales_pos_guard patch goods-ready untuk staf duty (bukan kasir profiles).

-- -----------------------------------------------------------------------------
-- Helper: patch sales = Barang Ready (tracking + mint QR + foto), bukan bayar
-- -----------------------------------------------------------------------------
create or replace function public.invoice_staff_goods_ready_patch_ok(
  p_old public.sales,
  p_new public.sales
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
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
    -- Tracking hanya ke fase ready (bukan DIAMBIL serah terima)
    and public.invoice_norm_track(p_new.tracking_status) in (
      'SIAP_PELUNASAN', 'SIAP_DIAMBIL', 'PENDING_PO'
    )
    -- Jangan paksa diambil_at dari jalur ready
    and p_old.diambil_at is not distinct from p_new.diambil_at;
$$;

comment on function public.invoice_staff_goods_ready_patch_ok(public.sales, public.sales) is
  'True jika UPDATE sales = Barang Ready (tracking/QR/foto), bukan ubah bayar/kasir/diambil.';

revoke all on function public.invoice_staff_goods_ready_patch_ok(public.sales, public.sales)
  from public, anon;
grant execute on function public.invoice_staff_goods_ready_patch_ok(public.sales, public.sales)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- sales_pos_guard: staf duty boleh handover ATAU goods-ready patch
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
      null;
    elsif tg_op = 'UPDATE'
       and public.invoice_can_staff_hub(new.toko_id) then
      v_kid := public.current_karyawan_id();
      if v_kid is null or not public.pos_duty_ok(v_kid, new.toko_id) then
        raise exception
          'Hanya karyawan aktif yang sudah absen masuk (shift OPEN) yang boleh update nota.'
          using errcode = '42501';
      end if;
      if not (
        public.invoice_staff_handover_patch_ok(old, new)
        or public.invoice_staff_goods_ready_patch_ok(old, new)
      ) then
        raise exception
          'Karyawan hanya boleh serah terima / Barang Ready (bukan ubah bayar/kasir/nota).'
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
-- complete_lab_job: claimer Back + duty → READY + tracking/QR (poin via trigger)
-- -----------------------------------------------------------------------------
create or replace function public.complete_lab_job(
  p_job_id uuid,
  p_item_ids uuid[] default null,
  p_foto_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kid uuid;
  v_k public.karyawan%rowtype;
  v_job public.lab_jobs%rowtype;
  v_sale public.sales%rowtype;
  v_dp boolean;
  v_token text;
  v_existing text;
  v_all_taken boolean;
  v_pending_before int;
  v_ready_after int;
  v_foto text := nullif(trim(coalesce(p_foto_url, '')), '');
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_job_id is null then
    return jsonb_build_object('ok', false, 'error', 'Job lab kosong');
  end if;

  v_kid := public.current_karyawan_id();
  if v_kid is null then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;

  select * into v_k from public.karyawan where id = v_kid;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;

  if lower(trim(coalesce(v_k.status_approval, ''))) not in ('aktif', 'active', 'approved') then
    return jsonb_build_object('ok', false, 'error', 'Karyawan tidak aktif');
  end if;

  if not public.is_back_office_jabatan(v_k.jabatan) then
    return jsonb_build_object('ok', false, 'error', 'Hanya Backliner yang bisa selesaikan job lab');
  end if;

  select * into v_job from public.lab_jobs where id = p_job_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Job lab tidak ditemukan');
  end if;

  if not public.same_store_toko(v_k.toko_id, v_job.toko_id) then
    return jsonb_build_object('ok', false, 'error', 'Beda cabang');
  end if;

  if not public.pos_duty_ok(v_kid, v_job.toko_id) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Absen masuk dulu (shift OPEN) sebelum selesaikan lab'
    );
  end if;

  if upper(trim(coalesce(v_job.status, ''))) = 'DONE' then
    select * into v_sale from public.sales where id = v_job.sale_id;
    return jsonb_build_object(
      'ok', true,
      'already', true,
      'job_id', v_job.id,
      'sale_id', v_job.sale_id,
      'no_invoice', v_job.no_invoice,
      'status', 'DONE',
      'tracking_status', v_sale.tracking_status,
      'nama', v_k.nama
    );
  end if;

  if upper(trim(coalesce(v_job.status, ''))) <> 'CLAIMED'
     or v_job.claimed_by is distinct from v_kid then
    return jsonb_build_object(
      'ok', false,
      'error', 'Hanya claimer job ini yang boleh menandai selesai'
    );
  end if;

  select * into v_sale
  from public.sales
  where id = v_job.sale_id
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Nota tidak ditemukan');
  end if;

  if v_sale.tenant_id is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
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
    return jsonb_build_object('ok', false, 'error', 'Barang sudah diambil — tidak perlu ready');
  end if;

  select count(*)::int into v_pending_before
  from public.sales_items i
  where i.sale_id = v_sale.id
    and public.invoice_norm_line(i.fulfillment_status) = 'PENDING_RO';

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

  get diagnostics v_ready_after = row_count;

  if v_pending_before > 0 and v_ready_after = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'Tidak ada item PENDING_RO yang diubah jadi READY'
    );
  end if;

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
      qr_dp_used_by = null,
      foto_hasil_url = coalesce(v_foto, foto_hasil_url)
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
      qr_lunas_used_by = null,
      foto_hasil_url = coalesce(v_foto, foto_hasil_url)
    where id = v_sale.id;
  end if;

  -- Pastikan DONE + poin LAB meski line sudah READY sebelumnya / partial update.
  perform public.try_award_lab_poin(v_sale.id);

  select * into v_job from public.lab_jobs where id = p_job_id;
  select * into v_sale from public.sales where id = v_sale.id;

  -- Jika masih ada PENDING_RO (partial item_ids), biarkan CLAIMED; else pastikan DONE.
  if upper(trim(coalesce(v_job.status, ''))) <> 'DONE' then
    if not exists (
      select 1 from public.sales_items i
      where i.sale_id = v_sale.id
        and public.invoice_norm_line(i.fulfillment_status) = 'PENDING_RO'
    ) then
      update public.lab_jobs
         set status = 'DONE'
       where id = p_job_id
      returning * into v_job;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'already', false,
    'job_id', v_job.id,
    'sale_id', v_sale.id,
    'no_invoice', v_sale.no_invoice,
    'status', v_job.status,
    'tracking_status', v_sale.tracking_status,
    'lines_ready', v_ready_after,
    'is_dp', v_dp,
    'nama', v_k.nama,
    'unit_qty', v_job.unit_qty
  );
end;
$$;

revoke all on function public.complete_lab_job(uuid, uuid[], text) from public;
grant execute on function public.complete_lab_job(uuid, uuid[], text) to authenticated;

comment on function public.complete_lab_job(uuid, uuid[], text) is
  'Backliner claimer + shift OPEN: PENDING_RO→READY, mint QR, poin LAB via trigger.';
