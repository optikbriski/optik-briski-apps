-- =============================================================================
-- Owner cross-app isolation guards
-- 1) Owner Toko cannot mutate karyawan.jabatan (escalate to Admin/Owner, etc.)
-- 2) jabatan Admin/Owner only settable by admin_pusat / super_admin
-- 3) profiles SELECT: Owner Toko = self only; provisioner/admin keep broad read
-- =============================================================================

create or replace function public.current_profile_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(trim(coalesce(role, '')))
  from public.profiles
  where id = auth.uid();
$$;

comment on function public.current_profile_role is
  'Role profil auth.uid() (security definer) — aman dipakai di RLS tanpa rekursi.';

create or replace function public.karyawan_guard_jabatan_mutate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new text := lower(trim(coalesce(new.jabatan, '')));
  v_old text := lower(trim(coalesce(old.jabatan, '')));
  v_role text := public.current_profile_role();
begin
  -- No jabatan change → skip
  if tg_op = 'UPDATE' and v_new is not distinct from v_old then
    return new;
  end if;

  -- Owner Toko (franchise): never mutate jabatan via REST/client.
  -- Approvals go through owner_decide_* (status only).
  if public.is_owner_role() and not public.is_owner_provisioner() then
    if tg_op = 'INSERT' and v_new in ('admin', 'owner') then
      raise exception 'Owner Toko tidak boleh set jabatan Admin/Owner'
        using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and v_new is distinct from v_old then
      raise exception 'Owner Toko tidak boleh mengubah jabatan karyawan'
        using errcode = '42501';
    end if;
  end if;

  -- Escalate to Admin/Owner: Admin Pusat / super_admin only
  if v_new in ('admin', 'owner') then
    if coalesce(v_role, '') not in ('admin_pusat', 'super_admin') then
      raise exception 'jabatan Admin/Owner hanya bisa di-set Admin Pusat'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_karyawan_guard_jabatan_mutate on public.karyawan;
create trigger trg_karyawan_guard_jabatan_mutate
  before insert or update on public.karyawan
  for each row
  execute function public.karyawan_guard_jabatan_mutate();

comment on function public.karyawan_guard_jabatan_mutate is
  'Blok Owner Toko ubah jabatan; kunci escalate Admin/Owner ke Admin Pusat.';

-- profiles SELECT: stop Owner Toko / staff from listing all admin profiles
drop policy if exists profiles_auth_select on public.profiles;
create policy profiles_auth_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.current_profile_role() in ('admin_pusat', 'super_admin', 'admin_toko')
    or public.is_owner_provisioner()
  );

-- profiles UPDATE: self or provisioner/admin only (prevent Owner Toko rewriting roles)
drop policy if exists profiles_auth_update on public.profiles;
create policy profiles_auth_update on public.profiles
  for update to authenticated
  using (
    id = auth.uid()
    or public.current_profile_role() in ('admin_pusat', 'super_admin')
    or public.is_owner_provisioner()
  )
  with check (
    id = auth.uid()
    or public.current_profile_role() in ('admin_pusat', 'super_admin')
    or public.is_owner_provisioner()
  );

-- Competing permissive ALL policy leaked every profile to Owner Toko / staff.
drop policy if exists profiles_auth_all on public.profiles;
drop policy if exists profiles_authenticated_all on public.profiles;
