-- Kode login Admin: 6 digit angka.
-- Digit 1 = posisi (prefix), digit 2–6 = unik per karyawan per jendela 10 dtk.
--
-- Prefix:
--   1 = Owner
--   2 = Admin
--   3 = Kepala Area
--   4 = Kepala Toko

create or replace function public.admin_login_jabatan_prefix(p_jabatan text)
returns text
language sql
immutable
as $$
  select case lower(trim(coalesce(p_jabatan, '')))
    when 'owner' then '1'
    when 'admin' then '2'
    when 'kepala area' then '3'
    when 'kepala toko' then '4'
    else null
  end;
$$;

-- 5 digit (00000–99999) dari HMAC(secret, karyawan_id || ':' || counter)
create or replace function public.admin_login_code_suffix(
  p_secret bytea,
  p_karyawan_id uuid,
  p_counter bigint
)
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_msg bytea;
  v_hash bytea;
  v_n bigint;
begin
  v_msg := convert_to(p_karyawan_id::text || ':' || p_counter::text, 'UTF8');
  v_hash := hmac(v_msg, p_secret, 'sha1');
  -- Ambil 4 byte → mod 100000 → selalu 5 digit, unik per (karyawan, counter)
  v_n := (
    ((get_byte(v_hash, 0)::bigint & 127) << 24)
    | ((get_byte(v_hash, 1)::bigint & 255) << 16)
    | ((get_byte(v_hash, 2)::bigint & 255) << 8)
    | (get_byte(v_hash, 3)::bigint & 255)
  ) % 100000;
  return lpad(v_n::text, 5, '0');
end;
$$;

create or replace function public.admin_login_code_for(
  p_master bytea,
  p_karyawan_id uuid,
  p_jabatan text,
  p_at timestamptz,
  p_period integer
)
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_prefix text;
  v_counter bigint;
  v_secret bytea;
  v_suffix text;
begin
  v_prefix := public.admin_login_jabatan_prefix(p_jabatan);
  if v_prefix is null then
    return null;
  end if;

  v_counter := floor(extract(epoch from p_at) / p_period)::bigint;
  v_secret := public.admin_totp_secret_for_karyawan(p_master, p_karyawan_id);
  v_suffix := public.admin_login_code_suffix(v_secret, p_karyawan_id, v_counter);
  return v_prefix || v_suffix;
end;
$$;

create or replace function public.get_admin_login_code()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_toko text;
  v_status text;
  v_jabatan text;
  v_nama text;
  v_cfg public.admin_login_totp_config%rowtype;
  v_now timestamptz := clock_timestamp();
  v_epoch double precision;
  v_code text;
  v_expires integer;
  v_prefix text;
begin
  if v_uid is null then
    raise exception 'Login karyawan diperlukan.';
  end if;

  select
    upper(trim(k.toko_id)),
    k.status_approval,
    k.jabatan,
    k.nama
  into v_toko, v_status, v_jabatan, v_nama
  from public.karyawan k
  where k.id = v_uid;

  if v_toko is null then
    raise exception 'Data karyawan tidak ditemukan.';
  end if;

  if not public.karyawan_can_show_admin_login_code(v_toko, v_jabatan, v_status) then
    if coalesce(v_status, '') <> 'Aktif' then
      raise exception 'Akun karyawan belum aktif.';
    end if;
    raise exception
      'Kode login Admin: PUSAT (Admin/Owner), atau cabang (Kepala Toko / Kepala Area).';
  end if;

  select * into v_cfg
  from public.admin_login_totp_config
  where id = 'pusat';

  if not found or not coalesce(v_cfg.enabled, false) then
    raise exception 'Login kode Admin belum diaktifkan.';
  end if;

  v_prefix := public.admin_login_jabatan_prefix(v_jabatan);
  if v_prefix is null then
    raise exception 'Jabatan tidak punya prefix kode login.';
  end if;

  v_code := public.admin_login_code_for(
    v_cfg.secret, v_uid, v_jabatan, v_now, v_cfg.period_seconds
  );

  v_epoch := extract(epoch from v_now);
  v_expires := v_cfg.period_seconds
    - (floor(v_epoch)::bigint % v_cfg.period_seconds)::integer;
  if v_expires = 0 then
    v_expires := v_cfg.period_seconds;
  end if;

  return jsonb_build_object(
    'code', v_code,
    'expires_in', v_expires,
    'period', v_cfg.period_seconds,
    'digits', 6,
    'prefix', v_prefix,
    'karyawan_id', v_uid,
    'nama', v_nama,
    'toko_id', v_toko,
    'jabatan', v_jabatan
  );
end;
$$;

revoke all on function public.get_admin_login_code() from public;
grant execute on function public.get_admin_login_code() to authenticated;

create or replace function public.resolve_admin_login_totp(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_cfg public.admin_login_totp_config%rowtype;
  v_now timestamptz := clock_timestamp();
  v_code text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
  v_period interval;
  v_row record;
  v_candidate text;
begin
  if length(v_code) <> 6 then
    return null;
  end if;

  select * into v_cfg
  from public.admin_login_totp_config
  where id = 'pusat';

  if not found or not coalesce(v_cfg.enabled, false) then
    return null;
  end if;

  v_period := make_interval(secs => v_cfg.period_seconds);

  for v_row in
    select k.id, k.nama, k.toko_id, k.jabatan, k.status_approval
    from public.karyawan k
    where k.status_approval = 'Aktif'
      and public.karyawan_can_show_admin_login_code(
        k.toko_id, k.jabatan, k.status_approval
      )
      -- Filter cepat lewat digit depan (posisi)
      and public.admin_login_jabatan_prefix(k.jabatan) = left(v_code, 1)
  loop
    v_candidate := public.admin_login_code_for(
      v_cfg.secret, v_row.id, v_row.jabatan, v_now, v_cfg.period_seconds
    );
    if v_candidate = v_code then
      return jsonb_build_object(
        'karyawan_id', v_row.id,
        'nama', v_row.nama,
        'toko_id', upper(trim(coalesce(v_row.toko_id, ''))),
        'jabatan', v_row.jabatan
      );
    end if;

    v_candidate := public.admin_login_code_for(
      v_cfg.secret, v_row.id, v_row.jabatan,
      v_now - v_period, v_cfg.period_seconds
    );
    if v_candidate = v_code then
      return jsonb_build_object(
        'karyawan_id', v_row.id,
        'nama', v_row.nama,
        'toko_id', upper(trim(coalesce(v_row.toko_id, ''))),
        'jabatan', v_row.jabatan
      );
    end if;

    v_candidate := public.admin_login_code_for(
      v_cfg.secret, v_row.id, v_row.jabatan,
      v_now + v_period, v_cfg.period_seconds
    );
    if v_candidate = v_code then
      return jsonb_build_object(
        'karyawan_id', v_row.id,
        'nama', v_row.nama,
        'toko_id', upper(trim(coalesce(v_row.toko_id, ''))),
        'jabatan', v_row.jabatan
      );
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.resolve_admin_login_totp(text) from public;
grant execute on function public.resolve_admin_login_totp(text) to service_role;

comment on function public.get_admin_login_code is
  'Kode 6 digit: digit1=posisi (1 Owner,2 Admin,3 Kepala Area,4 Kepala Toko), '
  'digit2-6 unik per orang per 10 dtk.';
