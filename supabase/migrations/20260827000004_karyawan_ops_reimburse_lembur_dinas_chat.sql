-- Karyawan ops: dinas luar, ajukan lembur, reimburse, chat toko.
-- Libur nasional tidak ada — hanya lebaran + 1 hari libur/minggu (roster).

-- -----------------------------------------------------------------------------
-- 1. Dinas luar = tipe baru di jadwal_pengajuan (tidak mengubah roster jadi libur)
-- -----------------------------------------------------------------------------
alter table public.jadwal_pengajuan
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists foto_url text;

alter table public.jadwal_pengajuan drop constraint if exists jadwal_pengajuan_tipe_check;
alter table public.jadwal_pengajuan
  add constraint jadwal_pengajuan_tipe_check
  check (tipe in ('IJIN', 'CUTI', 'TUKAR', 'DINAS'));

create or replace function public.apply_approved_jadwal_pengajuan(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jadwal_pengajuan%rowtype;
  v_tipe text;
  v_a date;
  v_b date;
  v_jadwal_a public.jadwal_kerja%rowtype;
  v_jadwal_b public.jadwal_kerja%rowtype;
  v_a_libur boolean;
  v_b_libur boolean;
begin
  select * into v_j from public.jadwal_pengajuan where id = p_id;
  if v_j.id is null then
    raise exception 'Pengajuan jadwal tidak ditemukan.';
  end if;

  v_tipe := upper(trim(coalesce(v_j.tipe, '')));
  v_a := v_j.tanggal;
  v_b := coalesce(v_j.tanggal_tukar, v_j.tanggal);

  if v_tipe = 'DINAS' then
    return;
  end if;

  if v_tipe in ('IJIN', 'CUTI') then
    insert into public.jadwal_kerja as jk (
      karyawan_id, toko_id, tanggal, jam_masuk, jam_pulang, is_libur, catatan
    ) values (
      v_j.karyawan_id, v_j.toko_id, v_a, null, null, true,
      left(v_tipe || ' disetujui: ' || coalesce(v_j.alasan, ''), 500)
    )
    on conflict (karyawan_id, tanggal) do update set
      toko_id = excluded.toko_id,
      jam_masuk = null,
      jam_pulang = null,
      is_libur = true,
      catatan = excluded.catatan;
  elsif v_tipe = 'TUKAR' then
    if v_j.partner_karyawan_id is null then
      raise exception 'Partner tukar tidak ada.';
    end if;

    select * into v_jadwal_a
    from public.jadwal_kerja
    where karyawan_id = v_j.karyawan_id and tanggal = v_a;
    select * into v_jadwal_b
    from public.jadwal_kerja
    where karyawan_id = v_j.partner_karyawan_id and tanggal = v_b;

    v_a_libur := coalesce(v_jadwal_a.is_libur, true) or v_jadwal_a.karyawan_id is null;
    v_b_libur := coalesce(v_jadwal_b.is_libur, true) or v_jadwal_b.karyawan_id is null;

    insert into public.jadwal_kerja as jk (
      karyawan_id, toko_id, tanggal, jam_masuk, jam_pulang, is_libur, catatan
    ) values (
      v_j.karyawan_id, v_j.toko_id, v_a,
      case when v_b_libur then null else v_jadwal_b.jam_masuk end,
      case when v_b_libur then null else v_jadwal_b.jam_pulang end,
      v_b_libur,
      'Hasil tukar jadwal dengan partner'
    )
    on conflict (karyawan_id, tanggal) do update set
      toko_id = excluded.toko_id,
      jam_masuk = excluded.jam_masuk,
      jam_pulang = excluded.jam_pulang,
      is_libur = excluded.is_libur,
      catatan = excluded.catatan;

    insert into public.jadwal_kerja as jk (
      karyawan_id, toko_id, tanggal, jam_masuk, jam_pulang, is_libur, catatan
    ) values (
      v_j.partner_karyawan_id, v_j.toko_id, v_b,
      case when v_a_libur then null else v_jadwal_a.jam_masuk end,
      case when v_a_libur then null else v_jadwal_a.jam_pulang end,
      v_a_libur,
      'Hasil tukar jadwal dengan partner'
    )
    on conflict (karyawan_id, tanggal) do update set
      toko_id = excluded.toko_id,
      jam_masuk = excluded.jam_masuk,
      jam_pulang = excluded.jam_pulang,
      is_libur = excluded.is_libur,
      catatan = excluded.catatan;
  else
    raise exception 'Tipe pengajuan tidak dikenal: %', v_tipe;
  end if;
end;
$$;

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

-- -----------------------------------------------------------------------------
-- 2. Lembur: karyawan draft → admin approve
-- -----------------------------------------------------------------------------
alter table public.payroll_overtime_entries
  drop constraint if exists payroll_overtime_entries_status_check;
alter table public.payroll_overtime_entries
  add constraint payroll_overtime_entries_status_check
  check (status in ('draft', 'approved', 'rejected'));

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

drop policy if exists payroll_ot_karyawan_delete on public.payroll_overtime_entries;
create policy payroll_ot_karyawan_delete on public.payroll_overtime_entries
  for delete to authenticated
  using (
    public.jadwal_is_self_karyawan(karyawan_id)
    and status = 'draft'
  );

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

revoke all on function public.decide_payroll_overtime(uuid, boolean, bigint, text) from public;
grant execute on function public.decide_payroll_overtime(uuid, boolean, bigint, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Reimburse
-- -----------------------------------------------------------------------------
create table if not exists public.karyawan_reimburse (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text not null references public.toko_id (id) on delete cascade,
  kategori text not null default 'Lainnya',
  jumlah_rp bigint not null check (jumlah_rp > 0),
  catatan text not null,
  foto_url text,
  status text not null default 'OPEN'
    check (status in ('OPEN', 'APPROVED', 'REJECTED')),
  balasan text,
  diputus_at timestamptz,
  diputus_oleh text,
  created_at timestamptz not null default now()
);

create index if not exists karyawan_reimburse_toko_idx
  on public.karyawan_reimburse (toko_id, status, created_at desc);
create index if not exists karyawan_reimburse_karyawan_idx
  on public.karyawan_reimburse (karyawan_id, created_at desc);

alter table public.karyawan_reimburse enable row level security;

drop policy if exists karyawan_reimburse_select on public.karyawan_reimburse;
create policy karyawan_reimburse_select on public.karyawan_reimburse
  for select to authenticated
  using (
    public.jadwal_is_self_karyawan(karyawan_id)
    or public.can_manage_jadwal_for_toko(toko_id)
  );

drop policy if exists karyawan_reimburse_insert on public.karyawan_reimburse;
create policy karyawan_reimburse_insert on public.karyawan_reimburse
  for insert to authenticated
  with check (
    public.jadwal_is_self_karyawan(karyawan_id)
    and status = 'OPEN'
  );

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

revoke all on function public.decide_karyawan_reimburse(uuid, boolean, text) from public;
grant execute on function public.decide_karyawan_reimburse(uuid, boolean, text) to authenticated;

grant select, insert on table public.karyawan_reimburse to authenticated;
grant all on table public.karyawan_reimburse to service_role;

-- -----------------------------------------------------------------------------
-- 4. Chat toko
-- -----------------------------------------------------------------------------
create table if not exists public.toko_chat_messages (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id) on delete cascade,
  sender_karyawan_id uuid references public.karyawan (id) on delete set null,
  sender_nama text not null,
  isi text not null,
  created_at timestamptz not null default now()
);

create index if not exists toko_chat_toko_created_idx
  on public.toko_chat_messages (toko_id, created_at desc);

alter table public.toko_chat_messages enable row level security;

drop policy if exists toko_chat_select on public.toko_chat_messages;
create policy toko_chat_select on public.toko_chat_messages
  for select to authenticated
  using (
    public.can_manage_jadwal_for_toko(toko_id)
    or exists (
      select 1 from public.karyawan k
      where public.jadwal_is_self_karyawan(k.id)
        and public.same_store_toko(k.toko_id, toko_chat_messages.toko_id)
    )
  );

drop policy if exists toko_chat_insert on public.toko_chat_messages;
create policy toko_chat_insert on public.toko_chat_messages
  for insert to authenticated
  with check (
    char_length(trim(isi)) > 0
    and char_length(isi) <= 1000
    and (
      public.can_manage_jadwal_for_toko(toko_id)
      or (
        sender_karyawan_id is not null
        and public.jadwal_is_self_karyawan(sender_karyawan_id)
        and exists (
          select 1 from public.karyawan k
          where k.id = sender_karyawan_id
            and public.same_store_toko(k.toko_id, toko_id)
        )
      )
    )
  );

grant select, insert on table public.toko_chat_messages to authenticated;
grant all on table public.toko_chat_messages to service_role;

do $$
begin
  alter publication supabase_realtime add table public.toko_chat_messages;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
