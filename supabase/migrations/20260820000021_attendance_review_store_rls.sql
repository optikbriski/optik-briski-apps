-- =============================================================================
-- 000021 — Tinjauan mencurigakan end-to-end.
-- Apply di SQL Editor live SETELAH 000020.
--
-- Monitor (000019) sudah sekat toko/tenant, tapi:
-- - status bisa loncat pending → curang / dibuka ulang lewat REST
-- - poin_logs FOR ALL di usaha yang sama = karyawan bisa +20 / hapus −200
-- - markCurang bisa menulis poin/SP ke karyawan_id lain dari client
-- =============================================================================

-- Kasus tinjauan: karyawan milik toko + usaha yang sama, dan pemanggil berhak monitor.
create or replace function public.attendance_review_case_ok(
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
    public.can_monitor_attendance_for_toko(p_toko)
    and exists (
      select 1
      from public.karyawan k
      where k.id = p_karyawan
        and k.tenant_id is not null
        and k.tenant_id is not distinct from public.current_tenant_id()
        and public.same_store_toko(k.toko_id, p_toko)
    );
$$;

comment on function public.attendance_review_case_ok(text, uuid) is
  'Tinjauan/Valid/Curang: monitor toko + karyawan toko/usaha yang sama.';

revoke all on function public.attendance_review_case_ok(text, uuid)
  from public, anon;
grant execute on function public.attendance_review_case_ok(text, uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Mesin status + sekat baris. INSERT selalu pending. Foto/shift tidak diutak-atik.
-- -----------------------------------------------------------------------------
create or replace function public.attendance_verifications_guard_monitor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_k_toko text;
  v_k_tenant uuid;
  v_late integer;
begin
  select k.toko_id, k.tenant_id
    into v_k_toko, v_k_tenant
  from public.karyawan k
  where k.id = new.karyawan_id;

  if not found or v_k_tenant is null then
    raise exception 'Karyawan verifikasi absensi tidak valid.'
      using errcode = '42501';
  end if;

  if not public.same_store_toko(v_k_toko, new.toko_id) then
    raise exception 'Verifikasi absensi hanya untuk toko karyawan.'
      using errcode = '42501';
  end if;

  if new.tenant_id is not null
     and new.tenant_id is distinct from v_k_tenant then
    raise exception 'tenant_id verifikasi tidak boleh beda usaha.'
      using errcode = '42501';
  end if;
  new.tenant_id := coalesce(new.tenant_id, v_k_tenant);

  if tg_op = 'INSERT' then
    new.status := 'pending_review';
    new.poin_awarded := null;
    new.reviewed_by := null;
    new.reviewed_at := null;
    return new;
  end if;

  if not public.same_store_toko(old.toko_id, new.toko_id) then
    raise exception 'toko_id verifikasi absensi tidak boleh dipindah'
      using errcode = '42501';
  end if;
  if old.karyawan_id is distinct from new.karyawan_id then
    raise exception 'karyawan_id verifikasi absensi tidak boleh diganti'
      using errcode = '42501';
  end if;
  if old.shift_id is distinct from new.shift_id
     or old.log_id is distinct from new.log_id then
    raise exception 'shift/log verifikasi tidak boleh diganti'
      using errcode = '42501';
  end if;
  if old.tenant_id is not null
     and new.tenant_id is distinct from old.tenant_id then
    raise exception 'tenant_id verifikasi tidak boleh diganti'
      using errcode = '42501';
  end if;

  new.capture_photo_url := old.capture_photo_url;
  new.enrolled_photo_url := old.enrolled_photo_url;
  new.match_score := old.match_score;
  new.liveness_ok := old.liveness_ok;
  new.liveness_confidence := old.liveness_confidence;
  new.liveness_provider := old.liveness_provider;

  if old.status is distinct from new.status then
    if not public.can_monitor_attendance_for_toko(old.toko_id) then
      raise exception 'status verifikasi hanya diubah admin toko/cabang yang berhak'
        using errcode = '42501';
    end if;
    if not public.attendance_review_case_ok(old.toko_id, old.karyawan_id) then
      raise exception 'Kasus tinjauan bukan milik toko/usaha ini.'
        using errcode = '42501';
    end if;

    if old.status = 'pending_review'
       and new.status in ('aman', 'mencurigakan') then
      null;
    elsif old.status = 'mencurigakan'
       and new.status in ('aman', 'curang') then
      null;
    else
      raise exception
        'Alur tinjauan: pending → aman/mencurigakan; mencurigakan → aman/curang.'
        using errcode = '42501';
    end if;

    new.reviewed_by := auth.uid();
    new.reviewed_at := coalesce(new.reviewed_at, now());

    if new.status = 'mencurigakan' then
      new.poin_awarded := null;
    elsif new.status = 'curang' then
      new.poin_awarded := -200;
    elsif new.status = 'aman' then
      v_late := 0;
      if new.log_id is not null then
        select coalesce(l.late_penalty_points, 0)
          into v_late
        from public.attendance_logs l
        where l.id = new.log_id;
      end if;
      if v_late < 0 then
        new.poin_awarded := v_late;
      else
        new.poin_awarded := 20;
      end if;
    end if;
  else
    new.poin_awarded := old.poin_awarded;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_attendance_verifications_guard_monitor
  on public.attendance_verifications;
create trigger trg_attendance_verifications_guard_monitor
  before insert or update on public.attendance_verifications
  for each row
  execute function public.attendance_verifications_guard_monitor();

-- Poin + SP dari baris kasus (bukan karyawan_id yang dikirim client).
create or replace function public.attendance_verifications_apply_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tanggal date;
  v_alasan text;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;
  if old.status is not distinct from new.status then
    return new;
  end if;
  if new.status not in ('aman', 'curang') then
    return new;
  end if;

  v_tanggal := (timezone('Asia/Jakarta', coalesce(new.reviewed_at, now())))::date;

  if new.status = 'curang' then
    delete from public.poin_logs p
    where p.karyawan_id = new.karyawan_id
      and (
        p.ref_id = 'absen-valid-' || new.id::text
        or (
          new.log_id is not null
          and p.ref_id = 'absen-telat-' || new.log_id::text
        )
      );

    begin
      insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
      values (
        new.karyawan_id, v_tanggal, -200, 'ABSEN',
        'absen-curang-' || new.id::text
      );
    exception
      when unique_violation then null;
    end;

    v_alasan := coalesce(nullif(trim(new.notes), ''),
      'Terbukti curang pada verifikasi wajah absensi (bukan keterlambatan).');

    begin
      insert into public.surat_peringatan (
        karyawan_id, toko_id, tingkat, alasan, sumber, ref_id,
        issued_by, issued_at
      ) values (
        new.karyawan_id, new.toko_id, 1, v_alasan, 'ABSEN_CURANG',
        new.id::text, new.reviewed_by, coalesce(new.reviewed_at, now())
      );
    exception
      when unique_violation then null;
    end;
  elsif coalesce(new.poin_awarded, 0) < 0 and new.log_id is not null then
    begin
      insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
      values (
        new.karyawan_id, v_tanggal, new.poin_awarded, 'ABSEN_TELAT',
        'absen-telat-' || new.log_id::text
      );
    exception
      when unique_violation then null;
    end;
  else
    begin
      insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
      values (
        new.karyawan_id, v_tanggal, coalesce(new.poin_awarded, 20), 'ABSEN',
        'absen-valid-' || new.id::text
      );
    exception
      when unique_violation then null;
    end;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_attendance_verifications_apply_review
  on public.attendance_verifications;
create trigger trg_attendance_verifications_apply_review
  after update of status on public.attendance_verifications
  for each row
  execute function public.attendance_verifications_apply_review();

-- -----------------------------------------------------------------------------
-- SP: jangan titip ke karyawan toko/usaha lain
-- -----------------------------------------------------------------------------
create or replace function public.surat_peringatan_guard_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_k_toko text;
  v_k_tenant uuid;
begin
  select k.toko_id, k.tenant_id
    into v_k_toko, v_k_tenant
  from public.karyawan k
  where k.id = new.karyawan_id;

  if not found then
    raise exception 'Karyawan SP tidak ditemukan.' using errcode = '42501';
  end if;

  if new.toko_id is null or not public.same_store_toko(v_k_toko, new.toko_id) then
    raise exception 'SP hanya untuk toko karyawan.' using errcode = '42501';
  end if;

  if v_k_tenant is null
     or v_k_tenant is distinct from public.current_tenant_id() then
    raise exception 'SP bukan milik usaha ini.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' and coalesce(new.sumber, '') = 'ABSEN_CURANG' then
    if new.ref_id is null
       or not exists (
         select 1
         from public.attendance_verifications v
         where v.id::text = new.ref_id
           and v.karyawan_id = new.karyawan_id
           and public.same_store_toko(v.toko_id, new.toko_id)
           and v.status = 'curang'
       ) then
      raise exception 'SP absensi curang wajib kasus tinjauan yang sudah curang.'
        using errcode = '42501';
    end if;
    new.tingkat := 1;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_surat_peringatan_guard_scope on public.surat_peringatan;
create trigger trg_surat_peringatan_guard_scope
  before insert or update on public.surat_peringatan
  for each row
  execute function public.surat_peringatan_guard_scope();

drop policy if exists surat_peringatan_admin_insert on public.surat_peringatan;
create policy surat_peringatan_admin_insert
  on public.surat_peringatan
  for insert to authenticated
  with check (public.attendance_review_case_ok(toko_id, karyawan_id));

-- -----------------------------------------------------------------------------
-- poin_logs: ABSEN hanya monitor toko. SOP/INVOICE tetap jalan di usaha sendiri.
-- -----------------------------------------------------------------------------
drop policy if exists poin_logs_auth_all on public.poin_logs;
drop policy if exists poin_logs_tenant on public.poin_logs;
drop policy if exists poin_logs_tenant_seal on public.poin_logs;
drop policy if exists poin_logs_select on public.poin_logs;
drop policy if exists poin_logs_insert on public.poin_logs;
drop policy if exists poin_logs_update on public.poin_logs;
drop policy if exists poin_logs_delete on public.poin_logs;

create policy poin_logs_select
  on public.poin_logs
  for select to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id
        and k.tenant_id is not distinct from public.current_tenant_id()
        and (
          k.id = auth.uid()
          or (
            k.email is not null and k.email = (auth.jwt() ->> 'email')
          )
          or public.can_monitor_attendance_for_toko(k.toko_id)
        )
    )
  );

