-- =============================================================================
-- 000017 — Email / HP login unik di seluruh project. Bukan per merek.
-- Dua brand tidak boleh pakai identitas masuk yang sama (ketuker akun).
-- Apply setelah 000016.
-- =============================================================================

create or replace function public.assert_login_email_free(
  p_email text,
  p_tenant uuid,
  p_except_karyawan uuid default null,
  p_except_member uuid default null,
  p_except_profile uuid default null
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v text := nullif(lower(trim(coalesce(p_email, ''))), '');
begin
  if v is null then
    return;
  end if;
  if exists (
    select 1 from public.karyawan k
    where lower(trim(k.email)) = v
      and (p_except_karyawan is null or k.id is distinct from p_except_karyawan)
      and k.tenant_id is not null
      and p_tenant is not null
      and k.tenant_id <> p_tenant
  ) then
    raise exception 'Email sudah dipakai akun merek lain'
      using errcode = '23505';
  end if;
  if exists (
    select 1 from public.members m
    where lower(trim(m.email)) = v
      and (p_except_member is null or m.id is distinct from p_except_member)
      and m.tenant_id is not null
      and p_tenant is not null
      and m.tenant_id <> p_tenant
  ) then
    raise exception 'Email sudah dipakai akun merek lain'
      using errcode = '23505';
  end if;
  if exists (
    select 1 from public.profiles p
    where lower(trim(p.email)) = v
      and (p_except_profile is null or p.id is distinct from p_except_profile)
      and p.tenant_id is not null
      and p_tenant is not null
      and p.tenant_id <> p_tenant
  ) then
    raise exception 'Email sudah dipakai akun merek lain'
      using errcode = '23505';
  end if;
end;
$$;

create or replace function public.assert_login_phone_free(
  p_phone text,
  p_tenant uuid,
  p_except_member uuid default null
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v text := public.wa_digits(p_phone);
begin
  if v is null or length(v) < 8 then
    return;
  end if;
  if exists (
    select 1 from public.members m
    where m.phone_e164 = v
      and (p_except_member is null or m.id is distinct from p_except_member)
      and m.tenant_id is not null
      and p_tenant is not null
      and m.tenant_id <> p_tenant
  ) then
    raise exception 'Nomor HP sudah dipakai akun merek lain'
      using errcode = '23505';
  end if;
end;
$$;

create or replace function public.trg_login_identity_karyawan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_login_email_free(
    new.email, new.tenant_id, new.id, null, new.id
  );
  return new;
end;
$$;

create or replace function public.trg_login_identity_members()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_login_email_free(
    new.email, new.tenant_id, null, new.id, null
  );
  perform public.assert_login_phone_free(
    new.phone_e164, new.tenant_id, new.id
  );
  return new;
end;
$$;

create or replace function public.trg_login_identity_profiles()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_login_email_free(
    new.email, new.tenant_id, new.id, null, new.id
  );
  return new;
end;
$$;

drop trigger if exists trg_login_identity_karyawan on public.karyawan;
create trigger trg_login_identity_karyawan
  before insert or update of email, tenant_id
  on public.karyawan
  for each row
  execute function public.trg_login_identity_karyawan();

drop trigger if exists trg_login_identity_members on public.members;
create trigger trg_login_identity_members
  before insert or update of email, phone_e164, tenant_id
  on public.members
  for each row
  execute function public.trg_login_identity_members();

drop trigger if exists trg_login_identity_profiles on public.profiles;
create trigger trg_login_identity_profiles
  before insert or update of email, tenant_id
  on public.profiles
  for each row
  execute function public.trg_login_identity_profiles();

drop index if exists public.karyawan_email_tenant_uidx;
create unique index if not exists karyawan_email_global_uidx
  on public.karyawan (lower(trim(email)))
  where nullif(trim(email), '') is not null;

drop index if exists public.members_email_tenant_uidx;
create unique index if not exists members_email_global_uidx
  on public.members (lower(trim(email)))
  where nullif(trim(email), '') is not null;

create unique index if not exists profiles_email_global_uidx
  on public.profiles (lower(trim(email)))
  where nullif(trim(email), '') is not null;

drop index if exists public.members_phone_global_uidx;
create unique index if not exists members_phone_global_uidx
  on public.members (phone_e164)
  where nullif(trim(phone_e164), '') is not null;

comment on function public.assert_login_email_free(text, uuid, uuid, uuid, uuid) is
  'Email login unik antar merek. Satu email tidak boleh jadi akun dua brand.';

comment on function public.assert_login_phone_free(text, uuid, uuid) is
  'HP login member unik antar merek.';

create or replace function public.member_register(
  p_phone text,
  p_password text,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null,
  p_tenant_id uuid default null
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
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
  end if;
  if length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password minimal 6 karakter');
  end if;
  if exists (
    select 1 from public.members m
    where m.phone_e164 = v_phone
  ) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Nomor HP sudah dipakai akun lain. Tidak boleh sama antar merek.'
    );
  end if;
  if v_email is not null and exists (
    select 1 from public.members m
    where lower(trim(m.email)) = v_email
  ) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Email sudah dipakai akun lain. Tidak boleh sama antar merek.'
    );
  end if;
  if v_email is not null and (
    exists (select 1 from public.karyawan k where lower(trim(k.email)) = v_email)
    or exists (select 1 from public.profiles p where lower(trim(p.email)) = v_email)
  ) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Email sudah dipakai akun lain. Tidak boleh sama antar merek.'
    );
  end if;

  insert into public.members (
    tenant_id, phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
  ) values (
    v_tenant, v_phone, trim(p_phone),
    nullif(trim(coalesce(p_nama, '')), ''),
    v_email, p_tanggal_lahir,
    crypt(v_pass, gen_salt('bf'))
  )
  returning * into v_member;

  return jsonb_build_object('ok', true, 'member', public.member_public_row(v_member));
end;
$$;

grant execute on function public.member_register(text, text, text, text, date, uuid)
  to anon, authenticated;
