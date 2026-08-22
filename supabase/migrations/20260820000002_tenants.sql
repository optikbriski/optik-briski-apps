-- =============================================================================
-- Multi-tenant: satu UMKM = satu tenant. Optik B. Riski = tenant pertama.
-- Cabang (toko_id) hanya hidup di dalam tenant. Jangan jadi CABANG milik Optik.
-- Project: ualqiiprtjysdmtqkpzr
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- 0. ID tetap supaya Dart / RPC / seed selalu sama
-- -----------------------------------------------------------------------------
create or replace function public.default_tenant_id()
returns uuid
language sql
immutable
as $$
  select '00000000-0000-0000-0000-000000000001'::uuid;
$$;

comment on function public.default_tenant_id() is
  'Tenant Optik B. Riski (pelanggan pertama Rekasa).';

grant execute on function public.default_tenant_id() to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 1. Tenant + modul
-- -----------------------------------------------------------------------------
create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  legal_name text,
  status text not null default 'aktif'
    check (status in ('aktif', 'suspend', 'trial')),
  pusat_toko_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenants_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

create unique index if not exists tenants_slug_uidx on public.tenants (slug);

create table if not exists public.tenant_modules (
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  module_key text not null,
  enabled boolean not null default true,
  primary key (tenant_id, module_key)
);

insert into public.tenants (id, slug, legal_name, status, pusat_toko_id)
values (
  public.default_tenant_id(),
  'optik-briski',
  'Optik B. Riski',
  'aktif',
  'PUSAT'
)
on conflict (id) do nothing;

insert into public.tenant_modules (tenant_id, module_key, enabled)
select public.default_tenant_id(), x.k, true
from (values
  ('pos'),
  ('logistics'),
  ('history_dp'),
  ('warranty'),
  ('finance'),
  ('master_data'),
  ('member_app'),
  ('attendance'),
  ('online_orders')
) as x(k)
on conflict (tenant_id, module_key) do nothing;

alter table public.tenants enable row level security;
alter table public.tenant_modules enable row level security;

-- -----------------------------------------------------------------------------
-- 2. Helper auth (SECURITY DEFINER — baca profil tanpa RLS rekursif)
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists tenant_id uuid references public.tenants (id),
  add column if not exists is_platform boolean not null default false;

create or replace function public.current_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v uuid;
begin
  if auth.uid() is null then
    return null;
  end if;
  select p.tenant_id into v from public.profiles p where p.id = auth.uid();
  if v is not null then
    return v;
  end if;
  select k.tenant_id into v from public.karyawan k where k.id = auth.uid() limit 1;
  return v;
end;
$$;

-- Hanya profiles.is_platform / role=platform (Rekasa). super_admin Optik bukan Rekasa.
create or replace function public.is_platform_user()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
begin
  if auth.uid() is null then
    return false;
  end if;
  select coalesce(p.is_platform, false)
      or lower(coalesce(p.role, '')) = 'platform'
    into v_ok
  from public.profiles p
  where p.id = auth.uid();
  return coalesce(v_ok, false);
end;
$$;

grant execute on function public.current_tenant_id() to anon, authenticated, service_role;
grant execute on function public.is_platform_user() to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. toko_id: cabang_code unik per tenant (PUSAT boleh di setiap UMKM)
-- -----------------------------------------------------------------------------
alter table public.toko_id
  add column if not exists tenant_id uuid references public.tenants (id),
  add column if not exists cabang_code text,
  add column if not exists is_pusat boolean not null default false;

update public.toko_id
set
  tenant_id = public.default_tenant_id(),
  cabang_code = coalesce(nullif(trim(cabang_code), ''), upper(trim(id))),
  is_pusat = (upper(trim(id)) in ('PUSAT', 'CABANG-PUSAT'))
where tenant_id is null;

update public.tenants
set pusat_toko_id = 'PUSAT'
where id = public.default_tenant_id()
  and coalesce(pusat_toko_id, '') = '';

alter table public.toko_id
  alter column tenant_id set default public.default_tenant_id();

-- Unique cabang_code per tenant (PUSAT + CABANG-x)
create unique index if not exists toko_id_tenant_cabang_uidx
  on public.toko_id (tenant_id, cabang_code)
  where cabang_code is not null and cabang_code <> '';

