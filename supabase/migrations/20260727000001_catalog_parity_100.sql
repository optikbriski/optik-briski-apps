-- =============================================================================
-- Katalog PUSAT ↔ semua cabang wajib 100% sama (SKU set + metadata).
-- Stok / reserved_qty TIDAK pernah disalin antar toko.
-- =============================================================================

-- Salin metadata katalog dari baris PUSAT ke semua toko (SKU sama). Stok aman.
create or replace function public.sync_catalog_metadata_from_pusat(p_sku text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_src public.products;
  v_n integer := 0;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;

  select * into v_src
  from public.products
  where upper(trim(sku)) = v_sku
    and upper(trim(toko_id)) = 'PUSAT'
  order by created_at
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
    sph_r = v_src.sph_r,
    sph_l = v_src.sph_l,
    cyl_r = v_src.cyl_r,
    cyl_l = v_src.cyl_l,
    add_r = v_src.add_r,
    add_l = v_src.add_l,
    image_url = v_src.image_url,
    foto_url = v_src.foto_url
  where upper(trim(p.sku)) = v_sku
    and upper(trim(p.toko_id)) <> 'PUSAT';

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Tegakkan parity 100%:
-- 1) setiap SKU di cabang mana pun → pastikan ada di PUSAT
-- 2) setiap SKU PUSAT → pastikan ada di semua toko (stok 0 jika baru)
-- 3) metadata cabang = metadata PUSAT (stok tidak diubah)
create or replace function public.enforce_catalog_parity()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku record;
  v_toko record;
  v_skus_lifted integer := 0;
  v_skus_propagated integer := 0;
  v_meta_synced integer := 0;
  v_pusat_count integer := 0;
  v_toko_count integer := 0;
  v_gaps integer := 0;
  v_n integer;
  v_expected integer;
  v_actual integer;
begin
  -- 1) Angkat SKU yang hanya ada di cabang → PUSAT (template stok 0)
  for v_sku in
    select distinct upper(trim(sku)) as sku
    from public.products
    where nullif(trim(sku), '') is not null
      and upper(trim(toko_id)) <> 'PUSAT'
      and not exists (
        select 1 from public.products p2
        where upper(trim(p2.sku)) = upper(trim(products.sku))
          and upper(trim(p2.toko_id)) = 'PUSAT'
      )
  loop
    perform public.ensure_product_at_toko(v_sku.sku, 'PUSAT', '{}'::jsonb);
    v_skus_lifted := v_skus_lifted + 1;
  end loop;

  -- 2) Sebarkan semua SKU PUSAT ke semua toko
  for v_sku in
    select distinct upper(trim(sku)) as sku
    from public.products
    where upper(trim(toko_id)) = 'PUSAT'
      and nullif(trim(sku), '') is not null
  loop
    v_n := public.propagate_pusat_sku_to_all_toko(v_sku.sku);
    v_skus_propagated := v_skus_propagated + 1;
    -- 3) Samakan metadata (bukan stok)
    v_meta_synced := v_meta_synced + public.sync_catalog_metadata_from_pusat(v_sku.sku);
  end loop;

  select count(distinct upper(trim(sku)))
  into v_pusat_count
  from public.products
  where upper(trim(toko_id)) = 'PUSAT'
    and nullif(trim(sku), '') is not null;

  select count(*) into v_toko_count
  from public.toko_id
  where upper(trim(id)) <> 'PUSAT'
    and nullif(trim(id), '') is not null;

  v_expected := v_pusat_count * v_toko_count;

  select count(*) into v_actual
  from public.products p
  where upper(trim(p.toko_id)) <> 'PUSAT'
    and nullif(trim(p.sku), '') is not null
    and exists (
      select 1 from public.products p2
      where upper(trim(p2.sku)) = upper(trim(p.sku))
        and upper(trim(p2.toko_id)) = 'PUSAT'
    )
    and exists (
      select 1 from public.toko_id t
      where upper(trim(t.id)) = upper(trim(p.toko_id))
    );

  -- Gap: kombinasi (SKU PUSAT × toko) yang belum punya baris
  select count(*) into v_gaps
  from (
    select upper(trim(p.sku)) as sku, upper(trim(t.id)) as toko
    from public.products p
    cross join public.toko_id t
    where upper(trim(p.toko_id)) = 'PUSAT'
      and nullif(trim(p.sku), '') is not null
      and upper(trim(t.id)) <> 'PUSAT'
      and nullif(trim(t.id), '') is not null
      and not exists (
        select 1 from public.products x
        where upper(trim(x.sku)) = upper(trim(p.sku))
          and upper(trim(x.toko_id)) = upper(trim(t.id))
      )
  ) missing;

  return jsonb_build_object(
    'parity_ok', (coalesce(v_gaps, 0) = 0),
    'pusat_skus', v_pusat_count,
    'toko_count', v_toko_count,
    'expected_branch_rows', v_expected,
    'actual_branch_catalog_rows', v_actual,
    'gaps', coalesce(v_gaps, 0),
    'skus_lifted_to_pusat', v_skus_lifted,
    'skus_propagated', v_skus_propagated,
    'metadata_rows_synced', v_meta_synced
  );
end;
$$;

-- Produk baru / diubah di PUSAT → sebar + samakan metadata ke semua toko
create or replace function public.trg_products_catalog_parity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if upper(trim(coalesce(new.toko_id, ''))) = 'PUSAT'
     and nullif(trim(coalesce(new.sku, '')), '') is not null then
    perform public.propagate_pusat_sku_to_all_toko(new.sku);
    perform public.sync_catalog_metadata_from_pusat(new.sku);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_products_propagate_pusat_catalog on public.products;
drop trigger if exists trg_products_catalog_parity on public.products;

create trigger trg_products_catalog_parity
  after insert or update on public.products
  for each row
  execute function public.trg_products_catalog_parity();

-- Hindari loop tak terbatas: sync metadata hanya update baris non-PUSAT,
-- trigger hanya jalan saat NEW.toko_id = PUSAT → aman.

grant execute on function public.sync_catalog_metadata_from_pusat(text) to authenticated;
grant execute on function public.enforce_catalog_parity() to authenticated;

-- Backfill lama diganti ke enforce penuh
create or replace function public.backfill_pusat_catalog_to_all_toko()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.enforce_catalog_parity();
end;
$$;

-- Jalankan sekali saat migrasi
select public.enforce_catalog_parity();
