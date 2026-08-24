-- =============================================================================
-- 000047 — Master Data: katalog terbuka + toko yang sama + kunci anon.
-- Apply di SQL Editor live SETELAH 000046.
--
-- Celah saat toko kelola Master Data:
-- - Flutter REST products tanpa page → potong ~1000 baris (SKU hilang)
-- - lookup / sebar banding toko exact (PUSAT ≠ CABANG-PUSAT)
-- - enforce/propagate/sync masih GRANT ke anon (gagal tenant, tetap terpanggil)
-- =============================================================================

create or replace function public.ensure_product_at_toko(
  p_sku text,
  p_toko text,
  p_template jsonb default '{}'::jsonb
)
returns public.products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_toko text := upper(trim(p_toko));
  v_row public.products;
  v_src public.products;
  v_tenant uuid;
  v_pusat text;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  v_tenant := public.assert_toko_in_caller_tenant(v_toko);
  v_pusat := public.tenant_pusat_toko_id(v_tenant);

  select * into v_row
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
    and public.same_store_toko(toko_id, v_toko)
  order by case when upper(trim(toko_id)) = v_toko then 0 else 1 end
  limit 1;
  if found then
    return v_row;
  end if;

  select * into v_src
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
  order by case
    when v_pusat is not null and public.same_store_toko(toko_id, v_pusat) then 0
    else 1
  end, created_at
  limit 1;

  if not found then
    raise exception
      'SKU % belum ada di katalog. Daftarkan di Product Master.',
      v_sku
      using errcode = 'P0001';
  end if;

  insert into public.products (
    nama, harga, harga_jual, harga_modal, kategori, sub_kategori,
    barcode, sku, warna, jenis_lensa, sph_r, sph_l, cyl_r, cyl_l, add_r, add_l,
    image_url, foto_url, toko_id, stock, reserved_qty, tenant_id
  ) values (
    v_src.nama,
    coalesce(v_src.harga_jual, v_src.harga, 0),
    coalesce(v_src.harga_jual, v_src.harga, 0),
    v_src.harga_modal,
    v_src.kategori, v_src.sub_kategori,
    v_src.barcode, v_src.sku, v_src.warna, v_src.jenis_lensa,
    v_src.sph_r, v_src.sph_l, v_src.cyl_r, v_src.cyl_l, v_src.add_r, v_src.add_l,
    coalesce(nullif(trim(v_src.image_url), ''), v_src.foto_url),
    coalesce(nullif(trim(v_src.foto_url), ''), v_src.image_url),
    v_toko, 0, 0, v_tenant
  )
  returning * into v_row;
  return v_row;
end;
$$;

comment on function public.ensure_product_at_toko(text, text, jsonb) is
  'Salin SKU katalog yang sudah ada ke toko ini (stok 0). PUSAT = CABANG-PUSAT. Bukan SKU baru. Bukan anon.';

revoke all on function public.ensure_product_at_toko(text, text, jsonb)
  from public, anon;
grant execute on function public.ensure_product_at_toko(text, text, jsonb)
  to authenticated, service_role;

create or replace function public.propagate_pusat_sku_to_all_toko(
  p_sku text,
  p_tenant_id uuid default null
)
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
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  v_tenant := coalesce(p_tenant_id, public.current_tenant_id());
  if v_tenant is null then
    raise exception 'tenant wajib — katalog tidak boleh sebar ke merek lain';
  end if;
  if public.current_tenant_id() is not null
     and not public.is_platform_user()
     and public.current_tenant_id() <> v_tenant then
    raise exception 'Tenant bukan milik usaha ini';
  end if;
  v_pusat := public.tenant_pusat_toko_id(v_tenant);
  if v_pusat is null then
    raise exception 'Tenant belum punya toko PUSAT';
  end if;
  if not exists (
    select 1 from public.products
    where upper(trim(sku)) = v_sku
      and public.same_store_toko(toko_id, v_pusat)
      and tenant_id = v_tenant
  ) then
    perform public.ensure_product_at_toko(v_sku, v_pusat, '{}'::jsonb);
  end if;
  for v_toko in
    select upper(trim(id)) as id
    from public.toko_id
    where tenant_id = v_tenant
      and coalesce(is_pusat, false) = false
      and not public.same_store_toko(id, v_pusat)
      and nullif(trim(id), '') is not null
  loop
    perform public.ensure_product_at_toko(v_sku, v_toko.id, '{}'::jsonb);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

comment on function public.propagate_pusat_sku_to_all_toko(text, uuid) is
  'Sebar SKU PUSAT ke cabang tenant. Bukan CABANG-PUSAT ganda. Bukan anon.';

revoke all on function public.propagate_pusat_sku_to_all_toko(text, uuid)
  from public, anon;
grant execute on function public.propagate_pusat_sku_to_all_toko(text, uuid)
  to authenticated, service_role;

