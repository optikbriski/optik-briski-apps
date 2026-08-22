-- =============================================================================
-- 000020 — Absensi toko end-to-end: karyawan HP → QR → GPS server → kiosk →
-- shift OPEN → POS. Apply di SQL Editor live SETELAH 000019.
--
-- 000019 mengunci monitor, tapi menimpa create_attendance_geo_unlock sehingga
-- hilang cek geofence/QR wajib/jadwal. REST INSERT unlock juga masih bisa
-- menipu kiosk. geofence_exit_logs dan get_valid_attendance_geo_unlock masih
-- memakai role-OR lintas merek.
-- =============================================================================

-- Geofence toko + alias PUSAT ↔ CABANG-PUSAT (baris geofence bisa di salah satu).
create or replace function public.point_in_store_geofence(
  p_toko_id text,
  p_lat double precision,
  p_lng double precision,
  p_buffer_meters double precision default 8
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.point_in_toko_geofence(p_toko_id, p_lat, p_lng, p_buffer_meters)
    or (
      public.is_pusat_toko_id(p_toko_id)
      and (
        public.point_in_toko_geofence('PUSAT', p_lat, p_lng, p_buffer_meters)
        or public.point_in_toko_geofence(
          'CABANG-PUSAT', p_lat, p_lng, p_buffer_meters
        )
      )
    );
$$;

comment on function public.point_in_store_geofence(
  text, double precision, double precision, double precision
) is
  'Geofence toko. PUSAT dan CABANG-PUSAT memakai area yang sama.';

revoke all on function public.point_in_store_geofence(
  text, double precision, double precision, double precision
) from public, anon;
grant execute on function public.point_in_store_geofence(
  text, double precision, double precision, double precision
) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- QR: tenant + PUSAT ↔ CABANG-PUSAT
-- -----------------------------------------------------------------------------
create or replace function public.validate_attendance_qr_token(
  p_payload text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text := trim(coalesce(p_payload, ''));
  v_parts text[];
  v_toko text;
  v_token text;
  v_row public.attendance_qr_tokens%rowtype;
  v_karyawan_toko text;
  v_karyawan_tenant uuid;
begin
  if v_uid is null then
    raise exception 'Login karyawan diperlukan untuk scan QR absensi.';
  end if;

  if length(v_raw) = 0 then
    raise exception 'QR kosong / tidak terbaca.';
  end if;

  if position('|' in v_raw) > 0 then
    v_parts := string_to_array(v_raw, '|');
    if array_length(v_parts, 1) < 4
       or v_parts[1] <> 'OBRATT'
       or v_parts[2] <> 'v1' then
      raise exception 'Format QR absensi tidak dikenali. Scan QR di layar Admin toko.';
    end if;
    v_toko := trim(v_parts[3]);
    v_token := trim(v_parts[4]);
  else
    v_token := v_raw;
    v_toko := null;
  end if;

  if v_token is null or length(v_token) < 16 then
    raise exception 'Token QR tidak valid.';
  end if;

  select k.toko_id, k.tenant_id
    into v_karyawan_toko, v_karyawan_tenant
  from public.karyawan k
  where k.id = v_uid
     or (k.email is not null and k.email = (auth.jwt() ->> 'email'))
  order by case when k.id = v_uid then 0 else 1 end
  limit 1;

  if v_karyawan_toko is null or length(trim(v_karyawan_toko)) = 0 then
    raise exception 'Data karyawan tidak ditemukan untuk akun ini.';
  end if;

  if v_karyawan_tenant is null
     or v_karyawan_tenant is distinct from public.current_tenant_id() then
    raise exception 'Akun karyawan bukan milik usaha ini.';
  end if;

  select * into v_row
  from public.attendance_qr_tokens t
  where t.token = v_token
  order by t.created_at desc
  limit 1;

  if not found then
    raise exception 'QR tidak dikenali. Pastikan scan QR Absensi di layar Admin.';
  end if;

  if v_row.expires_at <= now() then
    raise exception 'QR sudah kedaluwarsa. Minta Admin tampilkan QR terbaru.';
  end if;

  if not public.toko_belongs_to_current_tenant(v_row.toko_id) then
    raise exception 'QR absensi bukan milik usaha ini.';
  end if;

  if v_toko is not null
     and not public.same_store_toko(v_toko, v_row.toko_id) then
    raise exception 'QR tidak cocok dengan toko pada kode.';
  end if;

  if not public.same_store_toko(v_karyawan_toko, v_row.toko_id) then
    raise exception 'QR milik toko % — akun Anda terdaftar di %. Scan QR toko Anda.',
      v_row.toko_id, trim(v_karyawan_toko);
  end if;

  return jsonb_build_object(
    'ok', true,
    'token_id', v_row.id,
    'toko_id', v_row.toko_id,
    'expires_at', v_row.expires_at
  );
end;
$$;

revoke all on function public.validate_attendance_qr_token(text)
  from public, anon;
grant execute on function public.validate_attendance_qr_token(text)
  to authenticated, service_role;

comment on function public.validate_attendance_qr_token(text) is
  'Karyawan: validasi QR absensi. Wajib tenant + toko sendiri (PUSAT = CABANG-PUSAT).';

-- -----------------------------------------------------------------------------
-- Geo unlock: pulihkan geofence/QR/jadwal + sekat tenant (000019 menimpa ini)
-- -----------------------------------------------------------------------------
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
  v_karyawan_tenant uuid;
  v_ttl integer;
  v_expires timestamptz;
  v_id uuid;
  v_source text;
  v_jam_masuk time;
  v_is_libur boolean;
  v_today date;
  v_buf double precision;
  v_is_pulang boolean;
  v_toko text := trim(coalesce(p_toko_id, ''));
  v_has_tenant boolean;
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

  if p_latitude is null or p_longitude is null then
    raise exception
      'GPS wajib. Absen hanya berhasil jika HP Anda di dalam area toko.';
  end if;

  if p_qr_token_id is null then
    raise exception 'QR Absensi wajib. Scan QR di perangkat toko dulu.';
  end if;

  if not exists (
    select 1
    from public.attendance_qr_tokens t
    where t.id = p_qr_token_id
      and public.same_store_toko(t.toko_id, v_toko)
      and public.toko_belongs_to_current_tenant(t.toko_id)
      and t.expires_at > now() - interval '2 minutes'
  ) then
    raise exception 'Token QR absensi tidak valid / kedaluwarsa.';
  end if;

  select k.id, k.toko_id, k.tenant_id
    into v_karyawan_id, v_karyawan_toko, v_karyawan_tenant
  from public.karyawan k
  where k.id = v_uid
     or (k.email is not null and k.email = (auth.jwt() ->> 'email'))
  order by case when k.id = v_uid then 0 else 1 end
  limit 1;

  if v_karyawan_id is null then
    raise exception 'Data karyawan tidak ditemukan untuk akun ini.';
  end if;

  if v_karyawan_tenant is null
     or v_karyawan_tenant is distinct from public.current_tenant_id() then
    raise exception 'Akun karyawan bukan milik usaha ini.';
  end if;

  if not public.same_store_toko(v_karyawan_toko, v_toko) then
    raise exception 'Lokasi unlock hanya untuk toko Anda (%).',
      coalesce(trim(v_karyawan_toko), '-');
  end if;

  v_source := coalesce(nullif(trim(p_source), ''), 'qr+gps');
  v_is_pulang := position('pulang' in lower(v_source)) > 0;
  v_today := public.jakarta_today();

  v_buf := 8;
  if p_accuracy_meters is not null and p_accuracy_meters > 0 then
    v_buf := least(40, greatest(0, p_accuracy_meters * 0.4));
  end if;

  if not public.point_in_store_geofence(v_toko, p_latitude, p_longitude, v_buf)
  then
    raise exception
      'Di luar geofence toko. Absen ditolak. Pastikan GPS akurat dan Anda di area toko.';
  end if;

  if not v_is_pulang then
    select j.jam_masuk, j.is_libur
      into v_jam_masuk, v_is_libur
    from public.jadwal_kerja j
    where j.karyawan_id = v_karyawan_id
      and j.tanggal = v_today;

    if not found then
      raise exception
        'Belum ada jadwal kerja hari ini. Absen hanya bisa saat dijadwalkan.';
    end if;
    if coalesce(v_is_libur, false) then
      raise exception 'Hari ini libur menurut jadwal. Absen tidak tersedia.';
    end if;
    if v_jam_masuk is null then
      raise exception 'Jam masuk jadwal kosong. Hubungi Admin.';
    end if;
  end if;

  v_ttl := greatest(120, least(coalesce(p_ttl_seconds, 180), 300));
  v_expires := now() + make_interval(secs => v_ttl);

  update public.attendance_geo_unlocks
     set expires_at = least(expires_at, now())
   where karyawan_id = v_karyawan_id
     and public.same_store_toko(toko_id, v_toko)
     and expires_at > now();

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'attendance_geo_unlocks'
      and column_name = 'tenant_id'
  ) into v_has_tenant;

  if v_has_tenant then
    insert into public.attendance_geo_unlocks (
      karyawan_id, toko_id, expires_at, latitude, longitude,
      accuracy_meters, source, qr_token_id, tenant_id
    ) values (
      v_karyawan_id, v_toko, v_expires, p_latitude, p_longitude,
      p_accuracy_meters, v_source, p_qr_token_id, v_karyawan_tenant
    )
    returning id into v_id;
  else
    insert into public.attendance_geo_unlocks (
      karyawan_id, toko_id, expires_at, latitude, longitude,
      accuracy_meters, source, qr_token_id
    ) values (
      v_karyawan_id, v_toko, v_expires, p_latitude, p_longitude,
      p_accuracy_meters, v_source, p_qr_token_id
    )
    returning id into v_id;
  end if;

  return jsonb_build_object(
    'id', v_id,
    'karyawan_id', v_karyawan_id,
    'toko_id', v_toko,
    'tenant_id', v_karyawan_tenant,
    'expires_at', v_expires,
    'ttl_seconds', v_ttl,
    'latitude', p_latitude,
    'longitude', p_longitude,
    'accuracy_meters', p_accuracy_meters,
    'source', v_source,
    'geofence_ok', true,
    'qr_token_id', p_qr_token_id
  );
end;
$$;

revoke all on function public.create_attendance_geo_unlock(
  text, double precision, double precision, double precision, integer, uuid, text
) from public, anon;
grant execute on function public.create_attendance_geo_unlock(
  text, double precision, double precision, double precision, integer, uuid, text
) to authenticated, service_role;

comment on function public.create_attendance_geo_unlock is
  'Karyawan: unlock absen. Wajib QR + GPS di dalam geofence (dicek server) + tenant. '
  'Masuk: wajib jadwal. Bukan REST insert.';

-- -----------------------------------------------------------------------------
-- Admin/karyawan: cek unlock aktif — sekat kiosk + tenant (bukan role-OR lama)
-- -----------------------------------------------------------------------------
create or replace function public.get_valid_attendance_geo_unlock(
  p_karyawan_id uuid,
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
  v_self boolean := false;
begin
  if v_uid is null then
    raise exception 'Login diperlukan.';
  end if;
  if p_karyawan_id is null or v_toko = '' then
    raise exception 'karyawan_id dan toko_id wajib.';
  end if;
  if not public.toko_belongs_to_current_tenant(v_toko) then
    raise exception 'Toko tidak ada di usaha ini.';
  end if;

  select exists (
    select 1
    from public.karyawan k
    where k.id = p_karyawan_id
      and (
        k.id = v_uid
        or (k.email is not null and k.email = (auth.jwt() ->> 'email'))
      )
  ) into v_self;

  if not v_self and not public.can_open_store_kiosk_for_toko(v_toko) then
    raise exception 'Hanya Admin toko yang bersangkutan di usaha ini yang boleh cek unlock.';
  end if;

  select * into v_row
  from public.attendance_geo_unlocks u
  where u.karyawan_id = p_karyawan_id
    and public.same_store_toko(u.toko_id, v_toko)
    and u.expires_at > now()
    and u.consumed_at is null
  order by u.expires_at desc
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

revoke all on function public.get_valid_attendance_geo_unlock(uuid, text)
  from public, anon;
grant execute on function public.get_valid_attendance_geo_unlock(uuid, text)
  to authenticated, service_role;

comment on function public.get_valid_attendance_geo_unlock(uuid, text) is
  'Cek unlock aktif. Pelaku sendiri atau kiosk toko di tenant yang sama.';

-- Pusat: kiosk CABANG-PUSAT harus melihat unlock PUSAT (dan sebaliknya).
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
  where public.same_store_toko(u.toko_id, v_toko)
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

-- -----------------------------------------------------------------------------
-- Jangan izinkan REST INSERT unlock (bypass geofence/QR). RPC DEFINER tetap bisa.
-- -----------------------------------------------------------------------------
drop policy if exists attendance_geo_unlocks_karyawan_insert
  on public.attendance_geo_unlocks;
revoke insert on table public.attendance_geo_unlocks from anon, authenticated, public;
grant select on table public.attendance_geo_unlocks to authenticated;
grant all on table public.attendance_geo_unlocks to service_role;

drop policy if exists attendance_geo_unlocks_karyawan_select
  on public.attendance_geo_unlocks;
create policy attendance_geo_unlocks_karyawan_select
  on public.attendance_geo_unlocks
  for select
  to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      karyawan_id = auth.uid()
      or exists (
        select 1
        from public.karyawan k
        where k.id = karyawan_id
          and k.email is not null
          and k.email = (auth.jwt() ->> 'email')
      )
    )
  );

