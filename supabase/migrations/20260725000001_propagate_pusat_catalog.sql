-- =============================================================================
-- Katalog PUSAT = katalog semua toko (baris produk stok 0 di tiap cabang)
-- =============================================================================

-- Sebarkan 1 SKU PUSAT ke semua toko (idempotent via ensure_product_at_toko)
create or replace function public.propagate_pusat_sku_to_all_toko(p_sku text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_toko record;
  v_n integer := 0;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;

  -- Pastikan baris PUSAT ada (sumber template)
  if not exists (
    select 1 from public.products
    where upper(trim(sku)) = v_sku
      and upper(trim(toko_id)) = 'PUSAT'
  ) then
    -- Ambil sumber mana saja lalu pastikan PUSAT
    perform public.ensure_product_at_toko(v_sku, 'PUSAT', '{}'::jsonb);
  end if;

  for v_toko in
    select upper(trim(id)) as id
    from public.toko_id
    where upper(trim(id)) <> 'PUSAT'
      and nullif(trim(id), '') is not null
  loop
    perform public.ensure_product_at_toko(v_sku, v_toko.id, '{}'::jsonb);
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- Backfill semua SKU yang ada di PUSAT ke seluruh toko
create or replace function public.backfill_pusat_catalog_to_all_toko()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku record;
  v_skus integer := 0;
  v_rows integer := 0;
  v_n integer;
begin
  for v_sku in
    select distinct upper(trim(sku)) as sku
    from public.products
    where upper(trim(toko_id)) = 'PUSAT'
      and nullif(trim(sku), '') is not null
  loop
    v_n := public.propagate_pusat_sku_to_all_toko(v_sku.sku);
    v_skus := v_skus + 1;
    v_rows := v_rows + coalesce(v_n, 0);
  end loop;

  return jsonb_build_object(
    'skus', v_skus,
    'toko_writes', v_rows
  );
end;
$$;

-- Setelah produk baru masuk di PUSAT → otomatis daftar di semua toko
create or replace function public.trg_products_propagate_pusat_catalog()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if upper(trim(coalesce(new.toko_id, ''))) = 'PUSAT'
     and nullif(trim(coalesce(new.sku, '')), '') is not null then
    perform public.propagate_pusat_sku_to_all_toko(new.sku);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_products_propagate_pusat_catalog on public.products;
create trigger trg_products_propagate_pusat_catalog
  after insert on public.products
  for each row
  execute function public.trg_products_propagate_pusat_catalog();

-- Toko baru → dapat semua katalog PUSAT (stok 0)
create or replace function public.trg_toko_seed_pusat_catalog()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(new.id));
  v_sku record;
begin
  if v_toko is null or v_toko = '' or v_toko = 'PUSAT' then
    return new;
  end if;

  for v_sku in
    select distinct upper(trim(sku)) as sku
    from public.products
    where upper(trim(toko_id)) = 'PUSAT'
      and nullif(trim(sku), '') is not null
  loop
    perform public.ensure_product_at_toko(v_sku.sku, v_toko, '{}'::jsonb);
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_toko_seed_pusat_catalog on public.toko_id;
create trigger trg_toko_seed_pusat_catalog
  after insert on public.toko_id
  for each row
  execute function public.trg_toko_seed_pusat_catalog();

grant execute on function public.propagate_pusat_sku_to_all_toko(text) to authenticated;
grant execute on function public.backfill_pusat_catalog_to_all_toko() to authenticated;

-- One-shot: produk PUSAT yang sudah ada ikut terdaftar di semua toko
select public.backfill_pusat_catalog_to_all_toko();
