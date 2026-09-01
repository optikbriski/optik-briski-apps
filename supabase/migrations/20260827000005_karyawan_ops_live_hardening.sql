-- Harden ops 1–4 so cabang bisa running: grant, RLS admin_toko, dinas GPS,
-- notifikasi tidak menggagalkan approval, tarif lembur wajib, klaim tidak di-double.

drop policy if exists payroll_ot_select on public.payroll_overtime_entries;
create policy payroll_ot_select on public.payroll_overtime_entries
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.is_owner_provisioner()
    or public.can_manage_jadwal_for_toko(toko_id)
    or public.jadwal_is_self_karyawan(karyawan_id)
  );

drop policy if exists payroll_ot_karyawan_insert on public.payroll_overtime_entries;
create policy payroll_ot_karyawan_insert on public.payroll_overtime_entries
  for insert to authenticated
  with check (
    public.jadwal_is_self_karyawan(karyawan_id)
    and status = 'draft'
    and jam > 0
    and exists (
      select 1 from public.karyawan k
      where public.jadwal_is_self_karyawan(k.id)
        and public.same_store_toko(k.toko_id, toko_id)
    )
  );

create or replace function public.jadwal_pengajuan_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_self uuid;
  v_k_toko text;
  v_k_tenant uuid;
  v_p_toko text;
  v_p_tenant uuid;
  v_old_status text;
  v_new_status text;
begin
  if tg_op = 'DELETE' then
    if not public.is_platform_user() then
      raise exception 'Pengajuan jadwal tidak dihapus lewat REST. Batalkan saja.'
        using errcode = '42501';
    end if;
    return old;
  end if;

  v_self := public.current_karyawan_id();

  if tg_op = 'INSERT' then
    if v_self is null then
      raise exception 'Hanya karyawan usaha ini yang boleh mengajukan jadwal.'
        using errcode = '42501';
    end if;
    new.karyawan_id := v_self;
    new.status := 'PENDING';
    new.reviewer_id := null;
    new.reviewer_note := null;
    new.reviewed_at := null;

    select k.toko_id, k.tenant_id
      into v_k_toko, v_k_tenant
    from public.karyawan k
    where k.id = v_self;

    if v_k_toko is null or v_k_tenant is null then
      raise exception 'Data toko karyawan tidak lengkap.'
        using errcode = '42501';
    end if;
    new.toko_id := v_k_toko;

    new.tipe := upper(trim(coalesce(new.tipe, '')));
    if new.tipe not in ('IJIN', 'CUTI', 'TUKAR', 'DINAS') then
      raise exception 'Tipe pengajuan tidak valid.' using errcode = '42501';
    end if;
    if trim(coalesce(new.alasan, '')) = '' then
      raise exception 'Alasan wajib diisi.' using errcode = '42501';
    end if;
    new.alasan := left(trim(new.alasan), 500);

    if new.tipe = 'DINAS' then
      if new.lat is null or new.lng is null then
        raise exception 'Dinas luar wajib pin lokasi GPS.' using errcode = '42501';
      end if;
      if trim(coalesce(new.foto_url, '')) = '' then
        raise exception 'Dinas luar wajib foto bukti.' using errcode = '42501';
      end if;
    else
      new.lat := null;
      new.lng := null;
      new.foto_url := null;
    end if;

    if new.tipe = 'TUKAR' then
      if new.partner_karyawan_id is null
         or new.partner_karyawan_id = new.karyawan_id then
        raise exception 'Tukar jadwal wajib partner toko yang sama.'
          using errcode = '42501';
      end if;
      if new.tanggal_tukar is null then
        raise exception 'Tukar jadwal wajib tanggal partner.'
          using errcode = '42501';
      end if;
      select k.toko_id, k.tenant_id
        into v_p_toko, v_p_tenant
      from public.karyawan k
      where k.id = new.partner_karyawan_id;
      if not found
         or v_p_tenant is distinct from v_k_tenant
         or not public.same_store_toko(v_p_toko, v_k_toko) then
        raise exception 'Partner tukar harus karyawan toko/usaha yang sama.'
          using errcode = '42501';
      end if;
    else
      new.partner_karyawan_id := null;
      new.tanggal_tukar := null;
    end if;

    return new;
  end if;

  new.karyawan_id := old.karyawan_id;
  new.toko_id := old.toko_id;
  new.tipe := old.tipe;
  new.tanggal := old.tanggal;
  new.tanggal_tukar := old.tanggal_tukar;
  new.partner_karyawan_id := old.partner_karyawan_id;
  new.alasan := old.alasan;
  new.lat := old.lat;
  new.lng := old.lng;
  new.foto_url := old.foto_url;
  new.created_at := old.created_at;

  v_old_status := upper(trim(coalesce(old.status, '')));
  v_new_status := upper(trim(coalesce(new.status, '')));
  new.status := v_new_status;

  if v_new_status is not distinct from v_old_status then
    new.reviewer_id := old.reviewer_id;
    new.reviewer_note := old.reviewer_note;
    new.reviewed_at := old.reviewed_at;
    return new;
  end if;

  if v_old_status <> 'PENDING' then
    raise exception 'Pengajuan yang sudah diproses tidak bisa diubah.'
      using errcode = '42501';
  end if;

  if v_new_status = 'CANCELLED' then
    if not public.jadwal_is_self_karyawan(old.karyawan_id) then
      raise exception 'Hanya pengaju yang boleh membatalkan.'
        using errcode = '42501';
    end if;
    new.reviewer_id := null;
    new.reviewer_note := null;
    new.reviewed_at := now();
    return new;
  end if;

  if v_new_status in ('APPROVED', 'REJECTED') then
    if public.jadwal_is_self_karyawan(old.karyawan_id)
       and not public.is_platform_user() then
      raise exception 'Tidak boleh menyetujui atau menolak pengajuan sendiri.'
        using errcode = '42501';
    end if;
    if not public.jadwal_pengajuan_case_ok(old.toko_id, old.karyawan_id) then
      raise exception 'Hanya admin toko/cabang yang berhak memutus pengajuan.'
        using errcode = '42501';
    end if;
    new.reviewer_id := auth.uid();
    new.reviewed_at := coalesce(new.reviewed_at, now());
    if new.reviewer_note is not null then
      new.reviewer_note := left(trim(new.reviewer_note), 500);
    end if;
    return new;
  end if;

  raise exception
    'Alur pengajuan: PENDING → APPROVED / REJECTED / CANCELLED.'
    using errcode = '42501';
