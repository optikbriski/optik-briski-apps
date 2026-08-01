-- =============================================================================
-- CONSOLIDATED (aman di-run sekali): password auth + DOB + OTP WA/email terpisah
-- Ganti paste gabungan 000004+000005+000006 — hindari overload member_register.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- 1) Tabel dasar
-- -----------------------------------------------------------------------------
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
  add column if not exists password_hash text,
  add column if not exists tanggal_lahir date;

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

create table if not exists public.member_password_resets (
  identifier text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.member_register_pending (
  phone_e164 text primary key,
  phone_raw text,
  nama text,
  email text,
  tanggal_lahir date,
  password_hash text, -- boleh null sampai user isi password
  code_hash text not null default 'pending',
  expires_at timestamptz not null default (now() + interval '1 day'),
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.member_register_pending
  add column if not exists wa_code_hash text,
  add column if not exists email_code_hash text,
  add column if not exists wa_expires_at timestamptz,
  add column if not exists email_expires_at timestamptz,
  add column if not exists wa_verified boolean not null default false,
  add column if not exists email_verified boolean not null default false,
  add column if not exists wa_attempts int not null default 0,
  add column if not exists email_attempts int not null default 0;

-- Boleh null saat baru kirim OTP (sebelum password diisi)
alter table public.member_register_pending
  alter column password_hash drop not null;

alter table public.members enable row level security;
alter table public.member_password_resets enable row level security;
alter table public.member_register_pending enable row level security;

-- -----------------------------------------------------------------------------
-- 2) Helpers
-- -----------------------------------------------------------------------------
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
    'tanggal_lahir', v.tanggal_lahir,
    'font_scale', v.font_scale,
    'locale', v.locale
  );
$$;

-- Hapus overload lama supaya PostgREST tidak ambigu
drop function if exists public.member_register(text, text, text, text);
drop function if exists public.member_register(text, text, text, text, date);

-- -----------------------------------------------------------------------------
-- 3) Login / register langsung / reset password
-- -----------------------------------------------------------------------------
create or replace function public.member_register(
  p_phone text,
  p_password text,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
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
    phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
  ) values (
    v_phone, trim(p_phone),
    nullif(trim(coalesce(p_nama, '')), ''),
    v_email, p_tanggal_lahir,
    crypt(v_pass, gen_salt('bf'))
  )
  returning * into v_member;

  return jsonb_build_object('ok', true, 'member', public.member_public_row(v_member));
end;
$$;