create index if not exists toko_id_tenant_idx on public.toko_id (tenant_id);

-- -----------------------------------------------------------------------------
-- 4. tenant_id di semua tabel yang punya toko_id
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'toko_id'
      and c.table_name <> 'toko_id'
      and c.table_name not in (
        select table_name from information_schema.views
        where table_schema = 'public'
      )
  loop
    execute format(
      'alter table public.%I add column if not exists tenant_id uuid references public.tenants (id)',
      r.table_name
    );
    execute format(
      'update public.%I t set tenant_id = s.tenant_id
       from public.toko_id s
       where t.toko_id is not null
         and upper(trim(t.toko_id::text)) = upper(trim(s.id))
         and t.tenant_id is null',
      r.table_name
    );
    execute format(
      'update public.%I set tenant_id = public.default_tenant_id() where tenant_id is null',
      r.table_name
    );
    execute format(
      'create index if not exists %I on public.%I (tenant_id)',
      r.table_name || '_tenant_idx',
      r.table_name
    );
  end loop;
end
$$;

-- Trigger: isi tenant_id dari toko
create or replace function public.trg_set_tenant_from_toko()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v uuid;
  v_toko text;
begin
  v_toko := nullif(upper(trim(coalesce(new.toko_id::text, ''))), '');
  if v_toko is not null then
    select tenant_id into v from public.toko_id where upper(trim(id)) = v_toko;
  end if;
  new.tenant_id := coalesce(new.tenant_id, v, public.current_tenant_id(), public.default_tenant_id());
  return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'toko_id'
      and exists (
        select 1 from information_schema.columns x
        where x.table_schema = 'public'
          and x.table_name = c.table_name
          and x.column_name = 'tenant_id'
      )
      and c.table_name <> 'toko_id'
  loop
    execute format(
      'drop trigger if exists trg_set_tenant_from_toko on public.%I',
      r.table_name
    );
    execute format(
      'create trigger trg_set_tenant_from_toko
         before insert or update of toko_id, tenant_id
         on public.%I
         for each row
         execute function public.trg_set_tenant_from_toko()',
      r.table_name
    );
  end loop;
end
$$;

-- -----------------------------------------------------------------------------
-- 5. profiles / karyawan / owners / members
-- -----------------------------------------------------------------------------
update public.profiles
set tenant_id = coalesce(tenant_id, public.default_tenant_id())
where tenant_id is null;

alter table public.karyawan
  add column if not exists tenant_id uuid references public.tenants (id);

update public.karyawan k
set tenant_id = t.tenant_id
from public.toko_id t
where k.tenant_id is null
  and k.toko_id is not null
  and upper(trim(k.toko_id)) = upper(trim(t.id));

update public.karyawan
set tenant_id = public.default_tenant_id()
where tenant_id is null;

-- NIK / email unik per tenant (bukan global)
alter table public.karyawan drop constraint if exists karyawan_nik_key;
alter table public.karyawan drop constraint if exists karyawan_email_key;
drop index if exists public.karyawan_nik_key;
drop index if exists public.karyawan_email_key;

create unique index if not exists karyawan_nik_tenant_uidx
  on public.karyawan (tenant_id, nik)
  where nullif(trim(nik), '') is not null;

create unique index if not exists karyawan_email_tenant_uidx
  on public.karyawan (tenant_id, lower(trim(email)))
  where nullif(trim(email), '') is not null;

alter table public.owners
  add column if not exists tenant_id uuid references public.tenants (id);

update public.owners o
set tenant_id = m.tenant_id
from (
  select ot.owner_id, min(t.tenant_id::text)::uuid as tenant_id
  from public.owner_toko_map ot
  join public.toko_id t on t.id = ot.toko_id
  group by ot.owner_id
) m
where o.id = m.owner_id and o.tenant_id is null;

update public.owners
set tenant_id = public.default_tenant_id()
where tenant_id is null;

create or replace function public.trg_owners_tenant_default()
returns trigger
language plpgsql
as $$
begin
  new.tenant_id := coalesce(new.tenant_id, public.current_tenant_id(), public.default_tenant_id());
  return new;
end;
$$;

drop trigger if exists trg_owners_tenant_default on public.owners;
create trigger trg_owners_tenant_default
  before insert on public.owners
  for each row
  execute function public.trg_owners_tenant_default();

