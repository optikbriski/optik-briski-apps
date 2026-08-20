-- Rekasa bisa nyalakan modul satu-satu (bukan cuma paket A/B/C).
-- plan_key jadi 'custom' jika campuran tidak sama dengan katalog.

create or replace function public.platform_list_tenant_modules(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if p_tenant_id is null then
    raise exception 'tenant wajib';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'module_key', m.module_key,
      'enabled', m.enabled
    ) order by m.module_key)
    from public.tenant_modules m
    where m.tenant_id = p_tenant_id
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.platform_list_tenant_modules(uuid) to authenticated;

create or replace function public.platform_set_tenant_modules(
  p_tenant_id uuid,
  p_modules jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_on boolean;
  v_known text[] := array[
    'pos', 'logistics', 'history_dp', 'warranty', 'finance',
    'master_data', 'member_app', 'attendance', 'online_orders'
  ];
  v_match text;
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if p_tenant_id is null or not exists (select 1 from public.tenants t where t.id = p_tenant_id) then
    raise exception 'Tenant tidak ada';
  end if;
  if p_modules is null or jsonb_typeof(p_modules) <> 'object' then
    raise exception 'Daftar modul wajib (json object)';
  end if;

  foreach v_key in array v_known loop
    v_on := coalesce((p_modules ->> v_key)::boolean, false);
    insert into public.tenant_modules (tenant_id, module_key, enabled)
    values (p_tenant_id, v_key, v_on)
    on conflict (tenant_id, module_key) do update set enabled = excluded.enabled;
  end loop;

  v_match := (
    select c.plan_key
    from public.tenant_plan_catalog c
    where c.plan_key <> 'custom'
      and not exists (
        select 1
        from unnest(v_known) as k(module_key)
        where exists (
          select 1 from public.tenant_plan_modules pm
          where pm.plan_key = c.plan_key and pm.module_key = k.module_key
        ) is distinct from exists (
          select 1 from public.tenant_modules tm
          where tm.tenant_id = p_tenant_id
            and tm.module_key = k.module_key
            and tm.enabled
        )
      )
    order by c.sort_order desc
    limit 1
  );

  update public.tenants
  set plan_key = coalesce(v_match, 'custom'), updated_at = now()
  where id = p_tenant_id;

  return jsonb_build_object(
    'ok', true,
    'tenant_id', p_tenant_id,
    'plan_key', coalesce(v_match, 'custom')
  );
end;
$$;

grant execute on function public.platform_set_tenant_modules(uuid, jsonb)
  to authenticated;
