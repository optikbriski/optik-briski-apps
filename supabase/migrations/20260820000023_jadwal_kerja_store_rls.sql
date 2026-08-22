-- =============================================================================
-- 000023 — Jadwal kerja end-to-end.
-- Apply di SQL Editor live SETELAH 000022.
--
-- Celah saat toko jalan:
-- - jadwal_kerja_scoped FOR ALL: karyawan_id = auth.uid() → karyawan bisa
--   tulis shift sendiri (libur → masuk, jam_masuk digeser) lalu lolos absen.
-- - can_open_store_kiosk ikut WITH CHECK → APK toko bisa ubah roster.
-- - jadwal_pengajuan_auth_all using(true) → siapa pun login (merek lain)
--   bisa approve ijin sendiri / baca alasan cuti usaha lain.
-- - toko_shift_settings_auth_all using(true) → siapa pun ubah kuota/jam
--   cabang merek lain.
-- =============================================================================

create or replace function public.jadwal_is_self_karyawan(p_karyawan uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_karyawan is not null
    and (
      p_karyawan = auth.uid()
      or exists (
        select 1
        from public.karyawan k
        where k.id = p_karyawan
          and k.email is not null
          and k.email = (auth.jwt() ->> 'email')
          and k.tenant_id is not null
          and k.tenant_id is not distinct from public.current_tenant_id()
      )
    );
$$;

comment on function public.jadwal_is_self_karyawan(uuid) is
  'Baris jadwal milik akun ini (id atau email) di usaha sesi. Bukan merek lain.';

revoke all on function public.jadwal_is_self_karyawan(uuid)
  from public, anon;
grant execute on function public.jadwal_is_self_karyawan(uuid)
  to authenticated, service_role;

create or replace function public.current_karyawan_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select k.id
  from public.karyawan k
  where k.tenant_id is not null
    and k.tenant_id is not distinct from public.current_tenant_id()
    and (
      k.id = auth.uid()
      or (k.email is not null and k.email = (auth.jwt() ->> 'email'))
    )
  order by case when k.id = auth.uid() then 0 else 1 end
  limit 1;
$$;

comment on function public.current_karyawan_id() is
  'Karyawan sesi di usaha terikat. Kosong = bukan staf usaha ini.';

revoke all on function public.current_karyawan_id() from public, anon;
grant execute on function public.current_karyawan_id()
  to authenticated, service_role;

-- Sama pola geofence: admin_pusat boleh roster Pusat (bukan monitor absensi).
create or replace function public.can_manage_jadwal_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.toko_belongs_to_current_tenant(p_toko)
    and (
      public.is_platform_user()
      or public.current_profile_role() in ('owner', 'super_admin', 'admin_pusat')
      or (
        public.current_profile_role() = 'admin_toko'
        and public.same_store_toko(public.current_profile_toko_id(), p_toko)
      )
    );
$$;

comment on function public.can_manage_jadwal_for_toko(text) is
  'Ubah roster/kuota: pusat semua toko tenant; admin_toko toko sendiri. Bukan karyawan.';

revoke all on function public.can_manage_jadwal_for_toko(text)
  from public, anon;
grant execute on function public.can_manage_jadwal_for_toko(text)
  to authenticated, service_role;

create or replace function public.jadwal_pengajuan_case_ok(
  p_toko text,
  p_karyawan uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.can_manage_jadwal_for_toko(p_toko)
    and exists (
      select 1
      from public.karyawan k
      where k.id = p_karyawan
        and k.tenant_id is not null
        and k.tenant_id is not distinct from public.current_tenant_id()
        and public.same_store_toko(k.toko_id, p_toko)
    );
$$;

comment on function public.jadwal_pengajuan_case_ok(text, uuid) is
  'Setujui/tolak ijin: admin toko itu + karyawan toko/usaha yang sama.';

revoke all on function public.jadwal_pengajuan_case_ok(text, uuid)
  from public, anon;
grant execute on function public.jadwal_pengajuan_case_ok(text, uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- jadwal_kerja — baca sendiri / kiosk / admin; tulis hanya admin toko itu
-- -----------------------------------------------------------------------------
create or replace function public.jadwal_kerja_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_k_toko text;
  v_k_tenant uuid;
begin
  if tg_op = 'DELETE' then
    if not public.can_manage_jadwal_for_toko(old.toko_id)
       and not public.is_platform_user() then
      raise exception 'Hanya admin toko/cabang yang boleh hapus jadwal kerja.'
        using errcode = '42501';
    end if;
    return old;
  end if;

  select k.toko_id, k.tenant_id
    into v_k_toko, v_k_tenant
  from public.karyawan k
  where k.id = new.karyawan_id;

  if not found or v_k_tenant is null then
    raise exception 'Karyawan jadwal tidak valid.'
      using errcode = '42501';
  end if;

  if v_k_tenant is distinct from public.current_tenant_id()
     and not public.is_platform_user() then
    raise exception 'Jadwal kerja hanya untuk usaha ini.'
      using errcode = '42501';
  end if;

  if not public.same_store_toko(v_k_toko, new.toko_id) then
    raise exception 'Jadwal kerja hanya untuk toko karyawan.'
      using errcode = '42501';
  end if;

  if not public.toko_belongs_to_current_tenant(new.toko_id)
     and not public.is_platform_user() then
    raise exception 'Toko jadwal bukan milik usaha ini.'
      using errcode = '42501';
  end if;

  if not public.can_manage_jadwal_for_toko(new.toko_id)
     and not public.is_platform_user() then
    raise exception 'Hanya admin toko/cabang yang boleh mengubah jadwal kerja.'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    if old.karyawan_id is distinct from new.karyawan_id then
      raise exception 'karyawan_id jadwal tidak boleh diganti'
        using errcode = '42501';
    end if;
    if not public.same_store_toko(old.toko_id, new.toko_id) then
      raise exception 'toko_id jadwal tidak boleh dipindah'
        using errcode = '42501';
    end if;
  end if;

  if coalesce(new.is_libur, false) then
    new.is_libur := true;
    new.jam_masuk := null;
    new.jam_pulang := null;
  else
    new.is_libur := false;
    if new.jam_masuk is null or new.jam_pulang is null then
      raise exception 'Hari kerja wajib jam masuk dan jam pulang.'
        using errcode = '42501';
    end if;
  end if;

  if new.catatan is not null then
    new.catatan := left(trim(new.catatan), 500);
    if new.catatan = '' then
      new.catatan := null;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.jadwal_kerja_guard() is
  'Roster: admin toko itu, karyawan+toko+usaha cocok, libur tanpa jam.';

drop trigger if exists trg_jadwal_kerja_guard on public.jadwal_kerja;
create trigger trg_jadwal_kerja_guard
  before insert or update or delete on public.jadwal_kerja
  for each row
  execute function public.jadwal_kerja_guard();

drop policy if exists jadwal_kerja_auth_all on public.jadwal_kerja;
drop policy if exists jadwal_kerja_scoped on public.jadwal_kerja;
drop policy if exists jadwal_kerja_tenant_seal on public.jadwal_kerja;
drop policy if exists jadwal_kerja_select on public.jadwal_kerja;
drop policy if exists jadwal_kerja_insert on public.jadwal_kerja;
drop policy if exists jadwal_kerja_update on public.jadwal_kerja;
drop policy if exists jadwal_kerja_delete on public.jadwal_kerja;

create policy jadwal_kerja_select on public.jadwal_kerja
  for select to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      public.jadwal_is_self_karyawan(karyawan_id)
      or public.can_manage_jadwal_for_toko(toko_id)
      or public.can_monitor_attendance_for_toko(toko_id)
      or public.can_open_store_kiosk_for_toko(toko_id)
    )
  );

create policy jadwal_kerja_insert on public.jadwal_kerja
  for insert to authenticated
  with check (public.can_manage_jadwal_for_toko(toko_id));

create policy jadwal_kerja_update on public.jadwal_kerja
  for update to authenticated
  using (public.can_manage_jadwal_for_toko(toko_id))
  with check (public.can_manage_jadwal_for_toko(toko_id));

create policy jadwal_kerja_delete on public.jadwal_kerja
  for delete to authenticated
  using (public.can_manage_jadwal_for_toko(toko_id));

-- -----------------------------------------------------------------------------
-- toko_shift_settings — kuota/jam hanya admin toko itu
-- -----------------------------------------------------------------------------
create or replace function public.toko_shift_settings_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_jadwal_for_toko(new.toko_id)
     and not public.is_platform_user() then
    raise exception 'Hanya admin toko/cabang yang boleh ubah setting shift.'
      using errcode = '42501';
  end if;

  new.shift1_kuota := least(40, greatest(0, coalesce(new.shift1_kuota, 0)));
  new.shift2_kuota := least(40, greatest(0, coalesce(new.shift2_kuota, 0)));
  new.minggu_libur := false;
  new.shift1_label := left(trim(coalesce(new.shift1_label, 'Shift Pagi')), 40);
  new.shift2_label := left(trim(coalesce(new.shift2_label, 'Shift Sore')), 40);
  if new.shift1_label = '' then
    new.shift1_label := 'Shift Pagi';
  end if;
  if new.shift2_label = '' then
    new.shift2_label := 'Shift Sore';
  end if;
  if new.shift1_masuk is null or new.shift1_pulang is null
     or new.shift2_masuk is null or new.shift2_pulang is null then
    raise exception 'Setting shift wajib jam masuk/pulang kedua shift.'
      using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_toko_shift_settings_guard on public.toko_shift_settings;
create trigger trg_toko_shift_settings_guard
  before insert or update on public.toko_shift_settings
  for each row
  execute function public.toko_shift_settings_guard();

drop policy if exists toko_shift_settings_auth_all on public.toko_shift_settings;
drop policy if exists toko_shift_settings_tenant_seal on public.toko_shift_settings;
drop policy if exists toko_shift_settings_select on public.toko_shift_settings;
drop policy if exists toko_shift_settings_write on public.toko_shift_settings;
drop policy if exists toko_shift_settings_insert on public.toko_shift_settings;
drop policy if exists toko_shift_settings_update on public.toko_shift_settings;
drop policy if exists toko_shift_settings_delete on public.toko_shift_settings;

create policy toko_shift_settings_select on public.toko_shift_settings
  for select to authenticated
  using (public.toko_belongs_to_current_tenant(toko_id));

create policy toko_shift_settings_insert on public.toko_shift_settings
  for insert to authenticated
  with check (public.can_manage_jadwal_for_toko(toko_id));

create policy toko_shift_settings_update on public.toko_shift_settings
  for update to authenticated
  using (public.can_manage_jadwal_for_toko(toko_id))
  with check (public.can_manage_jadwal_for_toko(toko_id));

create policy toko_shift_settings_delete on public.toko_shift_settings
  for delete to authenticated
  using (public.can_manage_jadwal_for_toko(toko_id));

-- -----------------------------------------------------------------------------
-- jadwal_pengajuan — insert sendiri PENDING; decide hanya admin; apply di server
-- -----------------------------------------------------------------------------
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

    -- Tidak ada baris = hari libur (fail-closed), bukan hari kerja tanpa jam.
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

comment on function public.apply_approved_jadwal_pengajuan(uuid) is
  'Terapkan ijin/cuti/tukar dari baris pengajuan. Bukan dari payload client.';

revoke all on function public.apply_approved_jadwal_pengajuan(uuid)
  from public, anon, authenticated;
grant execute on function public.apply_approved_jadwal_pengajuan(uuid)
  to service_role;

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
    if new.tipe not in ('IJIN', 'CUTI', 'TUKAR') then
      raise exception 'Tipe pengajuan tidak valid.' using errcode = '42501';
    end if;
    if trim(coalesce(new.alasan, '')) = '' then
      raise exception 'Alasan wajib diisi.' using errcode = '42501';
    end if;
    new.alasan := left(trim(new.alasan), 500);

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

  -- UPDATE: kunci identitas; mesin status.
  new.karyawan_id := old.karyawan_id;
  new.toko_id := old.toko_id;
  new.tipe := old.tipe;
  new.tanggal := old.tanggal;
  new.tanggal_tukar := old.tanggal_tukar;
  new.partner_karyawan_id := old.partner_karyawan_id;
  new.alasan := old.alasan;
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

drop trigger if exists trg_jadwal_pengajuan_guard on public.jadwal_pengajuan;
create trigger trg_jadwal_pengajuan_guard
  before insert or update or delete on public.jadwal_pengajuan
  for each row
  execute function public.jadwal_pengajuan_guard();

create or replace function public.jadwal_pengajuan_after_decide()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'APPROVED' and old.status = 'PENDING' then
    perform public.apply_approved_jadwal_pengajuan(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_jadwal_pengajuan_after_decide on public.jadwal_pengajuan;
create trigger trg_jadwal_pengajuan_after_decide
  after update on public.jadwal_pengajuan
  for each row
  execute function public.jadwal_pengajuan_after_decide();

drop policy if exists jadwal_pengajuan_auth_all on public.jadwal_pengajuan;
drop policy if exists jadwal_pengajuan_tenant_seal on public.jadwal_pengajuan;
drop policy if exists jadwal_pengajuan_select on public.jadwal_pengajuan;
drop policy if exists jadwal_pengajuan_insert on public.jadwal_pengajuan;
drop policy if exists jadwal_pengajuan_update on public.jadwal_pengajuan;
drop policy if exists jadwal_pengajuan_delete on public.jadwal_pengajuan;

create policy jadwal_pengajuan_select on public.jadwal_pengajuan
  for select to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      public.jadwal_is_self_karyawan(karyawan_id)
      or public.can_manage_jadwal_for_toko(toko_id)
    )
  );

