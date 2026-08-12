-- Member catalog: server-side Lainnya bucket (not Frame / not Lensa).
-- Avoids client-only filter after a 300-row unscoped fetch hiding accessories.

drop function if exists public.list_member_catalog(text, text, int);
drop function if exists public.list_member_catalog(text, text, int, text);

create or replace function public.list_member_catalog(
  p_kategori text default null,
  p_q text default null,
  p_limit int default 120,
  p_toko text default null
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
begin
  if v_toko in ('PUSAT', 'CABANG-PUSAT') then
    v_toko := null;
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
        coalesce(v_toko, 'PUSAT') as stock_toko_id
      from public.products p
      left join public.products b
        on v_toko is not null
       and upper(trim(b.toko_id)) = v_toko
       and upper(trim(b.sku)) = upper(trim(p.sku))
      where upper(trim(p.toko_id)) = 'PUSAT'
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

grant execute on function public.list_member_catalog(text, text, int, text)
  to anon, authenticated;

comment on function public.list_member_catalog(text, text, int, text) is
  'Member Belanja Online catalog. p_kategori: Frame/Lensa equality, Lainnya = not Frame/Lensa (non-empty), null = all.';