-- -----------------------------------------------------------------------------
-- Shift/log: karyawan + toko + tenant harus satu usaha. OPEN wajib bukti unlock.
-- -----------------------------------------------------------------------------
create or replace function public.attendance_guard_karyawan_toko_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_k_toko text;
  v_k_tenant uuid;
  v_toko_tenant uuid;
begin
  select k.toko_id, k.tenant_id
    into v_k_toko, v_k_tenant
  from public.karyawan k
  where k.id = new.karyawan_id;

  if not found then
    raise exception 'Karyawan absensi tidak ditemukan.'
      using errcode = '42501';
  end if;

  if v_k_tenant is null then
    raise exception 'Karyawan belum terikat usaha.'
      using errcode = '42501';
  end if;

  if not public.same_store_toko(v_k_toko, new.toko_id) then
    raise exception 'Absensi hanya untuk toko karyawan.'
      using errcode = '42501';
  end if;

  select t.tenant_id into v_toko_tenant
  from public.toko_id t
  where public.same_store_toko(t.id, new.toko_id)
    and t.tenant_id = v_k_tenant
  limit 1;

  if v_toko_tenant is null then
    raise exception 'Toko absensi bukan milik usaha karyawan.'
      using errcode = '42501';
  end if;

  if new.tenant_id is not null
     and new.tenant_id is distinct from v_k_tenant then
    raise exception 'tenant_id absensi tidak boleh beda usaha.'
      using errcode = '42501';
  end if;

  new.tenant_id := coalesce(new.tenant_id, v_k_tenant);
  return new;
