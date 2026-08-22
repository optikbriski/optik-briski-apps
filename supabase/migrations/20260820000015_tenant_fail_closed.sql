-- =============================================================================
-- Fail-closed: sesi tanpa tenant ≠ Optik. default_tenant_id hanya seed kulit #1.
-- Apply setelah 000001–000014. Jangan di-apply dari agent ke live.
-- =============================================================================

comment on function public.default_tenant_id() is
  'Hanya ID seed Optik B. Riski (tenant #1). Bukan fallback sesi. '
  'RPC wajib current_tenant_id() / require_member_tenant(); null = tolak.';

create or replace function public.require_member_tenant(p uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p is null then
    raise exception 'tenant wajib — jangan memakai data usaha lain';
  end if;
  if exists (
    select 1 from public.tenants t
    where t.id = p and t.status = 'aktif'
  ) then
    return p;
  end if;
  raise exception 'Kode usaha / tenant tidak valid';
end;
$$;

comment on function public.require_member_tenant(uuid) is
  'Fail-closed. Null tidak boleh jatuh ke Optik.';

create or replace function public.current_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v uuid;
  v_status text;
begin
  if auth.uid() is null then
    return null;
  end if;
  if public.is_platform_user() then
    select p.tenant_id into v from public.profiles p where p.id = auth.uid();
    if v is not null then
      return v;
    end if;
    select k.tenant_id into v from public.karyawan k where k.id = auth.uid() limit 1;
    return v;
  end if;

  select p.tenant_id into v from public.profiles p where p.id = auth.uid();
  if v is null then
    select k.tenant_id into v from public.karyawan k where k.id = auth.uid() limit 1;
  end if;
  if v is null then
    return null;
  end if;
  select t.status into v_status from public.tenants t where t.id = v;
  if v_status is distinct from 'aktif' then
    return null;
  end if;
  return v;
end;
$$;

comment on function public.current_tenant_id() is
  'Tenant sesi. Null jika belum login / suspend / belum terikat. Tidak pernah diam-diam Optik.';
