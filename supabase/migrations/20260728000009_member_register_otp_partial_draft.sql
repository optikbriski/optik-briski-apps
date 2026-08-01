-- OTP WA: cukup nomor WA. OTP email: cukup nomor WA + email.
-- Nama / password / tanggal lahir boleh diisi belakangan (sebelum bikin akun).

create extension if not exists pgcrypto with schema extensions;

-- password_hash boleh kosong dulu saat baru kirim OTP
alter table public.member_register_pending
  alter column password_hash drop not null;

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
  v_hash text;
begin
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP / WhatsApp tidak valid');
  end if;

  if exists (select 1 from public.members m where m.phone_e164 = v_phone) then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP sudah terdaftar');
  end if;

  if v_email is not null
     and exists (
       select 1 from public.members m where lower(trim(m.email)) = v_email
     ) then
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

  v_hash := case
    when length(v_pass) >= 6 then crypt(v_pass, gen_salt('bf'))
    else coalesce(v_existing.password_hash, null)
  end;

  if found then
    update public.member_register_pending set
      phone_raw = trim(p_phone),
      nama = coalesce(nullif(trim(coalesce(p_nama, '')), ''), nama),
      tanggal_lahir = coalesce(p_tanggal_lahir, tanggal_lahir),
      password_hash = coalesce(v_hash, password_hash),
      email = coalesce(v_email, email),
      wa_verified = case
        when phone_raw is not distinct from trim(p_phone) then wa_verified
        else false
      end,
      email_verified = case
        when v_email is null or email is not distinct from v_email then email_verified
        else false
      end,
      created_at = now()
    where phone_e164 = v_phone;
  else
    insert into public.member_register_pending (
      phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
    ) values (
      v_phone,
      trim(p_phone),
      nullif(trim(coalesce(p_nama, '')), ''),
      v_email,
      p_tanggal_lahir,
      v_hash
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

-- Sinkron draft terakhir sebelum finalize (nama/password/DOB yang baru diisi)
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

grant execute on function public.member_save_register_draft(text, text, text, text, date)
  to anon, authenticated, service_role;
grant execute on function public.member_issue_register_otp(text, text)
  to anon, authenticated, service_role;
grant execute on function public.member_finalize_register(text)
  to anon, authenticated;
grant execute on function public.member_finalize_register_with_profile(text, text, text, text, date)
  to anon, authenticated;
