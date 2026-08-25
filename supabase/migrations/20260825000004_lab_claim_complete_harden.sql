-- Harden lab E2E: claim pakai current_karyawan_id + same_store + duty toko job;
-- complete tolak nota member_online; tracking QR hanya jika tidak ada PENDING_RO tersisa
-- (partial item tetap CLAIMED sampai semua line lab READY).

create or replace function public.claim_lab_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kid uuid;
  v_k public.karyawan%rowtype;
  v_job public.lab_jobs%rowtype;
  v_updated public.lab_jobs%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Login diperlukan';
  end if;

  v_kid := public.current_karyawan_id();
  if v_kid is null then
    raise exception 'Profil karyawan tidak ditemukan';
  end if;

  select * into v_k from public.karyawan where id = v_kid;
  if not found then
    raise exception 'Profil karyawan tidak ditemukan';
  end if;

  if lower(trim(coalesce(v_k.status_approval, ''))) not in ('aktif', 'active', 'approved') then
    raise exception 'Akun karyawan tidak aktif';
  end if;

  if not public.is_back_office_jabatan(v_k.jabatan) then
    raise exception 'Hanya Backliner / back office yang bisa claim job lab';
  end if;

  select * into v_job from public.lab_jobs where id = p_job_id for update;
  if not found then
    raise exception 'Job lab tidak ditemukan';
  end if;

  if not public.same_store_toko(v_k.toko_id, v_job.toko_id) then
    raise exception 'Job lab bukan untuk cabang Anda';
  end if;

  if not public.pos_duty_ok(v_kid, v_job.toko_id) then
    raise exception 'Belum absen masuk — tidak bisa claim job lab';
  end if;

  if exists (
    select 1 from public.jadwal_kerja j
    where j.karyawan_id = v_kid
      and j.tanggal = (timezone('Asia/Jakarta', now()))::date
      and j.is_libur is true
  ) then
    raise exception 'Sedang libur — tidak bisa claim job lab';
  end if;

  if v_job.status = 'CLAIMED' and v_job.claimed_by = v_kid then
    return jsonb_build_object(
      'ok', true,
      'job_id', v_job.id,
      'status', v_job.status,
      'claimed_by', v_job.claimed_by,
      'nama', v_k.nama,
      'already', true,
      'sale_id', v_job.sale_id,
      'no_invoice', v_job.no_invoice,
      'unit_qty', v_job.unit_qty
    );
  end if;

  if upper(trim(coalesce(v_job.status, ''))) = 'DONE' then
    raise exception 'Job lab sudah selesai';
  end if;

  update public.lab_jobs
     set status = 'CLAIMED',
         claimed_by = v_kid,
         claimed_at = now()
   where id = p_job_id
     and status = 'OPEN'
  returning * into v_updated;

  if not found then
    raise exception 'Job sudah diambil orang lain';
  end if;

  update public.sales
     set pembuat_kacamata_id = v_kid,
         nama_pembuat_kacamata = v_k.nama
   where id = v_updated.sale_id;

  return jsonb_build_object(
    'ok', true,
    'job_id', v_updated.id,
    'sale_id', v_updated.sale_id,
    'no_invoice', v_updated.no_invoice,
    'status', v_updated.status,
    'claimed_by', v_updated.claimed_by,
    'nama', v_k.nama,
    'unit_qty', v_updated.unit_qty,
    'already', false
  );
end;
$$;

revoke all on function public.claim_lab_job(uuid) from public;
grant execute on function public.claim_lab_job(uuid) to authenticated;

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
  v_pending_left int;
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

  if coalesce(v_sale.channel, '') = 'member_online'
     or v_sale.online_order_id is not null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Nota online bukan jalur lab POS — proses di Admin/online'
    );
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

  select count(*)::int into v_pending_left
  from public.sales_items i
  where i.sale_id = v_sale.id
    and public.invoice_norm_line(i.fulfillment_status) = 'PENDING_RO';

  -- Tracking + QR hanya jika tidak ada PENDING_RO tersisa (nota siap board).
  if v_pending_left = 0 then
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
  elsif v_foto is not null then
    update public.sales
    set foto_hasil_url = v_foto
    where id = v_sale.id;
  end if;

  perform public.try_award_lab_poin(v_sale.id);

  select * into v_job from public.lab_jobs where id = p_job_id;
  select * into v_sale from public.sales where id = v_sale.id;

  if upper(trim(coalesce(v_job.status, ''))) <> 'DONE' and v_pending_left = 0 then
    update public.lab_jobs
       set status = 'DONE'
     where id = p_job_id
    returning * into v_job;
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
    'pending_left', v_pending_left,
    'is_dp', coalesce(v_dp, public.invoice_is_dp(v_sale.status_pembayaran, v_sale.sisa_tagihan)),
    'nama', v_k.nama,
    'unit_qty', v_job.unit_qty
  );
end;
$$;

revoke all on function public.complete_lab_job(uuid, uuid[], text) from public;
grant execute on function public.complete_lab_job(uuid, uuid[], text) to authenticated;

comment on function public.claim_lab_job(uuid) is
  'Claim lab: current_karyawan_id + same_store + shift OPEN + back jabatan.';
comment on function public.complete_lab_job(uuid, uuid[], text) is
  'Selesai lab: PENDING_RO→READY; QR/tracking hanya jika 0 PENDING_RO; poin via try_award_lab_poin.';
