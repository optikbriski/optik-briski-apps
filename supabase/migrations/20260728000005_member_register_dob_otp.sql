-- =============================================================================
-- Member daftar: tanggal lahir + OTP verifikasi (WA + email via Edge)
-- =============================================================================

create extension if not exists pgcrypto;

alter table public.members
  add column if not exists tanggal_lahir date;

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

-- Pending registrasi menunggu OTP
create table if not exists public.member_register_pending (
  phone_e164 text primary key,
  phone_raw text,
  nama text,
  email text,
  tanggal_lahir date,
  password_hash text not null,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.member_register_pending enable row level security;

-- Mulai daftar: simpan pending + generate OTP (kode dikembalikan untuk Edge kirim)
create or replace function public.member_begin_register(
  p_phone text,
  p_password text,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null
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
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
begin
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP / WhatsApp tidak valid');
  end if;
  if v_email is null then
    return jsonb_build_object('ok', false, 'error', 'Email wajib agar OTP bisa dikirim');
  end if;
  if p_tanggal_lahir is null then
    return jsonb_build_object('ok', false, 'error', 'Tanggal lahir wajib diisi');
  end if;
  if p_tanggal_lahir > current_date then
    return jsonb_build_object('ok', false, 'error', 'Tanggal lahir tidak valid');
  end if;
  if p_tanggal_lahir > (current_date - interval '10 years') then
    return jsonb_build_object('ok', false, 'error', 'Usia minimal 10 tahun');
  end if;
  if length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password minimal 6 karakter');
  end if;
  if exists (select 1 from public.members m where m.phone_e164 = v_phone) then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP sudah terdaftar. Silakan masuk.');
  end if;
  if exists (
    select 1 from public.members m where lower(trim(m.email)) = v_email
  ) then
    return jsonb_build_object('ok', false, 'error', 'Email sudah terdaftar. Silakan masuk.');
  end if;

  insert into public.member_register_pending (
    phone_e164, phone_raw, nama, email, tanggal_lahir,
    password_hash, code_hash, expires_at, attempts
  ) values (
    v_phone,
    trim(p_phone),
    nullif(trim(coalesce(p_nama, '')), ''),
    v_email,
    p_tanggal_lahir,
    crypt(v_pass, gen_salt('bf')),
    crypt(v_code, gen_salt('bf')),
    now() + interval '15 minutes',
    0
  )
  on conflict (phone_e164) do update set
    phone_raw = excluded.phone_raw,
    nama = excluded.nama,
    email = excluded.email,
    tanggal_lahir = excluded.tanggal_lahir,
    password_hash = excluded.password_hash,
    code_hash = excluded.code_hash,
    expires_at = excluded.expires_at,
    attempts = 0,
    created_at = now();

  return jsonb_build_object(
    'ok', true,
    'phone_e164', v_phone,
    'email', v_email,
    'otp', v_code,
    'ttl_seconds', 900,
    'message', 'OTP dibuat. Akan dikirim ke WhatsApp & email.'
  );
end;
$$;

-- Selesai daftar setelah OTP benar
create or replace function public.member_complete_register(
  p_phone text,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_code text := trim(coalesce(p_code, ''));
  v_pend public.member_register_pending%rowtype;
  v_member public.members%rowtype;
begin
  if v_phone is null then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
  end if;
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi kode OTP');
  end if;

  select * into v_pend
  from public.member_register_pending
  where phone_e164 = v_phone;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Belum minta OTP daftar. Isi form lagi.');
  end if;
  if v_pend.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'OTP kedaluwarsa. Kirim ulang.');
  end if;
  if v_pend.attempts >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Terlalu banyak percobaan. Kirim OTP baru.');
  end if;
  if crypt(v_code, v_pend.code_hash) <> v_pend.code_hash then
    update public.member_register_pending
    set attempts = attempts + 1
    where phone_e164 = v_phone;
    return jsonb_build_object('ok', false, 'error', 'OTP salah');
  end if;

  if exists (select 1 from public.members m where m.phone_e164 = v_phone) then
    delete from public.member_register_pending where phone_e164 = v_phone;
    return jsonb_build_object('ok', false, 'error', 'Nomor sudah terdaftar. Silakan masuk.');
  end if;

  insert into public.members (
    phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
  ) values (
    v_pend.phone_e164,
    v_pend.phone_raw,
    v_pend.nama,
    v_pend.email,
    v_pend.tanggal_lahir,
    v_pend.password_hash
  )
  returning * into v_member;

  delete from public.member_register_pending where phone_e164 = v_phone;

  return jsonb_build_object(
    'ok', true,
    'member', public.member_public_row(v_member)
  );
end;
$$;

-- Update member_register lama agar juga bisa simpan DOB (tanpa OTP, fallback)
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
    phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
  ) values (
    v_phone,
    trim(p_phone),
    nullif(trim(coalesce(p_nama, '')), ''),
    v_email,
    p_tanggal_lahir,
    crypt(v_pass, gen_salt('bf'))
  )
  returning * into v_member;

  return jsonb_build_object(
    'ok', true,
    'member', public.member_public_row(v_member)
  );
end;
$$;

grant execute on function public.member_begin_register(text, text, text, text, date)
  to anon, authenticated, service_role;
grant execute on function public.member_complete_register(text, text)
  to anon, authenticated;
grant execute on function public.member_register(text, text, text, text, date)
  to anon, authenticated;
