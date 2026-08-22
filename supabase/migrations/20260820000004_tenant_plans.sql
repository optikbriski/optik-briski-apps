-- Paket langganan Rekasa (A/B/C). Ganti paket = nyalakan/matikan modul.
-- APK, merek, dan data tenant tidak diganti. Downgrade tidak hapus nota/stok.

create table if not exists public.tenant_plan_catalog (
  plan_key text primary key,
  label text not null,
  sort_order int not null default 0
);

create table if not exists public.tenant_plan_modules (
  plan_key text not null references public.tenant_plan_catalog (plan_key) on delete cascade,
  module_key text not null,
  primary key (plan_key, module_key)
);

insert into public.tenant_plan_catalog (plan_key, label, sort_order)
values
  ('paket_c', 'Paket C — Starter (POS + master + member)', 10),
  ('paket_b', 'Paket B — Bisnis (+ logistik, garansi, absensi)', 20),
  ('paket_a', 'Paket A — Pro (semua modul)', 30)
on conflict (plan_key) do update set label = excluded.label, sort_order = excluded.sort_order;

insert into public.tenant_plan_modules (plan_key, module_key)
values
  ('paket_c', 'pos'),
  ('paket_c', 'master_data'),
  ('paket_c', 'member_app'),
  ('paket_b', 'pos'),
  ('paket_b', 'master_data'),
  ('paket_b', 'member_app'),
  ('paket_b', 'logistics'),
  ('paket_b', 'warranty'),
  ('paket_b', 'attendance'),
  ('paket_b', 'history_dp'),
  ('paket_a', 'pos'),
  ('paket_a', 'master_data'),
  ('paket_a', 'member_app'),
  ('paket_a', 'logistics'),
  ('paket_a', 'warranty'),
  ('paket_a', 'attendance'),
  ('paket_a', 'history_dp'),
  ('paket_a', 'finance'),
  ('paket_a', 'online_orders')
on conflict (plan_key, module_key) do nothing;

alter table public.tenants
  add column if not exists plan_key text not null default 'paket_c';

update public.tenants
set plan_key = 'paket_a'
where id = public.default_tenant_id();

create or replace function public.apply_tenant_plan(p_tenant uuid, p_plan text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text := lower(trim(coalesce(p_plan, '')));
begin
  if v_plan is null or v_plan = '' then
    v_plan := 'paket_c';
  end if;
  if not exists (select 1 from public.tenant_plan_catalog c where c.plan_key = v_plan) then
    raise exception 'Paket tidak dikenal: %', v_plan;
  end if;

  update public.tenants set plan_key = v_plan, updated_at = now() where id = p_tenant;

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

grant execute on function public.apply_tenant_plan(uuid, text) to service_role;

select public.apply_tenant_plan(t.id, t.plan_key)
from public.tenants t;

create or replace function public.platform_create_tenant(
  p_slug text,
  p_display_name text,
  p_short_name text default null,
  p_assistant_name text default null,
  p_legal_name text default null,
  p_plan_key text default 'paket_c'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug text := public.normalize_tenant_slug(p_slug);
  v_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_id uuid := gen_random_uuid();
  v_pusat text;
  v_code text;
  v_plan text := lower(trim(coalesce(p_plan_key, 'paket_c')));
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa (profiles.is_platform) yang boleh buat UMKM baru';
  end if;
  if v_slug is null or length(v_slug) < 3 then
    raise exception 'Kode usaha (slug) minimal 3 huruf, contoh: optik-maju';
  end if;
  if v_name is null then
    raise exception 'Nama merek wajib';
  end if;
  if exists (select 1 from public.tenants where slug = v_slug) then
    raise exception 'Kode usaha sudah dipakai';
  end if;
  if not exists (select 1 from public.tenant_plan_catalog c where c.plan_key = v_plan) then
    raise exception 'Paket tidak dikenal';
  end if;

  v_code := upper(regexp_replace(v_slug, '[^a-z0-9]', '', 'g'));
  if length(v_code) > 16 then
    v_code := substr(v_code, 1, 16);
  end if;
  v_pusat := v_code || '-PUSAT';
  if exists (select 1 from public.toko_id where id = v_pusat) then
    v_pusat := substr(replace(v_id::text, '-', ''), 1, 8) || '-PUSAT';
  end if;

  insert into public.tenants (id, slug, legal_name, status, pusat_toko_id, plan_key)
  values (
    v_id, v_slug,
    coalesce(nullif(trim(coalesce(p_legal_name, '')), ''), v_name),
    'aktif', v_pusat, v_plan
  );

  insert into public.toko_id (id, toko_id, tenant_id, cabang_code, is_pusat)
  values (v_pusat, v_name || ' — Pusat', v_id, 'PUSAT', true);

  insert into public.app_brand (id, tenant_id, display_name, short_name, assistant_name)
  values (
    v_id::text,
    v_id,
    v_name,
    coalesce(nullif(trim(coalesce(p_short_name, '')), ''), left(v_name, 8)),
    coalesce(nullif(trim(coalesce(p_assistant_name, '')), ''), left(v_name, 4) || 'A')
  );

  insert into public.member_home_content (
    id, tenant_id, brand_label, greeting_guest, greeting_subtitle_guest
  ) values (
    v_id::text,
    v_id,
    upper(v_name),
    'Hi!',
    'Login untuk lihat pesanan & garansi'
  );

  insert into public.invoice_settings (toko_id, shop_name, tenant_id)
  values (v_pusat, v_name || ' PUSAT', v_id)
  on conflict (toko_id) do nothing;

  perform public.apply_tenant_plan(v_id, v_plan);

  return jsonb_build_object(
    'ok', true,
    'tenant_id', v_id,
    'slug', v_slug,
    'pusat_toko_id', v_pusat,
    'plan_key', v_plan
  );
end;
$$;

grant execute on function public.platform_create_tenant(text, text, text, text, text, text)
  to authenticated;

create or replace function public.platform_set_tenant_plan(p_tenant_id uuid, p_plan_key text)
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
  perform public.apply_tenant_plan(p_tenant_id, p_plan_key);
  return jsonb_build_object('ok', true, 'tenant_id', p_tenant_id, 'plan_key', lower(trim(p_plan_key)));
end;
$$;

grant execute on function public.platform_set_tenant_plan(uuid, text) to authenticated;

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
      'created_at', t.created_at
    ) order by t.created_at)
    from public.tenants t
    left join public.app_brand b on b.tenant_id = t.id
    left join public.tenant_plan_catalog c on c.plan_key = t.plan_key
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.platform_list_tenants() to authenticated;

create or replace function public.list_tenant_plans()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'plan_key', c.plan_key,
    'label', c.label
  ) order by c.sort_order), '[]'::jsonb)
  from public.tenant_plan_catalog c;
$$;

grant execute on function public.list_tenant_plans() to authenticated;

create or replace function public.list_my_tenant_modules()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tid uuid;
begin
  tid := public.current_tenant_id();
  if tid is null then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'module_key', m.module_key,
      'enabled', m.enabled
    ) order by m.module_key)
    from public.tenant_modules m
    where m.tenant_id = tid
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_my_tenant_modules() to authenticated, anon;
