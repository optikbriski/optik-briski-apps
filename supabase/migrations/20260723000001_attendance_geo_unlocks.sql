-- =============================================================================
-- Geo unlock absensi: bukti lokasi dari HP karyawan (scan QR + GPS geofence).
-- Admin Absensi Toko (Mac/web OK, tanpa GPS) hanya boleh face match / masuk-pulang
-- jika ada unlock aktif untuk karyawan + toko.
-- =============================================================================

create table if not exists public.attendance_geo_unlocks (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text not null references public.toko_id (id),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  consumed_at timestamptz,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  source text not null default 'qr+gps',
  qr_token_id uuid references public.attendance_qr_tokens (id) on delete set null
);

create index if not exists attendance_geo_unlocks_lookup_idx
  on public.attendance_geo_unlocks (karyawan_id, toko_id, expires_at desc);

create index if not exists attendance_geo_unlocks_toko_expires_idx
  on public.attendance_geo_unlocks (toko_id, expires_at desc);

comment on table public.attendance_geo_unlocks is
  'Bukti singkat lokasi karyawan (QR Absensi + GPS di geofence toko) untuk Absensi Toko Admin.';

alter table public.attendance_geo_unlocks enable row level security;

revoke all on table public.attendance_geo_unlocks from anon, authenticated;
grant select, insert, update on table public.attendance_geo_unlocks to authenticated;
grant all on table public.attendance_geo_unlocks to service_role;

-- Realtime: Admin Absensi Toko mendengar unlock baru → auto face match.
do $$
begin
  alter publication supabase_realtime add table public.attendance_geo_unlocks;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

-- Karyawan: insert unlock milik sendiri saja.
drop policy if exists attendance_geo_unlocks_karyawan_insert
  on public.attendance_geo_unlocks;
create policy attendance_geo_unlocks_karyawan_insert
  on public.attendance_geo_unlocks
  for insert
  to authenticated
  with check (
    karyawan_id = auth.uid()
    or exists (
      select 1
      from public.karyawan k
      where k.id = karyawan_id
        and k.email is not null
        and k.email = (auth.jwt() ->> 'email')
    )
  );

-- Karyawan: baca unlock sendiri.
drop policy if exists attendance_geo_unlocks_karyawan_select
  on public.attendance_geo_unlocks;
create policy attendance_geo_unlocks_karyawan_select
  on public.attendance_geo_unlocks
  for select
  to authenticated
  using (
    karyawan_id = auth.uid()
    or exists (
      select 1
      from public.karyawan k
      where k.id = karyawan_id
        and k.email is not null
        and k.email = (auth.jwt() ->> 'email')
    )
  );

-- Admin: baca unlock di tokonya (atau pusat/owner semua).
drop policy if exists attendance_geo_unlocks_admin_select
  on public.attendance_geo_unlocks;
create policy attendance_geo_unlocks_admin_select
  on public.attendance_geo_unlocks
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = attendance_geo_unlocks.toko_id
        )
    )
  );

-- -----------------------------------------------------------------------------
-- Karyawan: buat unlock setelah QR valid + GPS di area (dicek di client).
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
  v_ttl integer;
  v_expires timestamptz;
  v_id uuid;
  v_source text;
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

  -- Bukti GPS wajib: QR saja tidak cukup tanpa koordinat dari HP.
  if p_latitude is null or p_longitude is null then
    raise exception
      'GPS wajib. Scan QR hanya berhasil jika HP Anda di dalam area toko.';
  end if;

  if p_qr_token_id is not null then
    if not exists (
      select 1
      from public.attendance_qr_tokens t
      where t.id = p_qr_token_id
        and t.toko_id = trim(p_toko_id)
        and t.expires_at > now() - interval '2 minutes'
    ) then
      raise exception 'Token QR absensi tidak valid untuk unlock lokasi.';
    end if;
  end if;

  -- 2–5 menit (clamp 120–300).
  v_ttl := greatest(120, least(coalesce(p_ttl_seconds, 180), 300));
  v_expires := now() + make_interval(secs => v_ttl);
  v_source := coalesce(nullif(trim(p_source), ''), 'qr+gps');

  -- Satu unlock aktif per karyawan+toko: perpendek yang lama.
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
    'source', v_source
  );
end;
$$;

revoke all on function public.create_attendance_geo_unlock(
  text, double precision, double precision, double precision, integer, uuid, text
) from public;
grant execute on function public.create_attendance_geo_unlock(
  text, double precision, double precision, double precision, integer, uuid, text
) to authenticated;

comment on function public.create_attendance_geo_unlock is
  'Karyawan: buat geo unlock singkat setelah scan QR + GPS di geofence toko.';