create policy jadwal_pengajuan_insert on public.jadwal_pengajuan
  for insert to authenticated
  with check (
    public.jadwal_is_self_karyawan(karyawan_id)
    and public.toko_belongs_to_current_tenant(toko_id)
    and upper(coalesce(status, '')) = 'PENDING'
  );

create policy jadwal_pengajuan_update on public.jadwal_pengajuan
  for update to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      public.jadwal_is_self_karyawan(karyawan_id)
      or public.can_manage_jadwal_for_toko(toko_id)
    )
  )
  with check (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      public.jadwal_is_self_karyawan(karyawan_id)
      or public.can_manage_jadwal_for_toko(toko_id)
    )
  );

-- Hapus hanya lewat platform / SQL Editor. Client: CANCELLED.
create policy jadwal_pengajuan_delete on public.jadwal_pengajuan
  for delete to authenticated
  using (public.is_platform_user());

create or replace function public.decide_jadwal_pengajuan(
  p_pengajuan_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jadwal_pengajuan%rowtype;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  select * into v_j
  from public.jadwal_pengajuan
  where id = p_pengajuan_id
    and status = 'PENDING';
  if v_j.id is null then
    raise exception 'Pengajuan tidak ditemukan / sudah diproses.';
  end if;

  if public.jadwal_is_self_karyawan(v_j.karyawan_id)
     and not public.is_platform_user() then
    raise exception 'Tidak boleh menyetujui atau menolak pengajuan sendiri.'
      using errcode = '42501';
  end if;

  if not public.jadwal_pengajuan_case_ok(v_j.toko_id, v_j.karyawan_id) then
    raise exception 'Hanya admin toko/cabang yang berhak memutus pengajuan.'
      using errcode = '42501';
  end if;

  v_status := case when p_approve then 'APPROVED' else 'REJECTED' end;

  update public.jadwal_pengajuan set
    status = v_status,
    reviewer_note = p_note,
    reviewed_at = now()
  where id = p_pengajuan_id
    and status = 'PENDING';

  if not found then
    raise exception 'Pengajuan tidak ditemukan / sudah diproses.';
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', p_pengajuan_id,
    'status', v_status,
    'tipe', v_j.tipe
  );
