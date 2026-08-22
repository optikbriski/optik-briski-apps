-- =============================================================================
-- 000019 — Monitor absensi: sekat toko + tenant.
-- Tutup policy lama `OR role IN (admin_toko, …)` yang membuka semua cabang
-- dan semua merek. Apply di SQL Editor live SETELAH 000018.
-- =============================================================================

create or replace function public.is_pusat_toko_id(p_toko text)
returns boolean
language sql
immutable
as $$
  select upper(trim(coalesce(p_toko, ''))) in ('PUSAT', 'CABANG-PUSAT');
$$;

comment on function public.is_pusat_toko_id(text) is
  'Hanya PUSAT / CABANG-PUSAT. Bukan semua kode *-PUSAT.';

create or replace function public.toko_belongs_to_current_tenant(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.current_tenant_id() is not null
    and exists (
      select 1
      from public.toko_id t
      where t.tenant_id = public.current_tenant_id()
        and (
          lower(trim(t.id)) = lower(trim(coalesce(p_toko, '')))
          or public.same_store_toko(t.id, p_toko)
        )
    );
$$;

comment on function public.toko_belongs_to_current_tenant(text) is
  'Toko ada di tenant sesi. Null tenant = tolak. Bukan merek lain.';

create or replace function public.can_monitor_attendance_for_toko(p_toko text)
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
      or public.current_profile_role() in ('owner', 'super_admin')
      or (
        public.current_profile_role() = 'admin_pusat'
        and not public.is_pusat_toko_id(p_toko)
      )
      or (
        public.current_profile_role() = 'admin_toko'
        and public.same_store_toko(public.current_profile_toko_id(), p_toko)
      )
    );
$$;

comment on function public.can_monitor_attendance_for_toko(text) is
  'Owner/super_admin: semua toko tenant. admin_pusat: cabang saja. '
  'admin_toko: toko sendiri. Bukan merek lain.';

create or replace function public.can_open_store_kiosk_for_toko(p_toko text)
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
      or public.current_profile_role() in ('owner', 'admin_pusat', 'super_admin')
      or (
        public.current_profile_role() = 'admin_toko'
        and public.same_store_toko(public.current_profile_toko_id(), p_toko)
      )
    );
$$;

comment on function public.can_open_store_kiosk_for_toko(text) is
  'Kiosk QR/face: pusat semua toko tenant; admin_toko hanya toko sendiri.';

create or replace function public.attendance_row_visible(p_toko text, p_karyawan uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.toko_belongs_to_current_tenant(p_toko)
    and (
      p_karyawan = auth.uid()
      or exists (
        select 1
        from public.karyawan k
        where k.id = p_karyawan
          and k.email is not null
          and k.email = (auth.jwt() ->> 'email')
      )
      or public.can_monitor_attendance_for_toko(p_toko)
      or public.can_open_store_kiosk_for_toko(p_toko)
    );
$$;

comment on function public.attendance_row_visible(text, uuid) is
  'Baca/tulis log-shift: pelaku absen, kiosk toko, atau monitor toko. Tenant wajib.';

-- Backfill tenant_id yang kosong (tabel anak toko_id).
do $$
declare
  t text;
begin
  foreach t in array array[
    'attendance_verifications',
    'attendance_logs',
    'attendance_shifts',
    'surat_peringatan'
  ]
  loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = t
        and column_name = 'tenant_id'
    ) then
      execute format(
        'update public.%I v set tenant_id = s.tenant_id
         from public.toko_id s
         where v.tenant_id is null
           and v.toko_id is not null
           and upper(trim(v.toko_id::text)) = upper(trim(s.id))',
        t
      );
    end if;
  end loop;
end
$$;

-- Policy tenant_seal bersifat OR dengan policy lain: siapa pun di tenant
-- bisa SELECT/UPDATE semua baris. Drop untuk tabel absensi — sekat toko di bawah.
drop policy if exists attendance_verifications_tenant_seal
  on public.attendance_verifications;