end;
$$;

create or replace function public.decide_payroll_overtime(
  p_id uuid,
  p_approve boolean,
  p_rate_rp bigint default 0,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payroll_overtime_entries%rowtype;
  v_rate bigint;
  v_jumlah bigint;
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Harus login.';
  end if;

  select * into v_row from public.payroll_overtime_entries where id = p_id for update;
  if v_row.id is null then
    raise exception 'Pengajuan lembur tidak ditemukan.';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'Lembur ini sudah diproses.';
  end if;
  if not public.can_manage_jadwal_for_toko(v_row.toko_id) then
    raise exception 'Tidak berhak memutus lembur toko ini.';
  end if;

  if p_approve then
    v_rate := greatest(coalesce(p_rate_rp, 0), 0);
    if v_rate <= 0 then
      v_rate := greatest(coalesce(v_row.rate_rp, 0), 0);
    end if;
    if v_rate <= 0 then
      raise exception 'Tarif lembur per jam wajib diisi.';
    end if;
    v_jumlah := round(v_row.jam * v_rate)::bigint;
    update public.payroll_overtime_entries set
      status = 'approved',
      rate_rp = v_rate,
      jumlah_rp = v_jumlah,
      meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
        'reviewer_note', left(trim(coalesce(p_note, '')), 500)
      ),
      updated_at = now()
    where id = p_id;
  else
    update public.payroll_overtime_entries set
      status = 'rejected',
      meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
        'reviewer_note', left(trim(coalesce(p_note, '')), 500)
      ),
      updated_at = now()
    where id = p_id;
  end if;

  begin
    insert into public.notifikasi (user_id, judul, isi, tipe)
    select u.id,
      case when p_approve then 'Lembur disetujui' else 'Lembur ditolak' end,
      case when p_approve
        then 'Pengajuan lembur ' || v_row.jam::text || ' jam disetujui.'
        else 'Pengajuan lembur ditolak.'
      end,
      'ADMIN'
    from public.karyawan k
    join auth.users u on u.id = k.id
    where k.id = v_row.karyawan_id
    limit 1;
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.decide_karyawan_reimburse(
  p_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.karyawan_reimburse%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Harus login.';
  end if;
  select * into v_row from public.karyawan_reimburse where id = p_id for update;
  if v_row.id is null then
    raise exception 'Klaim tidak ditemukan.';
  end if;
  if v_row.status <> 'OPEN' then
    raise exception 'Klaim ini sudah diproses.';
  end if;
  if not public.can_manage_jadwal_for_toko(v_row.toko_id) then
    raise exception 'Tidak berhak memutus klaim toko ini.';
  end if;

  update public.karyawan_reimburse set
    status = case when p_approve then 'APPROVED' else 'REJECTED' end,
    balasan = nullif(left(trim(coalesce(p_note, '')), 500), ''),
    diputus_at = now(),
    diputus_oleh = coalesce(auth.jwt() ->> 'email', auth.uid()::text)
  where id = p_id
    and status = 'OPEN';

  begin
    insert into public.notifikasi (user_id, judul, isi, tipe)
    select u.id,
      case when p_approve then 'Reimburse disetujui' else 'Reimburse ditolak' end,
      left(coalesce(p_note, 'Klaim biaya ' || v_row.kategori), 280),
      'ADMIN'
    from public.karyawan k
    join auth.users u on u.id = k.id
    where k.id = v_row.karyawan_id
    limit 1;
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true);
end;
$$;

grant select, insert on table public.karyawan_reimburse to authenticated;
grant all on table public.karyawan_reimburse to service_role;
grant select, insert on table public.toko_chat_messages to authenticated;
grant all on table public.toko_chat_messages to service_role;

do $$
begin
  alter publication supabase_realtime add table public.toko_chat_messages;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
