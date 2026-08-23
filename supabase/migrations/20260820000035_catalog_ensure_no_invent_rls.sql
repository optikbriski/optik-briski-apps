-- =============================================================================
-- 000035 — Catalog ensure: copy existing SKU only. Anon cannot invent products.
-- Apply di SQL Editor live SETELAH 000034.
--
-- Celah saat toko jalan:
-- - ensure_product_at_toko (SECURITY DEFINER) masih bisa di-POST anon
--   karena GRANT PUBLIC/anon tersisa; assert_toko_in_caller_tenant
--   lolos jika current_tenant_id() null → menulis ke tenant toko PUSAT
-- - SKU yang tidak ada di katalog di-INSERT kosong (nama=SKU, harga=0)
--   lalu trigger parity menyebar ke semua cabang
-- =============================================================================

-- Artefak probe SKU yang tidak pernah ada di Product Master.
delete from public.product_branch_revision_logs
where upper(trim(coalesce(product_sku, ''))) = 'NO-SUCH-SKU';

delete from public.products
where upper(trim(sku)) = 'NO-SUCH-SKU';

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
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  v_tenant := public.assert_toko_in_caller_tenant(v_toko);
  v_pusat := public.tenant_pusat_toko_id(v_tenant);

  select * into v_row
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
    and upper(trim(toko_id)) = v_toko
  limit 1;
  if found then
    return v_row;
  end if;

  select * into v_src
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
  order by case
    when v_pusat is not null and upper(trim(toko_id)) = upper(trim(v_pusat)) then 0
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
  'Salin SKU katalog yang sudah ada ke toko ini (stok 0). Tidak membuat SKU baru. Bukan anon.';

revoke all on function public.ensure_product_at_toko(text, text, jsonb)
  from public, anon;
grant execute on function public.ensure_product_at_toko(text, text, jsonb)
  to authenticated, service_role;
