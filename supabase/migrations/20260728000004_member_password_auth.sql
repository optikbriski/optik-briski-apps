-- =============================================================================
-- Member: login email/HP + password, daftar, lupa password
-- =============================================================================

create extension if not exists pgcrypto;

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null unique,
  phone_raw text,
  nama text,
  email text,
  alamat text,
  font_scale numeric not null default 1.0,
  locale text not null default 'id',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.members
  add column if not exists password_hash text;

-- Email unik (case-insensitive) bila diisi
create unique index if not exists members_email_lower_uidx
  on public.members (lower(trim(email)))
  where nullif(trim(email), '') is not null;

create table if not exists public.member_otp (
  phone_e164 text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

-- Reset password pakai identifier (phone e164 atau email lower)
create table if not exists public.member_password_resets (
  identifier text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.members enable row level security;
alter table public.member_password_resets enable row level security;

create or replace function public.wa_digits(p text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      case
        when regexp_replace(coalesce(p, ''), '\D', '', 'g') ~ '^0'
          then '62' || substr(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 2)
        else regexp_replace(coalesce(p, ''), '\D', '', 'g')
      end,
      '\D',
      '',
      'g'
    ),
    ''
  );
$$;

create or replace function public.member_public_row(v public.members)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', v.id,
    'phone_e164', v.phone_e164,
    'phone_raw', v.phone_raw,
    'nama', v.nama,
    'email', v.email,
    'alamat', v.alamat,
    'font_scale', v.font_scale,
    'locale', v.locale
  );
$$;

-- Daftar akun baru
create or replace function public.member_register(
  p_phone text,
  p_password text,
  p_nama text default null,
  p_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_pass text := coalesce(p_password, '');
  v_member public.members%rowtype;
begin
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
  end if;
  if length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password minimal 6 karakter');
  end if;
  if exists (select 1 from public.members m where m.phone_e164 = v_phone) then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP sudah terdaftar. Silakan masuk.');
  end if;
  if v_email is not null and exists (
    select 1 from public.members m where lower(trim(m.email)) = v_email
  ) then
    return jsonb_build_object('ok', false, 'error', 'Email sudah terdaftar. Silakan masuk.');
  end if;

  insert into public.members (
    phone_e164, phone_raw, nama, email, password_hash
  ) values (
    v_phone,
    trim(p_phone),
    nullif(trim(coalesce(p_nama, '')), ''),
    v_email,
    crypt(v_pass, gen_salt('bf'))
  )
  returning * into v_member;

  return jsonb_build_object(
    'ok', true,
    'member', public.member_public_row(v_member)
  );
end;
$$;

-- Login: identifier = email ATAU nomor HP
create or replace function public.member_login(
  p_identifier text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := trim(coalesce(p_identifier, ''));
  v_pass text := coalesce(p_password, '');
  v_member public.members%rowtype;
  v_phone text;
begin
  if v_id = '' or v_pass = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi email/HP dan password');
  end if;

  if position('@' in v_id) > 0 then
    select * into v_member
    from public.members m
    where lower(trim(m.email)) = lower(v_id)
    limit 1;
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    select * into v_member
    from public.members m
    where m.phone_e164 = v_phone
    limit 1;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan. Daftar dulu.');
  end if;

  if v_member.password_hash is null or trim(v_member.password_hash) = '' then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Akun ini belum punya password. Pakai OTP atau atur via Lupa password.'
    );
  end if;

  if crypt(v_pass, v_member.password_hash) <> v_member.password_hash then
    return jsonb_build_object('ok', false, 'error', 'Password salah');
  end if;

  update public.members set updated_at = now() where id = v_member.id;

  return jsonb_build_object(
    'ok', true,
    'member', public.member_public_row(v_member)
  );
end;
$$;

-- Minta kode reset (debug_code dikembalikan sementara seperti OTP)
create or replace function public.member_request_password_reset(p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := trim(coalesce(p_identifier, ''));
  v_phone text;
  v_key text;
  v_member public.members%rowtype;
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
begin
  if v_id = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi email atau nomor HP');
  end if;

  if position('@' in v_id) > 0 then
    select * into v_member
    from public.members m
    where lower(trim(m.email)) = lower(v_id)
    limit 1;
    v_key := 'email:' || lower(v_id);
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    select * into v_member
    from public.members m
    where m.phone_e164 = v_phone
    limit 1;
    v_key := 'phone:' || v_phone;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan');
  end if;

  insert into public.member_password_resets(identifier, code_hash, expires_at, attempts)
  values (v_key, crypt(v_code, gen_salt('bf')), now() + interval '15 minutes', 0)
  on conflict (identifier) do update
  set code_hash = excluded.code_hash,
      expires_at = excluded.expires_at,
      attempts = 0,
      created_at = now();

  return jsonb_build_object(
    'ok', true,
    'message', 'Kode reset dibuat. Nanti dikirim WA/email.',
    'debug_code', v_code
  );
end;
$$;

create or replace function public.member_reset_password(
  p_identifier text,
  p_code text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := trim(coalesce(p_identifier, ''));
  v_code text := trim(coalesce(p_code, ''));
  v_pass text := coalesce(p_new_password, '');
  v_phone text;
  v_key text;
  v_row public.member_password_resets%rowtype;
  v_member public.members%rowtype;
begin
  if length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password baru minimal 6 karakter');
  end if;
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi kode reset');
  end if;

  if position('@' in v_id) > 0 then
    v_key := 'email:' || lower(v_id);
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    v_key := 'phone:' || v_phone;
  end if;

  select * into v_row from public.member_password_resets where identifier = v_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Minta kode reset dulu');
  end if;
  if v_row.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'Kode kedaluwarsa. Minta ulang.');
  end if;
  if v_row.attempts >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Terlalu banyak percobaan. Minta kode baru.');
  end if;

  if crypt(v_code, v_row.code_hash) <> v_row.code_hash then
    update public.member_password_resets
    set attempts = attempts + 1
    where identifier = v_key;
    return jsonb_build_object('ok', false, 'error', 'Kode salah');
  end if;

  if position('@' in v_id) > 0 then
    update public.members
    set password_hash = crypt(v_pass, gen_salt('bf')),
        updated_at = now()
    where lower(trim(email)) = lower(v_id)
    returning * into v_member;
  else
    update public.members
    set password_hash = crypt(v_pass, gen_salt('bf')),
        updated_at = now()
    where phone_e164 = public.wa_digits(v_id)
    returning * into v_member;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan');
  end if;

  delete from public.member_password_resets where identifier = v_key;

  return jsonb_build_object(
    'ok', true,
    'member', public.member_public_row(v_member)
  );
end;
$$;

grant execute on function public.member_register(text, text, text, text) to anon, authenticated;
grant execute on function public.member_login(text, text) to anon, authenticated;
grant execute on function public.member_request_password_reset(text) to anon, authenticated;
grant execute on function public.member_reset_password(text, text, text) to anon, authenticated;
