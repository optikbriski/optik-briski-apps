-- =============================================================================
-- Absensi mutlak di dalam geofence (dicek SERVER) + hanya saat dijadwalkan.
-- Absen masuk: wajib jadwal + di dalam geofence (boleh sebelum jam standby).
-- Peringatan keluar area / standby (app): pagi ≥ 08:30, siang ≥ 13:00.
-- Telat tetap dihitung dari jam_masuk jadwal (app).
-- =============================================================================

-- Haversine meter (WGS84)
create or replace function public.haversine_meters(
  lat1 double precision,
  lng1 double precision,
  lat2 double precision,
  lng2 double precision
)
returns double precision
language sql
immutable
as $$
  select 6371000.0 * 2.0 * asin(
    sqrt(
      power(sin(radians(lat2 - lat1) / 2.0), 2)
      + cos(radians(lat1)) * cos(radians(lat2))
        * power(sin(radians(lng2 - lng1) / 2.0), 2)
    )
  );
$$;

-- Point-in-polygon (ray casting). polygon jsonb: [{"lat":..,"lng":..}, ...]
create or replace function public.point_in_geofence_polygon(
  p_polygon jsonb,
  p_lat double precision,
  p_lng double precision
)
returns boolean
language plpgsql
immutable
as $$
declare
  n int;
  i int;
  j int;
  yi double precision;
  yj double precision;
  xi double precision;
  xj double precision;
  inside boolean := false;
begin
  if p_polygon is null or jsonb_typeof(p_polygon) <> 'array' then
    return false;
  end if;
  n := jsonb_array_length(p_polygon);
  if n < 3 then
    return false;
  end if;

  j := n - 1;
  for i in 0..n - 1 loop
    yi := (p_polygon -> i ->> 'lat')::double precision;
    xi := coalesce(
      (p_polygon -> i ->> 'lng')::double precision,
      (p_polygon -> i ->> 'lon')::double precision
    );
    yj := (p_polygon -> j ->> 'lat')::double precision;
    xj := coalesce(
      (p_polygon -> j ->> 'lng')::double precision,
      (p_polygon -> j ->> 'lon')::double precision
    );
    if xi is null or yi is null or xj is null or yj is null then
      return false;
    end if;
    if ((yi > p_lat) <> (yj > p_lat))
       and (
         p_lng < (xj - xi) * (p_lat - yi)
           / nullif(yj - yi, 0)
           + xi
       )
    then
      inside := not inside;
    end if;
    j := i;
  end loop;
  return inside;
end;
$$;