create or replace function public.sync_catalog_metadata_from_pusat(
  p_sku text,
  p_tenant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_src public.products;
  v_n integer := 0;
  v_tenant uuid;
  v_pusat text;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  v_tenant := coalesce(p_tenant_id, public.current_tenant_id());
  if v_tenant is null then
    raise exception 'tenant wajib';
  end if;
  v_pusat := public.tenant_pusat_toko_id(v_tenant);
  if v_pusat is null then
    return 0;
  end if;
  select * into v_src
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
    and public.same_store_toko(toko_id, v_pusat)
  order by case when upper(trim(toko_id)) = upper(trim(v_pusat)) then 0 else 1 end,
           created_at
  limit 1;
  if not found then
    return 0;
  end if;
  update public.products p
  set
    nama = v_src.nama,
    harga = v_src.harga,
    harga_jual = v_src.harga_jual,
    harga_modal = v_src.harga_modal,
    kategori = v_src.kategori,
    sub_kategori = v_src.sub_kategori,
    barcode = v_src.barcode,
    sku = v_src.sku,
    warna = v_src.warna,
    jenis_lensa = v_src.jenis_lensa,
    sph_r = v_src.sph_r, sph_l = v_src.sph_l,
    cyl_r = v_src.cyl_r, cyl_l = v_src.cyl_l,
    add_r = v_src.add_r, add_l = v_src.add_l,
    image_url = v_src.image_url,
    foto_url = v_src.foto_url
  where p.tenant_id = v_tenant
    and upper(trim(p.sku)) = v_sku
    and not public.same_store_toko(p.toko_id, v_pusat);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

create or replace function public.sync_catalog_metadata_from_pusat(p_sku text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  return public.sync_catalog_metadata_from_pusat(p_sku, public.current_tenant_id());
end;
$$;

revoke all on function public.sync_catalog_metadata_from_pusat(text, uuid)
  from public, anon;
revoke all on function public.sync_catalog_metadata_from_pusat(text)
  from public, anon;
grant execute on function public.sync_catalog_metadata_from_pusat(text, uuid)
  to authenticated, service_role;
grant execute on function public.sync_catalog_metadata_from_pusat(text)
  to authenticated, service_role;

create or replace function public.enforce_catalog_parity()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_t record;
  v_sku record;
  v_skus_lifted integer := 0;
  v_skus_propagated integer := 0;
  v_n integer := 0;
  v_pusat text;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if v_tenant is null and not public.is_platform_user() then
    raise exception 'tenant wajib — parity katalog tidak boleh lintas merek';
  end if;
  for v_t in
    select id from public.tenants
    where status = 'aktif'
      and (public.is_platform_user() or id = v_tenant)
  loop
    v_pusat := public.tenant_pusat_toko_id(v_t.id);
    for v_sku in
      select distinct upper(trim(p.sku)) as sku
      from public.products p
      where p.tenant_id = v_t.id
        and nullif(trim(p.sku), '') is not null
        and (v_pusat is null or not public.same_store_toko(p.toko_id, v_pusat))
        and not exists (
          select 1 from public.products p2
          where p2.tenant_id = v_t.id
            and upper(trim(p2.sku)) = upper(trim(p.sku))
            and v_pusat is not null
            and public.same_store_toko(p2.toko_id, v_pusat)
        )
    loop
      perform public.propagate_pusat_sku_to_all_toko(v_sku.sku, v_t.id);
      v_skus_lifted := v_skus_lifted + 1;
    end loop;
    for v_sku in
      select distinct upper(trim(p.sku)) as sku
      from public.products p
      where p.tenant_id = v_t.id
        and v_pusat is not null
        and public.same_store_toko(p.toko_id, v_pusat)
        and nullif(trim(p.sku), '') is not null
    loop
      perform public.propagate_pusat_sku_to_all_toko(v_sku.sku, v_t.id);
      perform public.sync_catalog_metadata_from_pusat(v_sku.sku, v_t.id);
      v_skus_propagated := v_skus_propagated + 1;
    end loop;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object(
    'ok', true,
    'tenants', v_n,
    'skus_lifted', v_skus_lifted,
    'skus_propagated', v_skus_propagated
  );
end;
$$;

comment on function public.enforce_catalog_parity() is
  'PUSAT = semua cabang (SKU + metadata). Stok tidak disalin. Bukan anon. Bukan merek lain.';

revoke all on function public.enforce_catalog_parity() from public, anon;
grant execute on function public.enforce_catalog_parity()
  to authenticated, service_role;

revoke all on function public.backfill_pusat_catalog_to_all_toko() from public, anon;
grant execute on function public.backfill_pusat_catalog_to_all_toko()
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Antrian Master Data — tanpa potong 1000 baris REST
-- -----------------------------------------------------------------------------
create or replace function public.list_master_products()
returns setof public.products
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if auth.uid() is null
     and coalesce(auth.jwt() ->> 'role', '') is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  if not public.can_edit_product_catalog() then
    raise exception 'Tidak berhak Master Data.' using errcode = '42501';
  end if;

  return query
  select p.*
  from public.products p
  where public.toko_belongs_to_current_tenant(p.toko_id)
  order by p.created_at desc;
end;
$$;

comment on function public.list_master_products() is
  'Semua baris produk tenant untuk Master Data. Bukan potong 1000 REST. Bukan anon. Bukan merek lain.';

revoke all on function public.list_master_products() from public, anon;
grant execute on function public.list_master_products()
  to authenticated, service_role;