-- -----------------------------------------------------------------------------
-- Admin / karyawan: cek unlock aktif (belum kedaluwarsa).
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
  v_role text;
  v_admin_toko text;
  v_row public.attendance_geo_unlocks%rowtype;
  v_self boolean := false;
begin
  if v_uid is null then
    raise exception 'Login diperlukan.';
  end if;

  if p_karyawan_id is null or p_toko_id is null or length(trim(p_toko_id)) = 0 then
    raise exception 'karyawan_id dan toko_id wajib.';
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

  select p.role, p.toko_id
    into v_role, v_admin_toko
  from public.profiles p
  where p.id = v_uid;

  if not v_self then
    if v_role is null then
      raise exception 'Tidak berhak membaca status lokasi absensi.';
    end if;
    if coalesce(v_admin_toko, '') not in ('PUSAT', 'CABANG-PUSAT')
       and coalesce(v_role, '') not in ('owner', 'admin_pusat')
       and coalesce(v_admin_toko, '') <> trim(p_toko_id) then
      raise exception 'Hanya Admin toko yang bersangkutan yang boleh cek unlock.';
    end if;
  end if;

  select * into v_row
  from public.attendance_geo_unlocks u
  where u.karyawan_id = p_karyawan_id
    and u.toko_id = trim(p_toko_id)
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

revoke all on function public.get_valid_attendance_geo_unlock(uuid, text) from public;
grant execute on function public.get_valid_attendance_geo_unlock(uuid, text) to authenticated;

comment on function public.get_valid_attendance_geo_unlock(uuid, text) is
  'Cek apakah karyawan punya geo unlock aktif untuk toko (Admin Absensi Toko).';

-- -----------------------------------------------------------------------------
-- Admin: unlock terbaru di toko (untuk poll / fallback Realtime).
-- -----------------------------------------------------------------------------
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
  v_role text;
  v_admin_toko text;
  v_row public.attendance_geo_unlocks%rowtype;
begin
  if v_uid is null then
    raise exception 'Login diperlukan.';
  end if;

  if p_toko_id is null or length(trim(p_toko_id)) = 0 then
    raise exception 'toko_id wajib.';
  end if;

  select p.role, p.toko_id
    into v_role, v_admin_toko
  from public.profiles p
  where p.id = v_uid;

  if v_role is null then
    raise exception 'Hanya Admin yang boleh menunggu scan lokasi karyawan.';
  end if;

  if coalesce(v_admin_toko, '') not in ('PUSAT', 'CABANG-PUSAT')
     and coalesce(v_role, '') not in ('owner', 'admin_pusat')
     and coalesce(v_admin_toko, '') <> trim(p_toko_id) then
    raise exception 'Hanya Admin toko yang bersangkutan.';
  end if;

  select * into v_row
  from public.attendance_geo_unlocks u
  where u.toko_id = trim(p_toko_id)
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

revoke all on function public.get_latest_attendance_geo_unlock_for_toko(text)
  from public;
grant execute on function public.get_latest_attendance_geo_unlock_for_toko(text)
  to authenticated;

comment on function public.get_latest_attendance_geo_unlock_for_toko(text) is
  'Admin: unlock geo terbaru di toko (belum dipakai / belum kedaluwarsa).';

-- -----------------------------------------------------------------------------
-- Admin: tandai unlock sudah dipakai (setelah face match / batal).
-- -----------------------------------------------------------------------------
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
  v_role text;
  v_admin_toko text;
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

  select p.role, p.toko_id
    into v_role, v_admin_toko
  from public.profiles p
  where p.id = v_uid;

  if v_role is null then
    raise exception 'Hanya Admin yang boleh menandai unlock dipakai.';
  end if;

  if coalesce(v_admin_toko, '') not in ('PUSAT', 'CABANG-PUSAT')
     and coalesce(v_role, '') not in ('owner', 'admin_pusat')
     and coalesce(v_admin_toko, '') <> v_row.toko_id then
    raise exception 'Tidak berhak untuk toko ini.';
  end if;

  update public.attendance_geo_unlocks
     set consumed_at = coalesce(consumed_at, now()),
         expires_at = least(expires_at, now())
   where id = p_unlock_id;

  return jsonb_build_object('ok', true, 'id', p_unlock_id);
end;
$$;

revoke all on function public.consume_attendance_geo_unlock(uuid) from public;
grant execute on function public.consume_attendance_geo_unlock(uuid)
  to authenticated;

comment on function public.consume_attendance_geo_unlock(uuid) is
  'Admin: tandai geo unlock sudah diproses (face match selesai / dibatalkan).';