-- True jika (lat,lng) di dalam geofence toko. buffer_meters untuk GPS noise.
create or replace function public.point_in_toko_geofence(
  p_toko_id text,
  p_lat double precision,
  p_lng double precision,
  p_buffer_meters double precision default 8
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mode text;
  v_lat double precision;
  v_lng double precision;
  v_radius integer;
  v_poly jsonb;
  v_dist double precision;
  v_buf double precision;
begin
  if p_toko_id is null or length(trim(p_toko_id)) = 0 then
    return false;
  end if;
  if p_lat is null or p_lng is null then
    return false;
  end if;
  if p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    return false;
  end if;

  v_buf := greatest(0, least(coalesce(p_buffer_meters, 8), 40));

  select
    lower(coalesce(t.geofence_mode, 'circle')),
    t.latitude,
    t.longitude,
    coalesce(t.radius_meters, 100),
    t.geofence_polygon
  into v_mode, v_lat, v_lng, v_radius, v_poly
  from public.toko_id t
  where t.id = trim(p_toko_id);

  if not found then
    return false;
  end if;

  if v_mode = 'polygon' and v_poly is not null
     and jsonb_typeof(v_poly) = 'array'
     and jsonb_array_length(v_poly) >= 3 then
    if public.point_in_geofence_polygon(v_poly, p_lat, p_lng) then
      return true;
    end if;
    -- Buffer sederhana: jarak ke centroid ≤ buffer (approksimasi tepi).
    -- Untuk ketat, tanpa buffer polygon jika di luar.
    return false;
  end if;

  if v_lat is null or v_lng is null then
    return false; -- geofence belum di-set → tolak absen
  end if;

  v_dist := public.haversine_meters(v_lat, v_lng, p_lat, p_lng);
  return v_dist <= (v_radius::double precision + v_buf);
end;
$$;

revoke all on function public.point_in_toko_geofence(text, double precision, double precision, double precision)
  from public;
grant execute on function public.point_in_toko_geofence(text, double precision, double precision, double precision)
  to authenticated;

-- Tanggal Jakarta hari ini
create or replace function public.jakarta_today()
returns date
language sql
stable
as $$
  select (timezone('Asia/Jakarta', now()))::date;
$$;

-- Harden create_attendance_geo_unlock
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
  v_jam_masuk time;
  v_is_libur boolean;
  v_today date;
  v_buf double precision;
  v_is_pulang boolean;
begin
  if v_uid is null then
    raise exception 'Login karyawan diperlukan untuk verifikasi lokasi.';
  end if;

  if p_toko_id is null or length(trim(p_toko_id)) = 0 then
    raise exception 'toko_id wajib diisi.';
  end if;

  if not exists (select 1 from public.toko_id t where t.id = trim(p_toko_id)) then
    raise exception 'Toko % tidak ditemukan.', trim(p_toko_id);
  end if;

  -- GPS wajib
  if p_latitude is null or p_longitude is null then
    raise exception
      'GPS wajib. Absen hanya berhasil jika HP Anda di dalam area toko.';
  end if;

  -- QR wajib (tidak boleh unlock tanpa token toko)
  if p_qr_token_id is null then
    raise exception 'QR Absensi wajib. Scan QR di perangkat toko dulu.';
  end if;

  if not exists (
    select 1
    from public.attendance_qr_tokens t
    where t.id = p_qr_token_id
      and t.toko_id = trim(p_toko_id)
      and t.expires_at > now() - interval '2 minutes'
  ) then
    raise exception 'Token QR absensi tidak valid / kedaluwarsa.';
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

  if coalesce(trim(v_karyawan_toko), '') <> trim(p_toko_id) then
    raise exception 'Lokasi unlock hanya untuk toko Anda (%).',
      coalesce(trim(v_karyawan_toko), '-');
  end if;

  v_source := coalesce(nullif(trim(p_source), ''), 'qr+gps');
  v_is_pulang := position('pulang' in lower(v_source)) > 0;
  v_today := public.jakarta_today();

  -- Buffer GPS (selaras app: max ~40m, default 8 / 0.4*accuracy)
  v_buf := 8;
  if p_accuracy_meters is not null and p_accuracy_meters > 0 then
    v_buf := least(40, greatest(0, p_accuracy_meters * 0.4));
  end if;

  -- Geofence SERVER — mutlak
  if not public.point_in_toko_geofence(
    trim(p_toko_id), p_latitude, p_longitude, v_buf
  ) then
    raise exception
      'Di luar geofence toko. Absen ditolak. Pastikan GPS akurat dan Anda di area toko.';
  end if;

  -- Masuk: wajib jadwal hari ini (boleh absen sebelum jam standby)
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
     and toko_id = trim(p_toko_id)
     and expires_at > now();

  insert into public.attendance_geo_unlocks (
    karyawan_id,
    toko_id,
    expires_at,
    latitude,
    longitude,
    accuracy_meters,
    source,
    qr_token_id
  ) values (
    v_karyawan_id,
    trim(p_toko_id),
    v_expires,
    p_latitude,
    p_longitude,
    p_accuracy_meters,
    v_source,
    p_qr_token_id
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'karyawan_id', v_karyawan_id,
    'toko_id', trim(p_toko_id),
    'expires_at', v_expires,
    'ttl_seconds', v_ttl,
    'latitude', p_latitude,
    'longitude', p_longitude,
    'accuracy_meters', p_accuracy_meters,
    'source', v_source,
    'geofence_ok', true
  );
end;
$$;

comment on function public.create_attendance_geo_unlock is
  'Karyawan: unlock absen. Wajib QR + GPS di dalam geofence (dicek server). '
  'Masuk: wajib jadwal + GPS di dalam geofence; absen boleh sebelum jam standby.';