end;
$$;

drop trigger if exists trg_attendance_shifts_guard_scope on public.attendance_shifts;
create trigger trg_attendance_shifts_guard_scope
  before insert or update of karyawan_id, toko_id, tenant_id
  on public.attendance_shifts
  for each row
  execute function public.attendance_guard_karyawan_toko_tenant();

drop trigger if exists trg_attendance_logs_guard_scope on public.attendance_logs;
create trigger trg_attendance_logs_guard_scope
  before insert or update of karyawan_id, toko_id, tenant_id
  on public.attendance_logs
  for each row
  execute function public.attendance_guard_karyawan_toko_tenant();

-- Shift OPEN = tiket POS. Jangan boleh tanpa QR+GPS server (geo unlock).
create or replace function public.attendance_guard_open_shift_unlock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if upper(trim(coalesce(new.status, ''))) <> 'OPEN' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and upper(trim(coalesce(old.status, ''))) = 'OPEN' then
    return new;
  end if;

  if not exists (
    select 1
    from public.attendance_geo_unlocks u
    where u.karyawan_id = new.karyawan_id
      and public.same_store_toko(u.toko_id, new.toko_id)
      and u.qr_token_id is not null
      and u.latitude is not null
      and u.longitude is not null
      and u.created_at > now() - interval '10 minutes'
  ) then
    raise exception
      'Absen masuk wajib QR toko + GPS di dalam area (dicek server).'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_attendance_shifts_open_unlock
  on public.attendance_shifts;
