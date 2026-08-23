-- =============================================================================
-- 000046 — Quick Stock Scan: toko yang sama + barcode fold + kunci anon.
-- Apply di SQL Editor live SETELAH 000045.
--
-- Celah saat toko pindai stok:
-- - lookup banding toko exact (PUSAT ≠ CABANG-PUSAT) → barang rak "tidak ketemu"
-- - barcode case-sensitive (SKU di-fold, barcode tidak)
-- - RPC belum kunci anon di body
-- =============================================================================

create or replace function public.can_quick_scan_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_inventory_for_toko(p_toko);
$$;

comment on function public.can_quick_scan_for_toko(text) is
  'Pindai stok cepat: admin toko sendiri / gudang Pusat. Bukan owner. Bukan kasir.';

revoke all on function public.can_quick_scan_for_toko(text) from public, anon;
grant execute on function public.can_quick_scan_for_toko(text)
  to authenticated, service_role;

-- Kode label produk saja. Bukan invoice, absensi, surat jalan.
create or replace function public.quick_scan_code_ok(p_code text)
returns boolean
language sql
immutable
as $$
  select
    length(trim(coalesce(p_code, ''))) between 1 and 200
    and left(trim(p_code), 1) is distinct from '{'
    and trim(p_code) not ilike 'optikbriski://%'
    and trim(p_code) not ilike 'rekasa://%'
    and not (
      position('://' in trim(p_code)) > 0
      and position('/i/' in trim(p_code)) > 0
    )
    and (
      trim(p_code) ~ '^OBRPROD\|v1\|.+'
      or left(upper(trim(p_code)), 3) is distinct from 'OBR'
    );
$$;

comment on function public.quick_scan_code_ok(text) is
  'Label produk / barcode. Bukan QR invoice, absensi, atau surat jalan.';

revoke all on function public.quick_scan_code_ok(text) from public, anon;
grant execute on function public.quick_scan_code_ok(text)
  to authenticated, service_role;

create or replace function public.lookup_quick_stock_scan(
  p_toko text,
  p_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_raw text := trim(coalesce(p_code, ''));
  v_sku text := '';
  v_id text := '';
  v_tenant uuid;
  v_row public.products;
  v_stock int;
  v_reserved int;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if auth.uid() is null
     and coalesce(auth.jwt() ->> 'role', '') is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  v_tenant := public.assert_toko_in_caller_tenant(v_toko);
  if auth.uid() is not null
     and not public.can_quick_scan_for_toko(v_toko) then
    raise exception
      'Hanya admin toko/cabang ini yang boleh pindai stok.'
      using errcode = '42501';
  end if;
  if not public.quick_scan_code_ok(v_raw) then
    raise exception 'Kode bukan label produk.' using errcode = '42501';
  end if;

  if v_raw ~ '^OBRPROD\|v1\|' then
    v_sku := trim(split_part(v_raw, '|', 3));
    v_id := trim(split_part(v_raw, '|', 4));
  else
    v_sku := v_raw;
  end if;

  if v_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    select * into v_row
    from public.products
    where tenant_id is not distinct from v_tenant
      and public.same_store_toko(toko_id, v_toko)
      and id = v_id::uuid
    order by case when upper(trim(toko_id)) = v_toko then 0 else 1 end
    limit 1;
  end if;

  if v_row.id is null and v_sku <> '' then
    select * into v_row
    from public.products
    where tenant_id is not distinct from v_tenant
      and public.same_store_toko(toko_id, v_toko)
      and upper(trim(sku)) = upper(v_sku)
    order by case when upper(trim(toko_id)) = v_toko then 0 else 1 end
    limit 1;
  end if;

  if v_row.id is null and v_sku <> '' then
    select * into v_row
    from public.products
    where tenant_id is not distinct from v_tenant
      and public.same_store_toko(toko_id, v_toko)
      and upper(trim(coalesce(barcode, ''))) = upper(v_sku)
    order by case when upper(trim(toko_id)) = v_toko then 0 else 1 end
    limit 1;
  end if;

  if v_row.id is null then
    return jsonb_build_object(
      'ok', true,
      'found', false,
      'toko_id', v_toko,
      'mutated', false
    );
  end if;

  v_stock := coalesce(v_row.stock, 0);
  v_reserved := coalesce(v_row.reserved_qty, 0);

  return jsonb_build_object(
    'ok', true,
    'found', true,
    'id', v_row.id,
    'toko_id', v_row.toko_id,
    'sku', v_row.sku,
    'barcode', v_row.barcode,
    'nama', v_row.nama,
    'kategori', v_row.kategori,
    'warna', v_row.warna,
    'jenis_lensa', v_row.jenis_lensa,
    'sph_r', v_row.sph_r,
    'cyl_r', v_row.cyl_r,
    'add_r', v_row.add_r,
    'image_url', coalesce(nullif(trim(v_row.image_url), ''), v_row.foto_url),
    'stock', v_stock,
    'reserved_qty', v_reserved,
    'available_qty', public.product_available_qty(v_stock, v_reserved),
    'harga_modal', coalesce(v_row.harga_modal, 0),
    'harga_jual', coalesce(v_row.harga_jual, v_row.harga, 0),
    'mutated', false
  );
end;
$$;

comment on function public.lookup_quick_stock_scan(text, text) is
  'Baca stok toko ini dari label. PUSAT = CABANG-PUSAT. Bukan potong stok. Bukan toko orang. Bukan merek lain.';

revoke all on function public.lookup_quick_stock_scan(text, text)
  from public, anon;
grant execute on function public.lookup_quick_stock_scan(text, text)
  to authenticated, service_role;