alter table public.members
  add column if not exists tenant_id uuid references public.tenants (id);

update public.members
set tenant_id = public.default_tenant_id()
where tenant_id is null;

alter table public.members
  alter column tenant_id set default public.default_tenant_id();

-- HP / email member unik per tenant
alter table public.members drop constraint if exists members_phone_e164_key;
drop index if exists public.members_phone_e164_key;
drop index if exists public.members_phone_tenant_uidx;
drop index if exists public.members_email_lower_uidx;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'members_tenant_phone_key'
      and conrelid = 'public.members'::regclass
  ) then
    alter table public.members
      add constraint members_tenant_phone_key unique (tenant_id, phone_e164);
  end if;
exception when others then
  null;
end
$$;

create unique index if not exists members_email_tenant_uidx
  on public.members (tenant_id, lower(trim(email)))
  where nullif(trim(email), '') is not null;

alter table public.member_otp
  add column if not exists tenant_id uuid references public.tenants (id);
update public.member_otp
set tenant_id = public.default_tenant_id()
where tenant_id is null;

alter table public.member_register_pending
  add column if not exists tenant_id uuid references public.tenants (id);
update public.member_register_pending
set tenant_id = public.default_tenant_id()
where tenant_id is null;

alter table public.member_password_resets
  add column if not exists tenant_id uuid references public.tenants (id);
update public.member_password_resets
set tenant_id = public.default_tenant_id()
where tenant_id is null;

create or replace function public.trg_members_tenant_default()
returns trigger
language plpgsql
as $$
begin
  new.tenant_id := coalesce(new.tenant_id, public.current_tenant_id(), public.default_tenant_id());
  return new;
end;
$$;

drop trigger if exists trg_members_tenant_default on public.members;
create trigger trg_members_tenant_default
  before insert on public.members
  for each row
  execute function public.trg_members_tenant_default();

-- -----------------------------------------------------------------------------
-- 6. app_brand + member_home_content per tenant (bukan singleton global)
-- -----------------------------------------------------------------------------
alter table public.app_brand
  add column if not exists tenant_id uuid references public.tenants (id);

alter table public.app_brand drop constraint if exists app_brand_singleton;

-- 000001 menyisakan id='default'. Insert uuid yang sama = 2 baris Optik,
-- lalu app_brand_tenant_uidx gagal (23505). Satu tenant = satu merek.
update public.app_brand
set tenant_id = public.default_tenant_id()
where tenant_id is null;

delete from public.app_brand a
where a.tenant_id is not null
  and a.ctid <> (
    select min(b.ctid)
    from public.app_brand b
    where b.tenant_id is not distinct from a.tenant_id
  );

insert into public.app_brand (id, tenant_id, display_name, short_name, assistant_name)
select
  public.default_tenant_id()::text,
  public.default_tenant_id(),
  'Optik B. Riski',
  'OBR',
  'OBRA'
where not exists (
  select 1 from public.app_brand
  where tenant_id = public.default_tenant_id()
);

create unique index if not exists app_brand_tenant_uidx on public.app_brand (tenant_id);

alter table public.member_home_content
  add column if not exists tenant_id uuid references public.tenants (id);

update public.member_home_content
set tenant_id = public.default_tenant_id()
where tenant_id is null;

delete from public.member_home_content a
where a.tenant_id is not null
  and a.ctid <> (
    select min(b.ctid)
    from public.member_home_content b
    where b.tenant_id is not distinct from a.tenant_id
  );

create unique index if not exists member_home_content_tenant_uidx
  on public.member_home_content (tenant_id);

-- -----------------------------------------------------------------------------
-- 7. Invoice unik per tenant
-- -----------------------------------------------------------------------------
drop index if exists public.sales_no_invoice_unique;
create unique index if not exists sales_no_invoice_tenant_uidx
  on public.sales (tenant_id, no_invoice)
  where no_invoice is not null;

