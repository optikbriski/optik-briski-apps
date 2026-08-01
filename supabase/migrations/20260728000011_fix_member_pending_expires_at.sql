-- Fix: null value in column "expires_at" of relation "member_register_pending"
-- BUKAN masalah Resend — gagal saat simpan draft, sebelum kirim email.

create extension if not exists pgcrypto with schema extensions;

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
      phone_e164, phone_raw, nama, email, tanggal_lahir,
      password_hash, code_hash, expires_at
    ) values (
      v_phone,
      trim(p_phone),
      nullif(trim(coalesce(p_nama, '')), ''),
      v_email,
      p_tanggal_lahir,
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

grant execute on function public.member_save_register_draft(text, text, text, text, date)
  to anon, authenticated, service_role;
