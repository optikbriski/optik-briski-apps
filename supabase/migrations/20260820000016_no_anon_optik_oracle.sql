-- =============================================================================
-- 000016 — anon tidak boleh memakai merek/UUID Optik sebagai default publik.
-- Apply setelah 000015.
-- =============================================================================

create or replace function public.app_brand_display_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(b.display_name), '')
  from public.app_brand b
  where b.tenant_id = public.current_tenant_id();
$$;

comment on function public.app_brand_display_name() is
  'Nama merek sesi. Anon / tanpa tenant = null. Tidak pernah diam-diam Optik.';

revoke all on function public.default_tenant_id() from public;
revoke all on function public.default_tenant_id() from anon;
grant execute on function public.default_tenant_id() to authenticated, service_role;

-- Jangan isi tenant_id otomatis ke Optik saat INSERT tanpa nilai.
do $$
declare
  r record;
begin
  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'tenant_id'
      and c.column_default is not null
      and c.column_default like '%default_tenant_id%'
  loop
    execute format(
      'alter table public.%I alter column tenant_id drop default',
      r.table_name
    );
  end loop;
end
$$;