-- -----------------------------------------------------------------------------
-- 8. RLS: staf hanya lihat tenant sendiri. Platform Rekasa lolos.
-- -----------------------------------------------------------------------------
drop policy if exists tenants_select on public.tenants;
create policy tenants_select on public.tenants
  for select to authenticated
  using (id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists tenant_modules_select on public.tenant_modules;
create policy tenant_modules_select on public.tenant_modules
  for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists tenant_modules_platform_write on public.tenant_modules;
create policy tenant_modules_platform_write on public.tenant_modules
  for all to authenticated
  using (public.is_platform_user())
  with check (public.is_platform_user());

drop policy if exists toko_id_anon_select on public.toko_id;
drop policy if exists toko_id_auth_select on public.toko_id;
drop policy if exists toko_id_auth_insert on public.toko_id;
drop policy if exists toko_id_auth_update on public.toko_id;
drop policy if exists toko_id_authenticated_all on public.toko_id;

create policy toko_id_auth_tenant on public.toko_id
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists app_brand_anon_select on public.app_brand;
drop policy if exists app_brand_auth_select on public.app_brand;
drop policy if exists app_brand_auth_update on public.app_brand;

create policy app_brand_auth_tenant on public.app_brand
  for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user());

create policy app_brand_auth_update_tenant on public.app_brand
  for update to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists member_home_content_read on public.member_home_content;
drop policy if exists member_home_content_write_pusat on public.member_home_content;

create policy member_home_content_auth_tenant on public.member_home_content
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists members_anon_all on public.members;
create policy members_auth_tenant on public.members
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists profiles_tenant on public.profiles;
create policy profiles_self_or_tenant on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or tenant_id = public.current_tenant_id()
    or public.is_platform_user()
  );

-- Produk / penjualan / stok: ganti kebijakan "semua authenticated" bila ada
drop policy if exists products_authenticated_all on public.products;
drop policy if exists products_auth_all on public.products;
create policy products_tenant_all on public.products
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists inventory_stocks_authenticated_all on public.inventory_stocks;
drop policy if exists inventory_stocks_auth_all on public.inventory_stocks;
create policy inventory_stocks_tenant_all on public.inventory_stocks
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists invoice_settings_authenticated_all on public.invoice_settings;
drop policy if exists invoice_settings_auth_all on public.invoice_settings;
create policy invoice_settings_tenant_all on public.invoice_settings
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists karyawan_authenticated_all on public.karyawan;
drop policy if exists karyawan_auth_all on public.karyawan;
create policy karyawan_tenant_all on public.karyawan
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists profiles_authenticated_all on public.profiles;
drop policy if exists profiles_auth_all on public.profiles;
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_platform_user())
  with check (id = auth.uid() or public.is_platform_user());

drop policy if exists karyawan_anon_select on public.karyawan;
create policy karyawan_anon_select on public.karyawan
  for select to anon
  using (tenant_id = public.default_tenant_id());

-- Sales: sekat tenant AND (bukan OR) ke policy owner yang sudah ada
drop policy if exists sales_tenant_all on public.sales;
drop policy if exists sales_select on public.sales;
drop policy if exists sales_insert on public.sales;
drop policy if exists sales_update on public.sales;
drop policy if exists sales_delete on public.sales;

create policy sales_select on public.sales
  for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (
      not public.is_owner_role()
      or public.is_owner_provisioner()
      or public.owner_can_access_toko(toko_id)
    )
  );

create policy sales_insert on public.sales
  for insert to authenticated
  with check (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (
      not public.is_owner_role()
      or public.is_owner_provisioner()
    )
  );

create policy sales_update on public.sales
  for update to authenticated
  using (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (
      not public.is_owner_role()
      or public.is_owner_provisioner()
    )
  )
  with check (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (
      not public.is_owner_role()
      or public.is_owner_provisioner()
    )
  );

create policy sales_delete on public.sales
  for delete to authenticated
  using (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (
      not public.is_owner_role()
      or public.is_owner_provisioner()
    )
  );

-- -----------------------------------------------------------------------------
-- 9. Katalog PUSAT hanya ke cabang TENANT yang sama
-- -----------------------------------------------------------------------------
drop function if exists public.propagate_pusat_sku_to_all_toko(text);

create or replace function public.tenant_pusat_toko_id(p_tenant uuid)
returns text
language sql
stable
as $$
  select coalesce(
    (select pusat_toko_id from public.tenants where id = p_tenant),
    (select id from public.toko_id where tenant_id = p_tenant and is_pusat limit 1)
  );
$$;