drop policy if exists attendance_logs_tenant_seal on public.attendance_logs;
drop policy if exists attendance_shifts_tenant_seal on public.attendance_shifts;
drop policy if exists surat_peringatan_tenant_seal on public.surat_peringatan;
drop policy if exists jadwal_kerja_tenant_seal on public.jadwal_kerja;
drop policy if exists attendance_geo_unlocks_tenant_seal
  on public.attendance_geo_unlocks;
drop policy if exists attendance_qr_tokens_tenant_seal
  on public.attendance_qr_tokens;

-- -----------------------------------------------------------------------------
-- attendance_verifications — ganti OR-role yang bocor
-- -----------------------------------------------------------------------------
drop policy if exists attendance_verifications_admin_select
  on public.attendance_verifications;
create policy attendance_verifications_admin_select
  on public.attendance_verifications
  for select to authenticated
  using (public.can_monitor_attendance_for_toko(toko_id));

drop policy if exists attendance_verifications_admin_update
  on public.attendance_verifications;
create policy attendance_verifications_admin_update
  on public.attendance_verifications
  for update to authenticated
  using (public.can_monitor_attendance_for_toko(toko_id))
  with check (public.can_monitor_attendance_for_toko(toko_id));

drop policy if exists attendance_verifications_admin_insert
  on public.attendance_verifications;
create policy attendance_verifications_admin_insert
  on public.attendance_verifications
  for insert to authenticated
  with check (
    public.can_open_store_kiosk_for_toko(toko_id)
    or public.can_monitor_attendance_for_toko(toko_id)
  );

drop policy if exists attendance_verifications_actor_insert
  on public.attendance_verifications;
create policy attendance_verifications_actor_insert
  on public.attendance_verifications
  for insert to authenticated
  with check (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      karyawan_id = auth.uid()
      or exists (
        select 1 from public.karyawan k
        where k.id = karyawan_id
          and k.email is not null
          and k.email = (auth.jwt() ->> 'email')
      )
    )
  );

create or replace function public.attendance_verifications_guard_monitor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if not public.same_store_toko(old.toko_id, new.toko_id) then
      raise exception 'toko_id verifikasi absensi tidak boleh dipindah'
        using errcode = '42501';
    end if;
    if old.karyawan_id is distinct from new.karyawan_id then
      raise exception 'karyawan_id verifikasi absensi tidak boleh diganti'
        using errcode = '42501';
    end if;
    if old.status is distinct from new.status
       and not public.can_monitor_attendance_for_toko(old.toko_id) then
      raise exception 'status verifikasi hanya diubah admin toko/cabang yang berhak'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_attendance_verifications_guard_monitor
  on public.attendance_verifications;
create trigger trg_attendance_verifications_guard_monitor
  before update on public.attendance_verifications
  for each row
  execute function public.attendance_verifications_guard_monitor();

-- -----------------------------------------------------------------------------
-- surat_peringatan
-- -----------------------------------------------------------------------------
drop policy if exists surat_peringatan_admin_select on public.surat_peringatan;
create policy surat_peringatan_admin_select
  on public.surat_peringatan
  for select to authenticated
  using (public.can_monitor_attendance_for_toko(toko_id));

drop policy if exists surat_peringatan_admin_insert on public.surat_peringatan;
create policy surat_peringatan_admin_insert
  on public.surat_peringatan
  for insert to authenticated
  with check (public.can_monitor_attendance_for_toko(toko_id));

-- -----------------------------------------------------------------------------
-- logs / shifts — ganti using(true)
-- -----------------------------------------------------------------------------
drop policy if exists attendance_logs_auth_all on public.attendance_logs;
create policy attendance_logs_scoped on public.attendance_logs
  for all to authenticated
  using (public.attendance_row_visible(toko_id, karyawan_id))
  with check (public.attendance_row_visible(toko_id, karyawan_id));

drop policy if exists attendance_shifts_auth_all on public.attendance_shifts;
create policy attendance_shifts_scoped on public.attendance_shifts
  for all to authenticated
  using (public.attendance_row_visible(toko_id, karyawan_id))
  with check (public.attendance_row_visible(toko_id, karyawan_id));

