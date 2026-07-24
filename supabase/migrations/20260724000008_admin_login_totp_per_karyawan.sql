-- =============================================================================
-- Login kode Admin: TOTP unik per karyawan + audit siapa yang login.
--
-- Siapa boleh tampilkan kode di APK:
--   • Toko PUSAT → semua karyawan Aktif (kepengawasan; keputusan ter-track)
--   • Cabang     → hanya jabatan Kepala Toko
--
-- Kode dihitung dari HMAC(master_secret, karyawan_id) → TOTP 6 digit / 10 dtk.
-- =============================================================================

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

-- Admin yang login boleh lihat jejak sendiri (opsional UI).
drop policy if exists admin_login_code_audit_select_own on public.admin_login_code_audit;
create policy admin_login_code_audit_select_own
  on public.admin_login_code_audit
  for select
  to authenticated
  using (admin_user_id = auth.uid());

-- Eligible: PUSAT semua Aktif; cabang hanya Kepala Toko Aktif
create or replace function public.karyawan_can_show_admin_login_code(
  p_toko_id text,
  p_jabatan text,
  p_status text
)
returns boolean
language sql
immutable
as $$
  select
    coalesce(p_status, '') = 'Aktif'
    and (
      upper(trim(coalesce(p_toko_id, ''))) = 'PUSAT'
      or lower(trim(coalesce(p_jabatan, ''))) = 'kepala toko'
    );
$$;

-- Secret turunan per karyawan (tidak disimpan; dihitung dari master)
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
  v_secret bytea;
  v_code text;
  v_expires integer;
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

  v_secret := public.admin_totp_secret_for_karyawan(v_cfg.secret, v_uid);
  v_code := public.admin_totp_at(
    v_secret, v_cfg.period_seconds, v_cfg.digits, v_now
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
    'digits', v_cfg.digits,
    'karyawan_id', v_uid,
    'nama', v_nama,
    'toko_id', v_toko,
    'jabatan', v_jabatan
  );
end;
$$;

revoke all on function public.get_admin_login_code() from public;
grant execute on function public.get_admin_login_code() to authenticated;

-- Resolve kode → karyawan (window ±1). Service role only.
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
  v_secret bytea;
  v_ok boolean;
begin
  if length(v_code) < 6 then
    return null;
  end if;

  select * into v_cfg
  from public.admin_login_totp_config
  where id = 'pusat';

  if not found or not coalesce(v_cfg.enabled, false) then
    return null;
  end if;

  if length(v_code) <> v_cfg.digits then
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
  loop
    v_secret := public.admin_totp_secret_for_karyawan(v_cfg.secret, v_row.id);
    v_ok :=
      v_code = public.admin_totp_at(
        v_secret, v_cfg.period_seconds, v_cfg.digits, v_now
      )
      or v_code = public.admin_totp_at(
        v_secret, v_cfg.period_seconds, v_cfg.digits, v_now - v_period
      )
      or v_code = public.admin_totp_at(
        v_secret, v_cfg.period_seconds, v_cfg.digits, v_now + v_period
      );

    if v_ok then
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

-- Compat: verify_admin_login_totp → true jika resolve sukses
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
  'Kode TOTP unik per karyawan. PUSAT: semua Aktif; cabang: Kepala Toko saja.';
comment on function public.resolve_admin_login_totp is
  'Service role: kode → identitas karyawan (untuk audit login Admin).';
comment on table public.admin_login_code_audit is
  'Jejak login Admin via kode APK: siapa karyawan yang memberi akses.';