create or replace function public.propagate_pusat_sku_to_all_toko(p_sku text, p_tenant_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_toko record;
  v_n integer := 0;
  v_tenant uuid;
  v_pusat text;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;

  v_tenant := coalesce(p_tenant_id, public.current_tenant_id(), public.default_tenant_id());
  v_pusat := public.tenant_pusat_toko_id(v_tenant);
  if v_pusat is null then
    raise exception 'Tenant belum punya toko PUSAT';
  end if;

  if not exists (
    select 1 from public.products
    where upper(trim(sku)) = v_sku
      and upper(trim(toko_id)) = upper(trim(v_pusat))
      and tenant_id = v_tenant
  ) then
    perform public.ensure_product_at_toko(v_sku, v_pusat, '{}'::jsonb);
  end if;

  for v_toko in
    select upper(trim(id)) as id
    from public.toko_id
    where tenant_id = v_tenant
      and coalesce(is_pusat, false) = false
      and nullif(trim(id), '') is not null
  loop
    perform public.ensure_product_at_toko(v_sku, v_toko.id, '{}'::jsonb);
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

grant execute on function public.propagate_pusat_sku_to_all_toko(text, uuid) to authenticated;

create or replace function public.trg_products_propagate_pusat_catalog()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pusat text;
begin
  v_pusat := public.tenant_pusat_toko_id(new.tenant_id);
  if v_pusat is not null
     and upper(trim(coalesce(new.toko_id, ''))) = upper(trim(v_pusat))
     and nullif(trim(coalesce(new.sku, '')), '') is not null then
    perform public.propagate_pusat_sku_to_all_toko(new.sku, new.tenant_id);
  end if;
  return new;
end;
$$;

create or replace function public.trg_toko_seed_pusat_catalog()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku record;
  v_pusat text;
begin
  if coalesce(new.is_pusat, false) then
    return new;
  end if;
  v_pusat := public.tenant_pusat_toko_id(new.tenant_id);
  if v_pusat is null or upper(trim(new.id)) = upper(trim(v_pusat)) then
    return new;
  end if;

  for v_sku in
    select distinct upper(trim(sku)) as sku
    from public.products
    where tenant_id = new.tenant_id
      and upper(trim(toko_id)) = upper(trim(v_pusat))
      and nullif(trim(sku), '') is not null
  loop
    perform public.ensure_product_at_toko(v_sku.sku, new.id, '{}'::jsonb);
  end loop;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. RPC publik: resolve slug, brand, buat tenant (Rekasa)
-- -----------------------------------------------------------------------------
create or replace function public.resolve_tenant(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v public.tenants%rowtype;
  v_brand public.app_brand%rowtype;
begin
  if v_slug = '' then
    v_slug := 'optik-briski';
  end if;
  select * into v from public.tenants where slug = v_slug and status = 'aktif';
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Kode usaha tidak ditemukan');
  end if;
  select * into v_brand from public.app_brand where tenant_id = v.id;
  return jsonb_build_object(
    'ok', true,
    'id', v.id,
    'slug', v.slug,
    'legal_name', v.legal_name,
    'pusat_toko_id', v.pusat_toko_id,
    'display_name', coalesce(v_brand.display_name, v.legal_name),
    'short_name', v_brand.short_name,
    'assistant_name', v_brand.assistant_name
  );
end;
$$;

grant execute on function public.resolve_tenant(text) to anon, authenticated, service_role;

create or replace function public.list_tenant_stores(
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'toko_id', t.toko_id,
      'cabang_code', t.cabang_code,
      'is_pusat', t.is_pusat,
      'latitude', t.latitude,
      'longitude', t.longitude
    ) order by t.is_pusat desc, t.id)
    from public.toko_id t
    where t.tenant_id = v_tenant
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_tenant_stores(uuid)
  to anon, authenticated, service_role;

create or replace function public.app_brand_display_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(b.display_name), ''),
    'Optik B. Riski'
  )
  from public.app_brand b
  where b.tenant_id = coalesce(public.current_tenant_id(), public.default_tenant_id());
$$;

create or replace function public.normalize_tenant_slug(p text)
returns text
language sql
immutable
as $$
  select nullif(
    trim(both '-' from regexp_replace(lower(trim(coalesce(p, ''))), '[^a-z0-9]+', '-', 'g')),
    ''
  );
$$;

