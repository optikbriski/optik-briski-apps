-- Profil Member lengkap: nama, email, WA/telp tampilan, alamat, tanggal lahir, preferensi.

create extension if not exists pgcrypto with schema extensions;

alter table public.members
  add column if not exists password_hash text,
  add column if not exists tanggal_lahir date,
  add column if not exists alamat text;

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

drop function if exists public.member_upsert_profile(text, text, text, text, numeric, text);

create or replace function public.member_upsert_profile(
  p_phone text,
  p_nama text default null,
  p_email text default null,
  p_alamat text default null,
  p_phone_raw text default null,
  p_tanggal_lahir date default null,
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
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
begin
  if v_phone is null then
    raise exception 'Nomor HP / WhatsApp tidak valid';
  end if;

  if v_email is not null and exists (
    select 1 from public.members m
    where lower(trim(m.email)) = v_email
      and m.phone_e164 <> v_phone
  ) then
    raise exception 'Email sudah dipakai akun lain';
  end if;

  insert into public.members (
    phone_e164, phone_raw, nama, email, alamat, tanggal_lahir, font_scale, locale
  ) values (
    v_phone,
    coalesce(nullif(trim(coalesce(p_phone_raw, '')), ''), trim(p_phone)),
    nullif(trim(coalesce(p_nama, '')), ''),
    v_email,
    nullif(trim(coalesce(p_alamat, '')), ''),
    p_tanggal_lahir,
    coalesce(p_font_scale, 1.0),
    coalesce(nullif(trim(coalesce(p_locale, '')), ''), 'id')
  )
  on conflict (phone_e164) do update set
    phone_raw = coalesce(
      nullif(trim(coalesce(p_phone_raw, '')), ''),
      excluded.phone_raw,
      members.phone_raw
    ),
    nama = coalesce(excluded.nama, members.nama),
    email = coalesce(v_email, members.email),
    alamat = coalesce(excluded.alamat, members.alamat),
    tanggal_lahir = coalesce(p_tanggal_lahir, members.tanggal_lahir),
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

grant execute on function public.member_upsert_profile(
  text, text, text, text, text, date, numeric, text
) to anon, authenticated;
