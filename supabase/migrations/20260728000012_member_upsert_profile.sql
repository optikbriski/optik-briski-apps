-- Fix: Could not find function public.member_upsert_profile (...) (PGRST202)
-- Dipakai tombol "Simpan profil" di tab Akun Member.

create extension if not exists pgcrypto with schema extensions;

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

create table if not exists public.member_family (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  nama text not null,
  hubungan text,
  phone_e164 text,
  created_at timestamptz not null default now()
);

alter table public.members enable row level security;
alter table public.member_family enable row level security;

drop policy if exists members_anon_all on public.members;
create policy members_anon_all on public.members
  for all to anon, authenticated using (true) with check (true);

drop policy if exists member_family_anon_all on public.member_family;
create policy member_family_anon_all on public.member_family
  for all to anon, authenticated using (true) with check (true);

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

create or replace function public.member_upsert_profile(
  p_phone text,
  p_nama text default null,
  p_email text default null,
  p_alamat text default null,
  p_font_scale numeric default null,
  p_locale text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_member public.members%rowtype;
begin
  if v_phone is null then
    raise exception 'Nomor HP tidak valid';
  end if;

  insert into public.members (
    phone_e164, phone_raw, nama, email, alamat, font_scale, locale
  ) values (
    v_phone,
    trim(p_phone),
    nullif(trim(coalesce(p_nama, '')), ''),
    nullif(lower(trim(coalesce(p_email, ''))), ''),
    nullif(trim(coalesce(p_alamat, '')), ''),
    coalesce(p_font_scale, 1.0),
    coalesce(nullif(trim(coalesce(p_locale, '')), ''), 'id')
  )
  on conflict (phone_e164) do update set
    phone_raw = coalesce(nullif(trim(excluded.phone_raw), ''), members.phone_raw),
    nama = coalesce(excluded.nama, members.nama),
    email = coalesce(excluded.email, members.email),
    alamat = coalesce(excluded.alamat, members.alamat),
    font_scale = coalesce(p_font_scale, members.font_scale),
    locale = coalesce(nullif(trim(coalesce(p_locale, '')), ''), members.locale),
    updated_at = now();

  select * into v_member from public.members where phone_e164 = v_phone;

  return jsonb_build_object(
    'id', v_member.id,
    'phone_e164', v_member.phone_e164,
    'phone_raw', v_member.phone_raw,
    'nama', v_member.nama,
    'email', v_member.email,
    'alamat', v_member.alamat,
    'tanggal_lahir', v_member.tanggal_lahir,
    'font_scale', v_member.font_scale,
    'locale', v_member.locale
  );
end;
$$;

grant execute on function public.member_upsert_profile(text, text, text, text, numeric, text)
  to anon, authenticated;
