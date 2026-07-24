-- =============================================================================
-- LOGIN KODE ADMIN — SQL LENGKAP (jalankan sekali di SQL Editor)
-- Menggabungkan aturan final:
--   • Periode 10 detik, kode 6 angka
--   • Digit 1 = posisi: 1 Owner · 2 Admin · 3 Kepala Area · 4 Kepala Toko
--   • Digit 2–6 unik per karyawan (tidak bentrok saat login bersamaan)
--   • PUSAT: jabatan Admin / Owner saja yang boleh lihat kode
--   • Cabang: Kepala Toko / Kepala Area
--   • Frontliner / Backliner: tidak punya kode
--   • Audit: siapa karyawan yang memberi kode saat login web
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Config + rate limit
-- -----------------------------------------------------------------------------
create table if not exists public.admin_login_totp_config (
  id text primary key,
  secret bytea not null,
  period_seconds integer not null default 10
    check (period_seconds >= 5 and period_seconds <= 60),
  digits integer not null default 6
    check (digits >= 6 and digits <= 8),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table public.admin_login_totp_config is
  'Secret master login kode Admin. Tidak pernah diekspos ke client.';

insert into public.admin_login_totp_config (id, secret, period_seconds, digits, enabled)
values ('pusat', gen_random_bytes(20), 10, 6, true)
on conflict (id) do nothing;

create table if not exists public.admin_login_totp_attempts (
  id bigserial primary key,
  email text not null,
  success boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists admin_login_totp_attempts_email_created_idx
  on public.admin_login_totp_attempts (email, created_at desc);

alter table public.admin_login_totp_config enable row level security;
alter table public.admin_login_totp_attempts enable row level security;

-- -----------------------------------------------------------------------------
-- Audit: track karyawan pemberi kode
-- -----------------------------------------------------------------------------
create table if not exists public.admin_login_code_audit (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id),
  karyawan_nama text,
  karyawan_toko_id text,
  karyawan_jabatan text,
  admin_user_id uuid references auth.users (id),
  admin_email text,
  admin_role text,
  admin_toko_id text,
  created_at timestamptz not null default now()
);

create index if not exists admin_login_code_audit_created_idx
  on public.admin_login_code_audit (created_at desc);
create index if not exists admin_login_code_audit_karyawan_idx
  on public.admin_login_code_audit (karyawan_id, created_at desc);
create index if not exists admin_login_code_audit_admin_idx
  on public.admin_login_code_audit (admin_user_id, created_at desc);

alter table public.admin_login_code_audit enable row level security;

drop policy if exists admin_login_code_audit_select_own on public.admin_login_code_audit;
create policy admin_login_code_audit_select_own
  on public.admin_login_code_audit
  for select
  to authenticated
  using (admin_user_id = auth.uid());

comment on table public.admin_login_code_audit is
  'Jejak login Admin via kode APK: siapa karyawan pemberi akses.';

-- -----------------------------------------------------------------------------
-- Helper crypto (legacy TOTP + secret per karyawan)
-- -----------------------------------------------------------------------------
create or replace function public.admin_totp_at(
  p_secret bytea,
  p_period integer,
  p_digits integer,
  p_at timestamptz
)
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_counter bigint;
  v_buf bytea := '\x0000000000000000'::bytea;
  v_hash bytea;
  v_offset integer;
  v_bin integer;
  v_mod integer;
  v_i integer;
begin
  v_counter := floor(extract(epoch from p_at) / p_period)::bigint;
  for v_i in 0..7 loop
    v_buf := set_byte(v_buf, 7 - v_i, ((v_counter >> (8 * v_i)) & 255)::integer);
  end loop;

  v_hash := hmac(v_buf, p_secret, 'sha1');
  v_offset := get_byte(v_hash, length(v_hash) - 1) & 15;
  v_bin :=
    ((get_byte(v_hash, v_offset) & 127) << 24)
    | ((get_byte(v_hash, v_offset + 1) & 255) << 16)
    | ((get_byte(v_hash, v_offset + 2) & 255) << 8)
    | (get_byte(v_hash, v_offset + 3) & 255);

  v_mod := (power(10, p_digits))::integer;
  return lpad((v_bin % v_mod)::text, p_digits, '0');
end;
$$;

create or replace function public.admin_totp_secret_for_karyawan(
  p_master bytea,
  p_karyawan_id uuid
)
returns bytea
language sql
immutable
set search_path = public, extensions
as $$
  select hmac(convert_to(p_karyawan_id::text, 'UTF8'), p_master, 'sha1');
$$;

-- -----------------------------------------------------------------------------
-- Siapa boleh lihat kode di APK
-- -----------------------------------------------------------------------------
create or replace function public.karyawan_can_show_admin_login_code(
  p_toko_id text,
  p_jabatan text,
  p_status text
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_jab text := lower(trim(coalesce(p_jabatan, '')));
begin
  if coalesce(p_status, '') <> 'Aktif' then
    return false;
  end if;

  if v_jab in ('frontliner', 'backliner') then
    return false;
  end if;

  if v_toko = 'PUSAT' then
    return v_jab in ('admin', 'owner');
  end if;

  return v_jab in ('kepala toko', 'kepala area');
end;
$$;

comment on function public.karyawan_can_show_admin_login_code is
  'PUSAT: Admin/Owner. Cabang: Kepala Toko/Kepala Area. Front/Back: tidak.';

-- -----------------------------------------------------------------------------
-- Format kode: digit1 posisi + 5 digit unik
-- 1 Owner · 2 Admin · 3 Kepala Area · 4 Kepala Toko
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- RPC: APK minta kode
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- Resolve kode → karyawan (Edge Function / service_role)
-- -----------------------------------------------------------------------------
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

create or replace function public.verify_admin_login_totp(p_code text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.resolve_admin_login_totp(p_code) is not null;
$$;

revoke all on function public.verify_admin_login_totp(text) from public;
grant execute on function public.verify_admin_login_totp(text) to service_role;

-- -----------------------------------------------------------------------------
-- Rate limit + catat attempt / sukses audit
-- -----------------------------------------------------------------------------
create or replace function public.admin_login_totp_allow_attempt(p_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_fails integer;
begin
  if v_email = '' then
    return false;
  end if;

  select count(*)::integer into v_fails
  from public.admin_login_totp_attempts
  where email = v_email
    and success = false
    and created_at > now() - interval '5 minutes';

  return coalesce(v_fails, 0) < 5;
end;
$$;

revoke all on function public.admin_login_totp_allow_attempt(text) from public;
grant execute on function public.admin_login_totp_allow_attempt(text) to service_role;

create or replace function public.admin_login_totp_record_attempt(
  p_email text,
  p_success boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_login_totp_attempts (email, success)
  values (lower(trim(coalesce(p_email, ''))), coalesce(p_success, false));

  delete from public.admin_login_totp_attempts
  where created_at < now() - interval '1 day';
end;
$$;

revoke all on function public.admin_login_totp_record_attempt(text, boolean) from public;
grant execute on function public.admin_login_totp_record_attempt(text, boolean)
  to service_role;

create or replace function public.admin_login_code_record_success(
  p_karyawan_id uuid,
  p_admin_user_id uuid,
  p_admin_email text,
  p_admin_role text,
  p_admin_toko_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_nama text;
  v_toko text;
  v_jabatan text;
begin
  select k.nama, upper(trim(k.toko_id)), k.jabatan
    into v_nama, v_toko, v_jabatan
  from public.karyawan k
  where k.id = p_karyawan_id;

  insert into public.admin_login_code_audit (
    karyawan_id,
    karyawan_nama,
    karyawan_toko_id,
    karyawan_jabatan,
    admin_user_id,
    admin_email,
    admin_role,
    admin_toko_id
  ) values (
    p_karyawan_id,
    v_nama,
    v_toko,
    v_jabatan,
    p_admin_user_id,
    lower(trim(coalesce(p_admin_email, ''))),
    lower(trim(coalesce(p_admin_role, ''))),
    upper(trim(coalesce(p_admin_toko_id, '')))
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_login_code_record_success(
  uuid, uuid, text, text, text
) from public;
grant execute on function public.admin_login_code_record_success(
  uuid, uuid, text, text, text
) to service_role;

comment on function public.get_admin_login_code is
  'Kode 6 angka: digit1=1 Owner / 2 Admin / 3 Kepala Area / 4 Kepala Toko; '
  'digit2-6 unik per orang per 10 dtk.';
comment on function public.resolve_admin_login_totp is
  'Service role: kode → identitas karyawan (audit login Admin).';