end;
$$;

comment on function public.decide_jadwal_pengajuan(uuid, boolean, text) is
  'Admin toko/cabang memutus ijin. Terapan roster di trigger, bukan client.';

revoke all on function public.decide_jadwal_pengajuan(uuid, boolean, text)
  from public, anon;
grant execute on function public.decide_jadwal_pengajuan(uuid, boolean, text)
  to authenticated, service_role;

-- Owner/admin_pusat: tetap RPC lama, tanpa tulis roster dari sini (hindari tukar 2x).
create or replace function public.owner_decide_jadwal(
  p_pengajuan_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jadwal_pengajuan%rowtype;
  v_res jsonb;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not (public.is_owner_role() or public.is_admin_pusat_or_owner()) then
    raise exception 'Hanya Owner / Admin';
  end if;

  select * into v_j
  from public.jadwal_pengajuan
  where id = p_pengajuan_id
    and status = 'PENDING';
  if v_j.id is null then
    raise exception 'Pengajuan tidak ditemukan / sudah diproses';
  end if;

  if public.is_owner_role() and not public.owner_can_access_toko(v_j.toko_id) then
    raise exception 'Toko di luar scope Owner';
  end if;

  v_res := public.decide_jadwal_pengajuan(p_pengajuan_id, p_approve, p_note);

  perform public.owner_write_audit(
    case when p_approve then 'approve_jadwal' else 'reject_jadwal' end,
    'jadwal_pengajuan',
    p_pengajuan_id::text,
    jsonb_build_object(
      'toko_id', v_j.toko_id,
      'tipe', v_j.tipe,
      'note', p_note
    )
  );

  return v_res;
end;
$$;

revoke all on function public.owner_decide_jadwal(uuid, boolean, text)
  from public, anon;
grant execute on function public.owner_decide_jadwal(uuid, boolean, text)
  to authenticated, service_role;

revoke all on function public.jadwal_kerja_guard() from public, anon;
revoke all on function public.toko_shift_settings_guard() from public, anon;
revoke all on function public.jadwal_pengajuan_guard() from public, anon;
revoke all on function public.jadwal_pengajuan_after_decide() from public, anon;