create trigger trg_attendance_shifts_open_unlock
  before insert or update of status
  on public.attendance_shifts
  for each row
  execute function public.attendance_guard_open_shift_unlock();

-- Log MASUK: QR + GPS server. Jangan andalkan cek client saja.
create or replace function public.attendance_guard_masuk_log_proof()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if upper(trim(coalesce(new.tipe, ''))) <> 'MASUK' then
    return new;
  end if;

  if new.qr_token_id is null then
    raise exception 'Absen masuk wajib token QR toko.'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.attendance_qr_tokens t
    where t.id = new.qr_token_id
      and public.same_store_toko(t.toko_id, new.toko_id)
      and public.toko_belongs_to_current_tenant(t.toko_id)
      and t.expires_at > now() - interval '10 minutes'
  ) then
    raise exception 'Token QR absensi tidak valid / kedaluwarsa.'
      using errcode = '42501';
  end if;

  if new.latitude is null or new.longitude is null then
    raise exception 'Absen masuk wajib GPS.'
      using errcode = '42501';
  end if;

  if not public.point_in_store_geofence(
    new.toko_id, new.latitude, new.longitude, 40
  ) then
    raise exception 'Absen masuk di luar geofence toko.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_attendance_logs_masuk_proof on public.attendance_logs;
create trigger trg_attendance_logs_masuk_proof
  before insert on public.attendance_logs
  for each row
  execute function public.attendance_guard_masuk_log_proof();

