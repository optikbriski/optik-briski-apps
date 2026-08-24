-- =============================================================================
-- 000048 — Master Data: list katalog tanpa potong max-rows PostgREST.
-- Apply di SQL Editor live SETELAH 000047.
--
-- Celah saat toko buka Master Data / kasir cari SKU:
-- - list_master_products() RETURNS SETOF masih kena db-max-rows (~1000)
--   → SKU hilang diam-diam, Flutter kira RPC sukses
-- - PUSAT + CABANG-PUSAT dua baris = stok dobel di list
-- =============================================================================

drop function if exists public.list_master_products();

create or replace function public.list_master_products(
  p_offset integer default 0,
  p_limit integer default 800
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_off integer := greatest(coalesce(p_offset, 0), 0);
  v_lim integer := least(greatest(coalesce(p_limit, 800), 1), 800);
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

  return coalesce(
    (
      select jsonb_agg(to_jsonb(p) order by p.created_at desc)
      from (
        select p.*
        from public.products p
        where public.toko_belongs_to_current_tenant(p.toko_id)
        order by p.created_at desc
        offset v_off
        limit v_lim
      ) p
    ),
    '[]'::jsonb
  );
end;
$$;

comment on function public.list_master_products(integer, integer) is
  'Halaman katalog Master Data (jsonb, bukan setof). Bukan potong 1000 REST. Bukan anon. Bukan merek lain.';

revoke all on function public.list_master_products(integer, integer)
  from public, anon;
grant execute on function public.list_master_products(integer, integer)
  to authenticated, service_role;
