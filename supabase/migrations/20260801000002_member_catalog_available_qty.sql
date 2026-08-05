-- Katalog / Belanja Online: expose stok tersedia (master PUSAT).
create or replace function public.list_member_catalog(
  p_kategori text default null,
  p_q text default null,
  p_limit int default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kat text := nullif(trim(p_kategori), '');
  v_q text := nullif(trim(p_q), '');
  v_limit int := greatest(1, least(coalesce(p_limit, 120), 300));
begin
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
        public.product_available_qty(p.stock, p.reserved_qty) as available_qty
      from public.products p
      where upper(trim(p.toko_id)) = 'PUSAT'
        and nullif(trim(p.sku), '') is not null
        and (v_kat is null or lower(trim(p.kategori)) = lower(v_kat))
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

grant execute on function public.list_member_catalog(text, text, int) to anon, authenticated;
