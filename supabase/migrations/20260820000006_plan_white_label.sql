-- Paket atas: APK/web merek sendiri. Paket bawah: kulit Rekasa, sekat di login.

alter table public.tenant_plan_catalog
  add column if not exists white_label boolean not null default false;

alter table public.tenants
  add column if not exists white_label boolean not null default false;

update public.tenant_plan_catalog set
  label = 'Paket C — Starter · kulit Rekasa (sekat di login)',
  white_label = false
where plan_key = 'paket_c';

update public.tenant_plan_catalog set
  label = 'Paket B — Bisnis · kulit Rekasa + modul lebih lengkap',
  white_label = false
where plan_key = 'paket_b';

update public.tenant_plan_catalog set
  label = 'Paket A — Pro · APK & web merek sendiri (nama + ikon)',
  white_label = true
where plan_key = 'paket_a';

update public.tenants t
set white_label = coalesce(c.white_label, false)
from public.tenant_plan_catalog c
where c.plan_key = t.plan_key;

update public.tenants
set white_label = true
where id = public.default_tenant_id();

create or replace function public.apply_tenant_plan(p_tenant uuid, p_plan text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text := lower(trim(coalesce(p_plan, '')));
  v_wl boolean := false;
begin
  if v_plan is null or v_plan = '' then
    v_plan := 'paket_c';
  end if;
  if not exists (select 1 from public.tenant_plan_catalog c where c.plan_key = v_plan) then
    raise exception 'Paket tidak dikenal: %', v_plan;
  end if;

  select c.white_label into v_wl
  from public.tenant_plan_catalog c
  where c.plan_key = v_plan;

  update public.tenants
  set plan_key = v_plan, white_label = coalesce(v_wl, false), updated_at = now()
  where id = p_tenant;

  insert into public.tenant_modules (tenant_id, module_key, enabled)
  select p_tenant, m.k, exists (
    select 1 from public.tenant_plan_modules pm
    where pm.plan_key = v_plan and pm.module_key = m.k
  )
  from (values
    ('pos'), ('logistics'), ('history_dp'), ('warranty'),
    ('finance'), ('master_data'), ('member_app'), ('attendance'), ('online_orders')
  ) as m(k)
  on conflict (tenant_id, module_key) do update
    set enabled = excluded.enabled;
end;
$$;

create or replace function public.platform_set_tenant_white_label(
  p_tenant_id uuid,
  p_white_label boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if p_tenant_id is null or not exists (select 1 from public.tenants t where t.id = p_tenant_id) then
    raise exception 'Tenant tidak ada';
  end if;
  update public.tenants
  set white_label = coalesce(p_white_label, false), updated_at = now()
  where id = p_tenant_id;
  return jsonb_build_object('ok', true, 'tenant_id', p_tenant_id, 'white_label', coalesce(p_white_label, false));
end;
$$;

grant execute on function public.platform_set_tenant_white_label(uuid, boolean)
  to authenticated;

create or replace function public.list_tenant_plans()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'plan_key', c.plan_key,
    'label', c.label,
    'white_label', c.white_label,
    'shell', case
      when c.white_label then 'APK & web merek sendiri (nama + ikon)'
      else 'Kulit Rekasa + kode usaha di login'
    end
  ) order by c.sort_order), '[]'::jsonb)
  from public.tenant_plan_catalog c;
$$;

grant execute on function public.list_tenant_plans() to authenticated;

create or replace function public.platform_list_tenants()
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
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'slug', t.slug,
      'legal_name', t.legal_name,
      'status', t.status,
      'pusat_toko_id', t.pusat_toko_id,
      'display_name', b.display_name,
      'plan_key', t.plan_key,
      'plan_label', c.label,
      'white_label', t.white_label,
      'created_at', t.created_at
    ) order by t.created_at)
    from public.tenants t
    left join public.app_brand b on b.tenant_id = t.id
    left join public.tenant_plan_catalog c on c.plan_key = t.plan_key
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.platform_list_tenants() to authenticated;