create or replace function public.platform_create_tenant(
  p_slug text,
  p_display_name text,
  p_short_name text default null,
  p_assistant_name text default null,
  p_legal_name text default null
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

  v_code := upper(regexp_replace(v_slug, '[^a-z0-9]', '', 'g'));
  if length(v_code) > 16 then
    v_code := substr(v_code, 1, 16);
  end if;
  v_pusat := v_code || '-PUSAT';
  if exists (select 1 from public.toko_id where id = v_pusat) then
    v_pusat := substr(replace(v_id::text, '-', ''), 1, 8) || '-PUSAT';
  end if;

  insert into public.tenants (id, slug, legal_name, status, pusat_toko_id)
  values (v_id, v_slug, coalesce(nullif(trim(coalesce(p_legal_name, '')), ''), v_name), 'aktif', v_pusat);

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

  insert into public.tenant_modules (tenant_id, module_key, enabled)
  select v_id, x.k, true
  from (values
    ('pos'), ('logistics'), ('history_dp'), ('warranty'),
    ('finance'), ('master_data'), ('member_app'), ('attendance'), ('online_orders')
  ) as x(k);

  return jsonb_build_object(
    'ok', true,
    'tenant_id', v_id,
    'slug', v_slug,
    'pusat_toko_id', v_pusat
  );
end;
$$;

grant execute on function public.platform_create_tenant(text, text, text, text, text)
  to authenticated;

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
      'created_at', t.created_at
    ) order by t.created_at)
    from public.tenants t
    left join public.app_brand b on b.tenant_id = t.id
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.platform_list_tenants() to authenticated;

-- -----------------------------------------------------------------------------
-- 11. Member RPC: filter tenant (default Optik supaya APK lama tetap jalan)
-- -----------------------------------------------------------------------------
create or replace function public.member_public_row(v public.members)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', v.id,
    'tenant_id', v.tenant_id,
    'phone_e164', v.phone_e164,
    'phone_raw', v.phone_raw,
    'nama', v.nama,
    'email', v.email,
    'alamat', v.alamat,
    'tanggal_lahir', v.tanggal_lahir,
    'font_scale', v.font_scale,
    'locale', v.locale
  );
$$;