create policy poin_logs_insert
  on public.poin_logs
  for insert to authenticated
  with check (
    exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id
        and k.tenant_id is not distinct from public.current_tenant_id()
        and (
          (
            sumber in ('ABSEN', 'ABSEN_TELAT')
            and public.can_monitor_attendance_for_toko(k.toko_id)
          )
          or (
            sumber not in ('ABSEN', 'ABSEN_TELAT')
            and (
              k.id = auth.uid()
              or public.can_monitor_attendance_for_toko(k.toko_id)
              or public.can_open_store_kiosk_for_toko(k.toko_id)
              or public.current_profile_role() in (
                'kasir', 'owner', 'admin_toko', 'admin_pusat', 'super_admin'
              )
            )
          )
        )
    )
  );

create policy poin_logs_delete
  on public.poin_logs
  for delete to authenticated
  using (
    exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id
        and k.tenant_id is not distinct from public.current_tenant_id()
        and (
          (
            sumber in ('ABSEN', 'ABSEN_TELAT')
            and public.can_monitor_attendance_for_toko(k.toko_id)
          )
          or (
            sumber not in ('ABSEN', 'ABSEN_TELAT')
            and (
              public.can_monitor_attendance_for_toko(k.toko_id)
              or public.can_open_store_kiosk_for_toko(k.toko_id)
            )
          )
        )
    )
  );

-- Admin tinjauan boleh kirim notifikasi ke karyawan toko yang dinilai.
drop policy if exists notifikasi_admin_insert_review on public.notifikasi;
create policy notifikasi_admin_insert_review
  on public.notifikasi
  for insert to authenticated
  with check (
    exists (
      select 1 from public.karyawan k
      where k.id = user_id
        and public.can_monitor_attendance_for_toko(k.toko_id)
    )
  );

revoke all on function public.attendance_verifications_apply_review()
  from public, anon;
revoke all on function public.surat_peringatan_guard_scope()
  from public, anon;
