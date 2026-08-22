-- =============================================================================
-- 000022 — Geofence toko end-to-end.
-- Apply di SQL Editor live SETELAH 000021.
--
-- toko_id_auth_tenant FOR ALL = siapa pun di usaha bisa ubah lat/lng/radius
-- toko mana pun. Karyawan bisa perlebar area lalu absen dari luar toko.
-- =============================================================================

create or replace function public.can_manage_geofence_for_toko(p_toko text)
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

comment on function public.can_manage_geofence_for_toko(text) is
  'Ubah geofence: pusat semua toko tenant; admin_toko toko sendiri. Bukan karyawan.';

revoke all on function public.can_manage_geofence_for_toko(text)
  from public, anon;
grant execute on function public.can_manage_geofence_for_toko(text)
  to authenticated, service_role;

-- Jangan biarkan RPC geometri dipanggil anon/authenticated untuk memetakan merek lain.
-- RPC absensi SECURITY DEFINER tetap bisa memanggil.
revoke all on function public.point_in_toko_geofence(
  text, double precision, double precision, double precision
) from public, anon, authenticated;
grant execute on function public.point_in_toko_geofence(
  text, double precision, double precision, double precision
) to service_role;

revoke all on function public.point_in_store_geofence(
  text, double precision, double precision, double precision
) from public, anon, authenticated;
grant execute on function public.point_in_store_geofence(
  text, double precision, double precision, double precision
) to service_role;

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
    (
      public.is_platform_user()
      or public.toko_belongs_to_current_tenant(p_toko_id)
    )
    and (
      public.point_in_toko_geofence(p_toko_id, p_lat, p_lng, p_buffer_meters)
      or (
        public.is_pusat_toko_id(p_toko_id)
        and (
          public.point_in_toko_geofence('PUSAT', p_lat, p_lng, p_buffer_meters)
          or public.point_in_toko_geofence(
            'CABANG-PUSAT', p_lat, p_lng, p_buffer_meters
          )
        )
      )
    );
$$;

-- Batas ukuran area (selaras UI 10–500 m). Polygon tidak boleh seluas kota.
create or replace function public.geofence_polygon_extent_ok(p_polygon jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  n int;
  i int;
  j int;
  yi double precision;
  xi double precision;
  yj double precision;
  xj double precision;
  v_dist double precision;
begin
  if p_polygon is null or jsonb_typeof(p_polygon) <> 'array' then
    return false;
  end if;
  n := jsonb_array_length(p_polygon);
  if n < 3 or n > 8 then
    return false;
  end if;

  for i in 0..n - 1 loop
    yi := (p_polygon -> i ->> 'lat')::double precision;
    xi := coalesce(
      (p_polygon -> i ->> 'lng')::double precision,
      (p_polygon -> i ->> 'lon')::double precision
    );
    if yi is null or xi is null
       or yi < -90 or yi > 90 or xi < -180 or xi > 180 then
      return false;
    end if;
    for j in i + 1..n - 1 loop
      yj := (p_polygon -> j ->> 'lat')::double precision;
      xj := coalesce(
        (p_polygon -> j ->> 'lng')::double precision,
        (p_polygon -> j ->> 'lon')::double precision
      );
      if yj is null or xj is null then
        return false;
      end if;
      v_dist := public.haversine_meters(yi, xi, yj, xj);
      if v_dist > 2000 then
        return false;
      end if;
    end loop;
  end loop;
  return true;
end;
$$;

revoke all on function public.geofence_polygon_extent_ok(jsonb)
  from public, anon;
grant execute on function public.geofence_polygon_extent_ok(jsonb)
  to authenticated, service_role;

create or replace function public.toko_id_guard_geofence()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text;
begin
  if tg_op = 'UPDATE' then
    if not public.is_platform_user() then
      new.id := old.id;
      new.tenant_id := old.tenant_id;
      if new.cabang_code is distinct from old.cabang_code then
        new.cabang_code := old.cabang_code;
      end if;
      if new.is_pusat is distinct from old.is_pusat then
        new.is_pusat := old.is_pusat;
      end if;
    end if;

    if old.latitude is distinct from new.latitude
       or old.longitude is distinct from new.longitude
       or old.radius_meters is distinct from new.radius_meters
       or old.geofence_mode is distinct from new.geofence_mode
       or old.geofence_polygon is distinct from new.geofence_polygon then
      if not public.can_manage_geofence_for_toko(old.id) then
        raise exception 'Hanya admin toko/cabang yang berhak mengubah geofence.'
          using errcode = '42501';
      end if;

      v_mode := lower(trim(coalesce(new.geofence_mode, 'circle')));
      if v_mode not in ('circle', 'polygon') then
        raise exception 'Mode geofence hanya circle atau polygon.'
          using errcode = '42501';
      end if;
      new.geofence_mode := v_mode;

      if new.latitude is not null
         and (new.latitude < -90 or new.latitude > 90) then
        raise exception 'latitude geofence tidak valid.' using errcode = '42501';
      end if;
      if new.longitude is not null
         and (new.longitude < -180 or new.longitude > 180) then
        raise exception 'longitude geofence tidak valid.' using errcode = '42501';
      end if;

      new.radius_meters := least(500, greatest(10, coalesce(new.radius_meters, 100)));

      if v_mode = 'polygon' then
        if not public.geofence_polygon_extent_ok(new.geofence_polygon) then
          raise exception
            'Polygon geofence wajib 3–8 titik di area toko (maks ~2 km).'
            using errcode = '42501';
        end if;
      else
        if new.latitude is null or new.longitude is null then
          raise exception 'Geofence lingkaran wajib titik pusat.'
            using errcode = '42501';
        end if;
        new.geofence_polygon := null;
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_toko_id_guard_geofence on public.toko_id;
create trigger trg_toko_id_guard_geofence
  before update on public.toko_id
  for each row
  execute function public.toko_id_guard_geofence();

drop policy if exists toko_id_auth_tenant on public.toko_id;
drop policy if exists toko_id_tenant_seal on public.toko_id;
drop policy if exists toko_id_auth_select on public.toko_id;
drop policy if exists toko_id_auth_update on public.toko_id;
drop policy if exists toko_id_auth_insert on public.toko_id;
drop policy if exists toko_id_auth_delete on public.toko_id;

-- Baca daftar/koordinat: staf usaha sendiri (POS, absen, peta). Bukan merek lain.
create policy toko_id_auth_select
  on public.toko_id
  for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user());

-- Ubah geofence: hanya admin yang berhak untuk toko itu.
create policy toko_id_auth_update_geofence
  on public.toko_id
  for update to authenticated
  using (public.can_manage_geofence_for_toko(id))
  with check (public.can_manage_geofence_for_toko(id));

-- Cabang baru lewat RPC DEFINER. Client biasa tidak menambah/hapus toko.
create policy toko_id_auth_insert
  on public.toko_id
  for insert to authenticated
  with check (
    public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and public.current_profile_role() in ('owner', 'super_admin')
    )
  );

create policy toko_id_auth_delete
  on public.toko_id
  for delete to authenticated
  using (
    public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and public.current_profile_role() in ('owner', 'super_admin')
    )
  );

revoke all on function public.toko_id_guard_geofence() from public, anon;