create or replace function public.member_login(p_identifier text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
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
    select * into v_member from public.members m
    where lower(trim(m.email)) = lower(v_id) limit 1;
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    select * into v_member from public.members m
    where m.phone_e164 = v_phone limit 1;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan. Daftar dulu.');
  end if;
  if v_member.password_hash is null or trim(v_member.password_hash) = '' then
    return jsonb_build_object('ok', false, 'error',
      'Akun ini belum punya password. Pakai OTP atau Lupa password.');
  end if;
  if crypt(v_pass, v_member.password_hash) <> v_member.password_hash then
    return jsonb_build_object('ok', false, 'error', 'Password salah');
  end if;

  update public.members set updated_at = now() where id = v_member.id;
  return jsonb_build_object('ok', true, 'member', public.member_public_row(v_member));
end;
$$;

create or replace function public.member_request_password_reset(p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
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
    select * into v_member from public.members m
    where lower(trim(m.email)) = lower(v_id) limit 1;
    v_key := 'email:' || lower(v_id);
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    select * into v_member from public.members m
    where m.phone_e164 = v_phone limit 1;
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
    'message', 'Kode reset dibuat.',
    'debug_code', v_code
  );
end;
$$;

create or replace function public.member_reset_password(
  p_identifier text, p_code text, p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
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
    return jsonb_build_object('ok', false, 'error', 'Terlalu banyak percobaan.');
  end if;
  if crypt(v_code, v_row.code_hash) <> v_row.code_hash then
    update public.member_password_resets set attempts = attempts + 1 where identifier = v_key;
    return jsonb_build_object('ok', false, 'error', 'Kode salah');
  end if;

  if position('@' in v_id) > 0 then
    update public.members
    set password_hash = crypt(v_pass, gen_salt('bf')), updated_at = now()
    where lower(trim(email)) = lower(v_id)
    returning * into v_member;
  else
    update public.members
    set password_hash = crypt(v_pass, gen_salt('bf')), updated_at = now()
    where phone_e164 = public.wa_digits(v_id)
    returning * into v_member;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan');
  end if;

  delete from public.member_password_resets where identifier = v_key;
  return jsonb_build_object('ok', true, 'member', public.member_public_row(v_member));
end;
$$;

-- -----------------------------------------------------------------------------
-- 4) Draft daftar + OTP per channel (WA / email)
-- -----------------------------------------------------------------------------
create or replace function public.member_save_register_draft(
  p_phone text,
  p_password text default null,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_pass text := coalesce(p_password, '');
  v_existing public.member_register_pending%rowtype;
begin
  -- Draft partial: OTP boleh dikirim dulu; profil lengkap dicek di finalize.
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP / WhatsApp tidak valid');
  end if;
  if exists (select 1 from public.members m where m.phone_e164 = v_phone) then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP sudah terdaftar');
  end if;
  if v_email is not null
     and exists (select 1 from public.members m where lower(trim(m.email)) = v_email) then
    return jsonb_build_object('ok', false, 'error', 'Email sudah terdaftar');
  end if;
  if p_tanggal_lahir is not null
     and p_tanggal_lahir > (current_date - interval '10 years') then
    return jsonb_build_object('ok', false, 'error', 'Usia minimal 10 tahun');
  end if;
  if length(v_pass) > 0 and length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password minimal 6 karakter');
  end if;

  select * into v_existing from public.member_register_pending where phone_e164 = v_phone;

  if found then
    update public.member_register_pending set
      phone_raw = trim(p_phone),
      nama = coalesce(nullif(trim(coalesce(p_nama, '')), ''), nama),
      tanggal_lahir = coalesce(p_tanggal_lahir, tanggal_lahir),
      password_hash = case
        when length(v_pass) >= 6 then crypt(v_pass, gen_salt('bf'))
        else password_hash
      end,
      email = coalesce(v_email, email),
      code_hash = coalesce(code_hash, 'pending'),
      expires_at = coalesce(expires_at, now() + interval '1 day'),
      wa_verified = case when phone_raw is not distinct from trim(p_phone) then wa_verified else false end,
      email_verified = case
        when v_email is null or email is not distinct from v_email then email_verified
        else false
      end,
      created_at = now()
    where phone_e164 = v_phone;
  else
    insert into public.member_register_pending (
      phone_e164, phone_raw, nama, email, tanggal_lahir,
      password_hash, code_hash, expires_at
    ) values (
      v_phone, trim(p_phone),
      nullif(trim(coalesce(p_nama, '')), ''),
      v_email, p_tanggal_lahir,
      case when length(v_pass) >= 6 then crypt(v_pass, gen_salt('bf')) else null end,
      'pending',
      now() + interval '1 day'
    );
  end if;

  select * into v_existing from public.member_register_pending where phone_e164 = v_phone;

  return jsonb_build_object(
    'ok', true,
    'phone_e164', v_phone,
    'email', v_existing.email,
    'wa_verified', coalesce(v_existing.wa_verified, false),
    'email_verified', coalesce(v_existing.email_verified, false)
  );
end;
$$;

create or replace function public.member_issue_register_otp(p_phone text, p_channel text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_ch text := lower(trim(coalesce(p_channel, '')));
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_email text;
begin
  if v_phone is null then
    return jsonb_build_object('ok', false, 'error', 'Nomor tidak valid');
  end if;
  if v_ch not in ('wa', 'email') then
    return jsonb_build_object('ok', false, 'error', 'Channel harus wa atau email');
  end if;
  if not exists (select 1 from public.member_register_pending where phone_e164 = v_phone) then
    return jsonb_build_object('ok', false, 'error', 'Isi nomor WhatsApp dulu');
  end if;

  select email into v_email from public.member_register_pending where phone_e164 = v_phone;

  if v_ch = 'email' and v_email is null then
    return jsonb_build_object('ok', false, 'error', 'Isi email dulu');
  end if;

  if v_ch = 'wa' then
    update public.member_register_pending set
      wa_code_hash = crypt(v_code, gen_salt('bf')),
      wa_expires_at = now() + interval '15 minutes',
      wa_attempts = 0,
      wa_verified = false
    where phone_e164 = v_phone;
  else
    update public.member_register_pending set
      email_code_hash = crypt(v_code, gen_salt('bf')),
      email_expires_at = now() + interval '15 minutes',
      email_attempts = 0,
      email_verified = false
    where phone_e164 = v_phone;
  end if;

  return jsonb_build_object(
    'ok', true,
    'channel', v_ch,
    'phone_e164', v_phone,
    'email', v_email,
    'otp', v_code,
    'ttl_seconds', 900
  );
end;
$$;

create or replace function public.member_check_register_otp(
  p_phone text, p_channel text, p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_ch text := lower(trim(coalesce(p_channel, '')));
  v_code text := trim(coalesce(p_code, ''));
  v_row public.member_register_pending%rowtype;
  v_hash text;
  v_exp timestamptz;
  v_att int;
begin
  if v_phone is null or v_code = '' then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Data kurang');
  end if;

  select * into v_row from public.member_register_pending where phone_e164 = v_phone;
  if not found then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Draft tidak ada');
  end if;

  if v_ch = 'wa' then
    v_hash := v_row.wa_code_hash; v_exp := v_row.wa_expires_at; v_att := v_row.wa_attempts;
  elsif v_ch = 'email' then
    v_hash := v_row.email_code_hash; v_exp := v_row.email_expires_at; v_att := v_row.email_attempts;
  else
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Channel invalid');
  end if;

  if v_hash is null then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Belum kirim OTP');
  end if;
  if v_exp is null or v_exp < now() then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'OTP kedaluwarsa');
  end if;
  if v_att >= 8 then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Terlalu banyak percobaan');
  end if;

  if crypt(v_code, v_hash) <> v_hash then
    if v_ch = 'wa' then
      update public.member_register_pending set wa_attempts = wa_attempts + 1 where phone_e164 = v_phone;
    else
      update public.member_register_pending set email_attempts = email_attempts + 1 where phone_e164 = v_phone;
    end if;
    return jsonb_build_object('ok', true, 'verified', false, 'error', 'Kode salah');
  end if;

  if v_ch = 'wa' then
    update public.member_register_pending set wa_verified = true where phone_e164 = v_phone;
  else
    update public.member_register_pending set email_verified = true where phone_e164 = v_phone;
  end if;

  return jsonb_build_object('ok', true, 'verified', true, 'channel', v_ch);
end;
$$;

create or replace function public.member_finalize_register(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_pend public.member_register_pending%rowtype;
  v_member public.members%rowtype;
begin
  if v_phone is null then
    return jsonb_build_object('ok', false, 'error', 'Nomor tidak valid');
  end if;

  select * into v_pend from public.member_register_pending where phone_e164 = v_phone;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Data daftar tidak ditemukan');
  end if;
  if not coalesce(v_pend.wa_verified, false) then
    return jsonb_build_object('ok', false, 'error', 'Verifikasi WhatsApp dulu');
  end if;
  if not coalesce(v_pend.email_verified, false) then
    return jsonb_build_object('ok', false, 'error', 'Verifikasi email dulu');
  end if;
  if nullif(trim(coalesce(v_pend.nama, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Isi nama lengkap dulu');
  end if;
  if v_pend.email is null then
    return jsonb_build_object('ok', false, 'error', 'Isi email dulu');
  end if;
  if v_pend.tanggal_lahir is null then
    return jsonb_build_object('ok', false, 'error', 'Pilih tanggal lahir dulu');
  end if;
  if v_pend.password_hash is null then
    return jsonb_build_object('ok', false, 'error', 'Isi password dulu');
  end if;
  if exists (select 1 from public.members m where m.phone_e164 = v_phone) then
    delete from public.member_register_pending where phone_e164 = v_phone;
    return jsonb_build_object('ok', false, 'error', 'Nomor sudah terdaftar. Silakan masuk.');
  end if;

  insert into public.members (
    phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
  ) values (
    v_pend.phone_e164, v_pend.phone_raw, v_pend.nama, v_pend.email,
    v_pend.tanggal_lahir, v_pend.password_hash
  )
  returning * into v_member;

  delete from public.member_register_pending where phone_e164 = v_phone;

  return jsonb_build_object(
    'ok', true,
    'member', public.member_public_row(v_member),
    'message', 'Akun siap. Silakan masuk.'
  );
end;
$$;

create or replace function public.member_finalize_register_with_profile(
  p_phone text,
  p_password text default null,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_draft jsonb;
begin
  v_draft := public.member_save_register_draft(
    p_phone, p_password, p_nama, p_email, p_tanggal_lahir
  );
  if coalesce((v_draft->>'ok')::boolean, false) is not true then
    return v_draft;
  end if;
  return public.member_finalize_register(p_phone);
end;
$$;

-- -----------------------------------------------------------------------------
-- 5) Grants
-- -----------------------------------------------------------------------------
grant execute on function public.member_register(text, text, text, text, date) to anon, authenticated;
grant execute on function public.member_login(text, text) to anon, authenticated;
grant execute on function public.member_request_password_reset(text) to anon, authenticated;
grant execute on function public.member_reset_password(text, text, text) to anon, authenticated;
grant execute on function public.member_save_register_draft(text, text, text, text, date)
  to anon, authenticated, service_role;
grant execute on function public.member_issue_register_otp(text, text)
  to anon, authenticated, service_role;
grant execute on function public.member_check_register_otp(text, text, text)
  to anon, authenticated;
grant execute on function public.member_finalize_register(text)
  to anon, authenticated;
grant execute on function public.member_finalize_register_with_profile(text, text, text, text, date)
  to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 6) Patch tabel lama (CREATE IF NOT EXISTS tidak mengubah kolom existing)
-- -----------------------------------------------------------------------------
alter table public.member_register_pending
  alter column password_hash drop not null;

alter table public.member_register_pending
  alter column code_hash set default 'pending';

alter table public.member_register_pending
  alter column expires_at set default (now() + interval '1 day');

update public.member_register_pending
set code_hash = 'pending'
where code_hash is null;

update public.member_register_pending
set expires_at = now() + interval '1 day'
where expires_at is null;

alter table public.member_register_pending
  alter column code_hash set not null;

alter table public.member_register_pending
  alter column expires_at set not null;