-- -----------------------------------------------------------------------------
-- jadwal (dipakai hitung telat di monitor)
-- -----------------------------------------------------------------------------
drop policy if exists jadwal_kerja_auth_all on public.jadwal_kerja;
create policy jadwal_kerja_scoped on public.jadwal_kerja
  for all to authenticated
  using (
    karyawan_id = auth.uid()
    or public.can_approve_karyawan_for_toko(toko_id)
    or public.can_monitor_attendance_for_toko(toko_id)
    or public.can_open_store_kiosk_for_toko(toko_id)
  )
  with check (
    karyawan_id = auth.uid()
    or public.can_approve_karyawan_for_toko(toko_id)
    or public.can_monitor_attendance_for_toko(toko_id)
    or public.can_open_store_kiosk_for_toko(toko_id)
  );

-- -----------------------------------------------------------------------------
-- geo unlocks admin SELECT
-- -----------------------------------------------------------------------------
drop policy if exists attendance_geo_unlocks_admin_select
  on public.attendance_geo_unlocks;
create policy attendance_geo_unlocks_admin_select
  on public.attendance_geo_unlocks
  for select to authenticated
  using (public.can_open_store_kiosk_for_toko(toko_id));

-- -----------------------------------------------------------------------------
-- Kiosk RPC: wajib tenant + toko sendiri
-- -----------------------------------------------------------------------------
create or replace function public.issue_attendance_qr_token(
  p_toko_id text,
  p_ttl_seconds integer default 5
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
begin
  if v_uid is null then
    raise exception 'Login diperlukan untuk menampilkan QR absensi.';
  end if;
  if v_toko = '' then
    raise exception 'toko_id wajib diisi.';
  end if;
  if not public.can_open_store_kiosk_for_toko(v_toko) then
    raise exception 'QR absensi hanya untuk toko Anda di usaha ini.';
  end if;

  v_ttl := greatest(5, least(coalesce(p_ttl_seconds, 5), 120));

  update public.attendance_qr_tokens
     set expires_at = now()
   where toko_id = v_toko
     and expires_at > now();

  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires := now() + make_interval(secs => v_ttl);

  insert into public.attendance_qr_tokens (toko_id, token, expires_at, created_by)
  values (v_toko, v_token, v_expires, v_uid)
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

create or replace function public.get_latest_attendance_geo_unlock_for_toko(
  p_toko_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_toko text := trim(coalesce(p_toko_id, ''));
  v_row public.attendance_geo_unlocks%rowtype;
begin
  if v_uid is null then
    raise exception 'Login diperlukan.';
  end if;
  if v_toko = '' then
    raise exception 'toko_id wajib.';
  end if;
  if not public.can_open_store_kiosk_for_toko(v_toko) then
    raise exception 'Hanya Admin toko yang bersangkutan di usaha ini.';
  end if;

  select * into v_row
  from public.attendance_geo_unlocks u
  where u.toko_id = v_toko
    and u.expires_at > now()
    and u.consumed_at is null
  order by u.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'valid', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'valid', true,
    'id', v_row.id,
    'karyawan_id', v_row.karyawan_id,
    'toko_id', v_row.toko_id,
    'expires_at', v_row.expires_at,
    'created_at', v_row.created_at,
    'latitude', v_row.latitude,
    'longitude', v_row.longitude,
    'accuracy_meters', v_row.accuracy_meters,
    'source', v_row.source,
    'qr_token_id', v_row.qr_token_id
  );
end;
$$;

create or replace function public.consume_attendance_geo_unlock(
  p_unlock_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.attendance_geo_unlocks%rowtype;
begin
  if v_uid is null then
    raise exception 'Login diperlukan.';
  end if;
  if p_unlock_id is null then
    raise exception 'unlock_id wajib.';
  end if;

  select * into v_row
  from public.attendance_geo_unlocks u
  where u.id = p_unlock_id
  for update;

  if not found then
    return jsonb_build_object('ok', false);
  end if;

  if not public.can_open_store_kiosk_for_toko(v_row.toko_id) then
    raise exception 'Tidak berhak untuk toko ini.';
  end if;

  update public.attendance_geo_unlocks
     set consumed_at = coalesce(consumed_at, now()),
         expires_at = least(expires_at, now())
   where id = p_unlock_id;

  return jsonb_build_object('ok', true, 'id', p_unlock_id);
end;
$$;

create or replace function public.create_attendance_geo_unlock(
  p_toko_id text,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_accuracy_meters double precision default null,
  p_ttl_seconds integer default 180,
  p_qr_token_id uuid default null,
  p_source text default 'qr+gps'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_karyawan_id uuid;
  v_karyawan_toko text;
  v_ttl integer;
  v_expires timestamptz;
  v_id uuid;
  v_source text;
  v_toko text := trim(coalesce(p_toko_id, ''));
begin
  if v_uid is null then
    raise exception 'Login karyawan diperlukan untuk verifikasi lokasi.';
  end if;
  if v_toko = '' then
    raise exception 'toko_id wajib diisi.';
  end if;
  if not public.toko_belongs_to_current_tenant(v_toko) then
    raise exception 'Toko tidak ada di usaha ini.';
  end if;

  select k.id, k.toko_id
    into v_karyawan_id, v_karyawan_toko
  from public.karyawan k
  where k.id = v_uid
     or (k.email is not null and k.email = (auth.jwt() ->> 'email'))
  order by case when k.id = v_uid then 0 else 1 end
  limit 1;

  if v_karyawan_id is null then
    raise exception 'Data karyawan tidak ditemukan untuk akun ini.';
  end if;

  if not public.same_store_toko(v_karyawan_toko, v_toko) then
    raise exception 'Lokasi unlock hanya untuk toko Anda (%).',
      coalesce(trim(v_karyawan_toko), '-');
  end if;

  if p_latitude is null or p_longitude is null then
    raise exception
      'GPS wajib. Scan QR hanya berhasil jika HP Anda di dalam area toko.';
  end if;

  if p_qr_token_id is not null then
    if not exists (
      select 1
      from public.attendance_qr_tokens t
      where t.id = p_qr_token_id
        and t.toko_id = v_toko
        and t.expires_at > now() - interval '2 minutes'
    ) then
      raise exception 'Token QR absensi tidak valid untuk unlock lokasi.';
    end if;
  end if;

  v_ttl := greatest(120, least(coalesce(p_ttl_seconds, 180), 300));
  v_expires := now() + make_interval(secs => v_ttl);
  v_source := coalesce(nullif(trim(p_source), ''), 'qr+gps');

  update public.attendance_geo_unlocks
     set expires_at = least(expires_at, now())
   where karyawan_id = v_karyawan_id
     and toko_id = v_toko
     and expires_at > now();

  insert into public.attendance_geo_unlocks (
    karyawan_id, toko_id, expires_at, latitude, longitude,
    accuracy_meters, source, qr_token_id
  ) values (
    v_karyawan_id, v_toko, v_expires, p_latitude, p_longitude,
    p_accuracy_meters, v_source, p_qr_token_id
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'karyawan_id', v_karyawan_id,
    'toko_id', v_toko,
    'expires_at', v_expires,
    'ttl_seconds', v_ttl,
    'latitude', p_latitude,
    'longitude', p_longitude,
    'accuracy_meters', p_accuracy_meters,
    'source', v_source
  );
end;
$$;

revoke all on function public.is_pusat_toko_id(text) from public;
revoke all on function public.is_pusat_toko_id(text) from anon;
grant execute on function public.is_pusat_toko_id(text) to authenticated, service_role;

revoke all on function public.toko_belongs_to_current_tenant(text) from public;
revoke all on function public.toko_belongs_to_current_tenant(text) from anon;
grant execute on function public.toko_belongs_to_current_tenant(text)
  to authenticated, service_role;

revoke all on function public.can_monitor_attendance_for_toko(text) from public;
revoke all on function public.can_monitor_attendance_for_toko(text) from anon;
grant execute on function public.can_monitor_attendance_for_toko(text)
  to authenticated, service_role;

revoke all on function public.can_open_store_kiosk_for_toko(text) from public;
revoke all on function public.can_open_store_kiosk_for_toko(text) from anon;
grant execute on function public.can_open_store_kiosk_for_toko(text)
  to authenticated, service_role;

revoke all on function public.attendance_row_visible(text, uuid) from public;
revoke all on function public.attendance_row_visible(text, uuid) from anon;
grant execute on function public.attendance_row_visible(text, uuid)
  to authenticated, service_role;
