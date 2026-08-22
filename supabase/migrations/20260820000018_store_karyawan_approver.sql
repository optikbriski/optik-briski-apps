-- =============================================================================
-- 000018 — Admin toko boleh setujui/tolak karyawan toko sendiri.
-- Pusat / owner / super_admin tetap semua cabang di tenant yang sama.
-- Bukan merek lain. Bukan cabang lain. Bukan self-Aktif saat daftar.
-- Apply di SQL Editor live SETELAH 000017.
-- =============================================================================

create or replace function public.current_profile_toko_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(coalesce(toko_id, '')), '')
  from public.profiles
  where id = auth.uid();
$$;

comment on function public.current_profile_toko_id() is
  'toko_id profil auth.uid(). Kosong = belum assigned. Jangan grant ke anon.';

create or replace function public.same_store_toko(a text, b text)
returns boolean
language sql
immutable
as $$
  select
    nullif(trim(coalesce(a, '')), '') is not null
    and nullif(trim(coalesce(b, '')), '') is not null
    and (
      lower(trim(a)) = lower(trim(b))
      or (
        upper(trim(a)) in ('PUSAT', 'CABANG-PUSAT')
        and upper(trim(b)) in ('PUSAT', 'CABANG-PUSAT')
      )
    );
$$;

comment on function public.same_store_toko(text, text) is
  'Toko yang sama. PUSAT = CABANG-PUSAT. Bukan semua *-PUSAT.';

create or replace function public.can_approve_karyawan_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin_pusat_approver()
    or (
      public.current_profile_role() = 'admin_toko'
      and public.current_tenant_id() is not null
      and public.same_store_toko(public.current_profile_toko_id(), p_toko)
    );
$$;

comment on function public.can_approve_karyawan_for_toko(text) is
  'Pusat/owner: semua toko tenant. admin_toko: hanya toko sendiri. Suspend = tolak.';

create or replace function public.karyawan_guard_status_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new text := trim(coalesce(new.status_approval, ''));
  v_old text := trim(coalesce(old.status_approval, ''));
  v_pending constant text[] := array[
    'pending',
    'menunggu otp',
    'menunggu persetujuan'
  ];
begin
  -- INSERT (register): hanya pusat yang boleh langsung Aktif.
  -- admin_toko tetap dipaksa antrean — tidak bisa self-Aktif / titip Aktif.
  if tg_op = 'INSERT' then
    if not public.is_admin_pusat_approver() then
      if lower(v_new) = 'aktif'
         or lower(v_new) like 'ditolak%'
         or v_new = '' then
        new.status_approval := 'Menunggu Persetujuan';
      elsif lower(v_new) = any (v_pending) then
        null;
      else
        new.status_approval := 'Menunggu Persetujuan';
      end if;
    end if;
    return new;
  end if;

  if v_new is not distinct from v_old then
    return new;
  end if;

  -- UPDATE status: pusat semua toko; admin_toko hanya baris toko sendiri
  -- (lama dan baru — tidak bisa pindah cabang sambil mengaktifkan).
  if public.can_approve_karyawan_for_toko(new.toko_id)
     and public.can_approve_karyawan_for_toko(old.toko_id) then
    return new;
  end if;

  if lower(v_old) = any (v_pending)
     and lower(v_new) = any (v_pending) then
    return new;
  end if;

  raise exception
    'status_approval hanya diubah Admin Pusat atau admin toko cabang yang sama'
    using errcode = '42501';
end;
$$;

comment on function public.karyawan_guard_status_approval is
  'Blok self-approve. Aktif/Ditolak: pusat, atau admin_toko untuk toko sendiri.';

drop trigger if exists trg_karyawan_guard_status_approval on public.karyawan;
create trigger trg_karyawan_guard_status_approval
  before insert or update on public.karyawan
  for each row
  execute function public.karyawan_guard_status_approval();

create or replace function public.karyawan_guard_store_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() is distinct from 'admin_toko' then
    return new;
  end if;

  if not public.same_store_toko(public.current_profile_toko_id(), new.toko_id) then
    raise exception 'admin_toko hanya boleh kelola karyawan toko sendiri'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE'
     and not public.same_store_toko(old.toko_id, new.toko_id) then
    raise exception 'admin_toko tidak boleh pindahkan karyawan ke toko lain'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function public.karyawan_guard_store_scope is
  'admin_toko tidak boleh baca-tulis karyawan cabang/merek lain lewat REST.';

drop trigger if exists trg_karyawan_guard_store_scope on public.karyawan;
create trigger trg_karyawan_guard_store_scope
  before insert or update on public.karyawan
  for each row
  execute function public.karyawan_guard_store_scope();

revoke all on function public.current_profile_toko_id() from public;
revoke all on function public.current_profile_toko_id() from anon;
grant execute on function public.current_profile_toko_id() to authenticated, service_role;

revoke all on function public.same_store_toko(text, text) from public;
revoke all on function public.same_store_toko(text, text) from anon;
grant execute on function public.same_store_toko(text, text) to authenticated, service_role;

revoke all on function public.can_approve_karyawan_for_toko(text) from public;
revoke all on function public.can_approve_karyawan_for_toko(text) from anon;
grant execute on function public.can_approve_karyawan_for_toko(text) to authenticated, service_role;