-- -----------------------------------------------------------------------------
-- geofence_exit_logs: using(true) + tenant_seal OR = bocor semua merek
-- -----------------------------------------------------------------------------
alter table public.geofence_exit_logs
  add column if not exists tenant_id uuid references public.tenants (id);

update public.geofence_exit_logs v
set tenant_id = s.tenant_id
from public.toko_id s
where v.tenant_id is null
  and public.same_store_toko(v.toko_id, s.id);

drop policy if exists geofence_exit_logs_authenticated_all
  on public.geofence_exit_logs;
drop policy if exists geofence_exit_logs_tenant_seal
  on public.geofence_exit_logs;
drop policy if exists geofence_exit_logs_actor_insert
  on public.geofence_exit_logs;
drop policy if exists geofence_exit_logs_select
  on public.geofence_exit_logs;

create policy geofence_exit_logs_actor_insert
  on public.geofence_exit_logs
  for insert
  to authenticated
  with check (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      karyawan_id = auth.uid()
      or exists (
        select 1
        from public.karyawan k
        where k.id = karyawan_id
          and k.email is not null
          and k.email = (auth.jwt() ->> 'email')
      )
    )
    and exists (
      select 1
      from public.karyawan k
      where k.id = karyawan_id
        and public.same_store_toko(k.toko_id, toko_id)
        and k.tenant_id is not distinct from public.current_tenant_id()
    )
  );

create policy geofence_exit_logs_select
  on public.geofence_exit_logs
  for select
  to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      karyawan_id = auth.uid()
      or exists (
        select 1
        from public.karyawan k
        where k.id = karyawan_id
          and k.email is not null
          and k.email = (auth.jwt() ->> 'email')
      )
      or public.can_monitor_attendance_for_toko(toko_id)
    )
  );

revoke all on function public.attendance_guard_karyawan_toko_tenant()
  from public, anon;
revoke all on function public.attendance_guard_open_shift_unlock()
  from public, anon;
revoke all on function public.attendance_guard_masuk_log_proof()
  from public, anon;