drop function if exists public.member_login(text, text);
create function public.member_login(
  p_identifier text,
  p_password text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id text := trim(coalesce(p_identifier, ''));
  v_pass text := coalesce(p_password, '');
  v_member public.members%rowtype;
  v_phone text;
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
begin
  if v_id = '' or v_pass = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi email/HP dan password');
  end if;

  if position('@' in v_id) > 0 then
    select * into v_member from public.members m
    where m.tenant_id = v_tenant and lower(trim(m.email)) = lower(v_id)
    limit 1;
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    select * into v_member from public.members m
    where m.tenant_id = v_tenant and m.phone_e164 = v_phone
    limit 1;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan di usaha ini. Daftar dulu.');
  end if;
  if v_member.password_hash is null or trim(v_member.password_hash) = '' then
    return jsonb_build_object('ok', false, 'error',
      'Akun ini belum punya password. Pakai OTP atau Lupa password.');
  end if;
  if crypt(v_pass, v_member.password_hash) <> v_member.password_hash then
    return jsonb_build_object('ok', false, 'error', 'Password salah');
  end if;

  update public.members set updated_at = now() where id = v_member.id;
  return jsonb_build_object('ok', true, 'member', public.member_public_row(v_member));
end;
$$;

grant execute on function public.member_login(text, text, uuid) to anon, authenticated;

drop function if exists public.member_register(text, text, text, text);
drop function if exists public.member_register(text, text, text, text, date);
create function public.member_register(
  p_phone text,
  p_password text,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
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
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
begin
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
  end if;
  if length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password minimal 6 karakter');
  end if;
  if exists (
    select 1 from public.members m
    where m.tenant_id = v_tenant and m.phone_e164 = v_phone
  ) then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP sudah terdaftar di usaha ini. Silakan masuk.');
  end if;
  if v_email is not null and exists (
    select 1 from public.members m
    where m.tenant_id = v_tenant and lower(trim(m.email)) = v_email
  ) then
    return jsonb_build_object('ok', false, 'error', 'Email sudah terdaftar di usaha ini. Silakan masuk.');
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

drop function if exists public.list_member_sales(text);
create function public.list_member_sales(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        s.id, s.no_invoice, s.toko_id, s.nama_pelanggan, s.status_pembayaran,
        s.tracking_status, s.diambil_at, s.foto_hasil_url, s.sisa_tagihan,
        s.total_harga, s.dibayarkan, s.created_at, s.lunas_at,
        s.channel, s.online_order_id, s.fulfillment, s.courier,
        (s.qr_dp_token is not null and length(trim(s.qr_dp_token)) >= 8) as has_qr_dp,
        (s.qr_lunas_token is not null and length(trim(s.qr_lunas_token)) >= 8) as has_qr_lunas,
        (s.qr_claim_token is not null and length(trim(s.qr_claim_token)) >= 8) as has_qr_claim
      from public.sales s
      where s.tenant_id = v_tenant
        and (
          public.wa_digits(s.no_wa) = v_phone
          or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
        )
      order by s.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_member_sales(text, uuid) to anon, authenticated;

drop function if exists public.list_member_cabang_stores();
create function public.list_member_cabang_stores(
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows json;
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
begin
  select coalesce(
    json_agg(
      json_build_object(
        'toko_id', s.toko_id,
        'shop_name', s.shop_name,
        'address', s.address,
        'phone', s.phone,
        'google_review_url', s.google_review_url,
        'latitude', t.latitude,
        'longitude', t.longitude
      )
      order by s.toko_id
    ),
    '[]'::json
  )
  into v_rows
  from (
    select
      upper(trim(i.toko_id)) as toko_id,
      nullif(trim(i.shop_name), '') as shop_name,
      nullif(trim(i.address), '') as address,
      nullif(trim(i.phone), '') as phone,
      nullif(trim(i.google_review_url), '') as google_review_url
    from public.invoice_settings i
    where i.tenant_id = v_tenant
      and nullif(trim(i.toko_id), '') is not null
  ) s
  left join public.toko_id t
    on upper(trim(t.id)) = s.toko_id
   and t.tenant_id = v_tenant;

  return v_rows;
end;
$$;

grant execute on function public.list_member_cabang_stores(uuid)
  to anon, authenticated, service_role;

drop function if exists public.list_member_help_stores();
create function public.list_member_help_stores(
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows json;
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
  v_pusat text := public.tenant_pusat_toko_id(v_tenant);
begin
  select coalesce(
    json_agg(
      json_build_object(
        'toko_id', s.toko_id,
        'shop_name', s.shop_name,
        'address', s.address,
        'phone', s.phone,
        'google_review_url', s.google_review_url,
        'latitude', t.latitude,
        'longitude', t.longitude
      )
      order by s.toko_id
    ),
    '[]'::json
  )
  into v_rows
  from (
    select
      upper(trim(i.toko_id)) as toko_id,
      nullif(trim(i.shop_name), '') as shop_name,
      nullif(trim(i.address), '') as address,
      nullif(trim(i.phone), '') as phone,
      nullif(trim(i.google_review_url), '') as google_review_url
    from public.invoice_settings i
    where i.tenant_id = v_tenant
      and nullif(trim(i.toko_id), '') is not null
      and upper(trim(i.toko_id)) not in ('PUSAT', 'CABANG-PUSAT')
      and upper(trim(i.toko_id)) is distinct from upper(trim(coalesce(v_pusat, '')))
  ) s
  left join public.toko_id t
    on upper(trim(t.id)) = s.toko_id
   and t.tenant_id = v_tenant;

  return v_rows;
end;
$$;

grant execute on function public.list_member_help_stores(uuid)
  to anon, authenticated, service_role;

drop function if exists public.list_member_catalog(text, text, int, text);
create function public.list_member_catalog(
  p_kategori text default null,
  p_q text default null,
  p_limit int default 120,
  p_toko text default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kat text := nullif(trim(p_kategori), '');
  v_kat_norm text := lower(trim(coalesce(v_kat, '')));
  v_q text := nullif(trim(p_q), '');
  v_limit int := greatest(1, least(coalesce(p_limit, 120), 300));
  v_toko text := nullif(upper(trim(coalesce(p_toko, ''))), '');
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
  v_pusat text := public.tenant_pusat_toko_id(v_tenant);
begin
  if v_toko is not null and exists (
    select 1 from public.toko_id t
    where t.tenant_id = v_tenant
      and upper(trim(t.id)) = v_toko
      and t.is_pusat
  ) then
    v_toko := null;
  end if;
  if v_toko in ('PUSAT', 'CABANG-PUSAT') then
    v_toko := null;
  end if;
  if v_pusat is null then
    v_pusat := 'PUSAT';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.nama)
    from (
      select
        p.id,
        p.sku,
        p.barcode,
        p.nama,
        p.kategori,
        p.sub_kategori,
        p.warna,
        p.jenis_lensa,
        coalesce(p.harga_jual, p.harga) as harga,
        case
          when p.harga is not null
            and p.harga_jual is not null
            and p.harga > p.harga_jual
          then p.harga
          else null
        end as harga_asli,
        coalesce(nullif(trim(p.image_url), ''), nullif(trim(p.foto_url), '')) as image_url,
        case
          when v_toko is null then
            public.product_available_qty(p.stock, p.reserved_qty)
          else
            public.product_available_qty(
              coalesce(b.stock, 0),
              coalesce(b.reserved_qty, 0)
            )
        end as available_qty,
        coalesce(v_toko, v_pusat) as stock_toko_id
      from public.products p
      left join public.products b
        on v_toko is not null
       and b.tenant_id = v_tenant
       and upper(trim(b.toko_id)) = v_toko
       and upper(trim(b.sku)) = upper(trim(p.sku))
      where p.tenant_id = v_tenant
        and upper(trim(p.toko_id)) = upper(trim(v_pusat))
        and nullif(trim(p.sku), '') is not null
        and (
          v_kat is null
          or (
            v_kat_norm = 'lainnya'
            and nullif(trim(p.kategori), '') is not null
            and lower(trim(p.kategori)) not in ('frame', 'lensa')
          )
          or (
            v_kat_norm <> 'lainnya'
            and lower(trim(p.kategori)) = v_kat_norm
          )
        )
        and (
          v_q is null
          or p.nama ilike '%' || v_q || '%'
          or p.sku ilike '%' || v_q || '%'
          or coalesce(p.barcode, '') ilike '%' || v_q || '%'
          or coalesce(p.warna, '') ilike '%' || v_q || '%'
        )
      order by p.nama
      limit v_limit
    ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_member_catalog(text, text, int, text, uuid)
  to anon, authenticated;

-- Upsert profil: conflict per tenant
drop function if exists public.member_upsert_profile(text, text, text, text, numeric, text);
drop function if exists public.member_upsert_profile(text, text, text, text, text, date, numeric, text);

create function public.member_upsert_profile(
  p_phone text,
  p_nama text default null,
  p_email text default null,
  p_alamat text default null,
  p_phone_raw text default null,
  p_tanggal_lahir date default null,
  p_font_scale numeric default null,
  p_locale text default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
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
  v_tenant uuid := coalesce(p_tenant_id, public.default_tenant_id());
begin
  if v_phone is null then
    raise exception 'Nomor HP / WhatsApp tidak valid';
  end if;

  if v_email is not null and exists (
    select 1 from public.members m
    where m.tenant_id = v_tenant
      and lower(trim(m.email)) = v_email
      and m.phone_e164 <> v_phone
  ) then
    raise exception 'Email sudah dipakai akun lain di usaha ini';
  end if;

  insert into public.members (
    tenant_id, phone_e164, phone_raw, nama, email, alamat, tanggal_lahir, font_scale, locale
  ) values (
    v_tenant,
    v_phone,
    coalesce(nullif(trim(coalesce(p_phone_raw, '')), ''), trim(p_phone)),
    nullif(trim(coalesce(p_nama, '')), ''),
    v_email,
    nullif(trim(coalesce(p_alamat, '')), ''),
    p_tanggal_lahir,
    coalesce(p_font_scale, 1.0),
    coalesce(nullif(trim(coalesce(p_locale, '')), ''), 'id')
  )
  on conflict (tenant_id, phone_e164) do update set
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

  select * into v_member
  from public.members
  where tenant_id = v_tenant and phone_e164 = v_phone;

  return jsonb_build_object(
    'id', v_member.id,
    'tenant_id', v_member.tenant_id,
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

grant execute on function public.member_upsert_profile(text, text, text, text, text, date, numeric, text, uuid)
  to anon, authenticated;

comment on table public.tenants is
  'Satu UMKM = satu tenant. Rekasa (is_platform) membuat baris baru; bukan cabang Optik.';
