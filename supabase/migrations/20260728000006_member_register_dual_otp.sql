-- =============================================================================
-- Daftar Member: OTP terpisah WhatsApp & email + verifikasi per channel
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

alter table public.member_register_pending
  add column if not exists wa_code_hash text,
  add column if not exists email_code_hash text,
  add column if not exists wa_expires_at timestamptz,
  add column if not exists email_expires_at timestamptz,
  add column if not exists wa_verified boolean not null default false,
  add column if not exists email_verified boolean not null default false,
  add column if not exists wa_attempts int not null default 0,
  add column if not exists email_attempts int not null default 0;

-- Migrasi data lama: code_hash → kedua channel
update public.member_register_pending
set
  wa_code_hash = coalesce(wa_code_hash, code_hash),
  email_code_hash = coalesce(email_code_hash, code_hash),
  wa_expires_at = coalesce(wa_expires_at, expires_at),
  email_expires_at = coalesce(email_expires_at, expires_at)
where code_hash is not null;

-- Simpan / update draft pendaftaran (belum buat akun)
create or replace function public.member_save_register_draft(
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
  v_existing public.member_register_pending%rowtype;
begin
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP / WhatsApp tidak valid');
  end if;
  if v_email is null then
    return jsonb_build_object('ok', false, 'error', 'Email wajib');
  end if;
  if p_tanggal_lahir is null then
    return jsonb_build_object('ok', false, 'error', 'Tanggal lahir wajib');
  end if;
  if p_tanggal_lahir > (current_date - interval '10 years') then
    return jsonb_build_object('ok', false, 'error', 'Usia minimal 10 tahun');
  end if;
  if length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password minimal 6 karakter');
  end if;
  if exists (select 1 from public.members m where m.phone_e164 = v_phone) then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP sudah terdaftar');
  end if;
  if exists (select 1 from public.members m where lower(trim(m.email)) = v_email) then
    return jsonb_build_object('ok', false, 'error', 'Email sudah terdaftar');
  end if;

  select * into v_existing from public.member_register_pending where phone_e164 = v_phone;

  if found then
    update public.member_register_pending set
      phone_raw = trim(p_phone),
      nama = nullif(trim(coalesce(p_nama, '')), ''),
      tanggal_lahir = p_tanggal_lahir,
      password_hash = crypt(v_pass, gen_salt('bf')),
      wa_verified = case when phone_raw is not distinct from trim(p_phone) then wa_verified else false end,
      email_verified = case when email is not distinct from v_email then email_verified else false end,
      email = v_email,
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
      crypt(v_pass, gen_salt('bf')),
      crypt('000000', gen_salt('bf')),
      now() + interval '1 day'
    );
  end if;

  select * into v_existing from public.member_register_pending where phone_e164 = v_phone;

  return jsonb_build_object(
    'ok', true,
    'phone_e164', v_phone,
    'email', v_email,
    'wa_verified', coalesce(v_existing.wa_verified, false),
    'email_verified', coalesce(v_existing.email_verified, false)
  );
end;
$$;

-- Generate OTP per channel (wa | email)
create or replace function public.member_issue_register_otp(
  p_phone text,
  p_channel text
)
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
    return jsonb_build_object('ok', false, 'error', 'Isi & simpan data daftar dulu');
  end if;

  select email into v_email from public.member_register_pending where phone_e164 = v_phone;

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

-- Cek OTP channel (auto-confirm di UI)
create or replace function public.member_check_register_otp(
  p_phone text,
  p_channel text,
  p_code text
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
    v_hash := v_row.wa_code_hash;
    v_exp := v_row.wa_expires_at;
    v_att := v_row.wa_attempts;
  elsif v_ch = 'email' then
    v_hash := v_row.email_code_hash;
    v_exp := v_row.email_expires_at;
    v_att := v_row.email_attempts;
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

-- Buat akun hanya jika WA + email sudah verified
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

grant execute on function public.member_save_register_draft(text, text, text, text, date)
  to anon, authenticated, service_role;
grant execute on function public.member_issue_register_otp(text, text)
  to anon, authenticated, service_role;
grant execute on function public.member_check_register_otp(text, text, text)
  to anon, authenticated;
grant execute on function public.member_finalize_register(text)
  to anon, authenticated;
