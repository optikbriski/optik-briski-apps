-- =============================================================================
-- Member/OBRA: summary mode also returns in-stock SKU matches (tappable list)
-- =============================================================================
-- Raises p_limit cap to 30. Empty/short query still mode=summary, but includes
-- top in-stock SKUs ordered by kategori, nama (available_qty > 0).

create or replace function public.search_member_toko_stock(
  p_toko_id text,
  p_q text default null,
  p_limit int default 8
)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_q text := nullif(trim(coalesce(p_q, '')), '');
  v_limit int := greatest(1, least(coalesce(p_limit, 8), 30));
  v_exists boolean := false;
  v_summary json;
  v_matches json;
  v_skus_in_stock int := 0;
begin
  if v_toko = '' then
    return json_build_object(
      'toko_id', null,
      'ok', false,
      'error', 'toko_id_required',
      'mode', 'summary',
      'query', null,
      'skus_in_stock', 0,
      'by_kategori', '[]'::json,
      'matches', '[]'::json
    );
  end if;

  if v_toko in ('PUSAT', 'CABANG-PUSAT') then
    return json_build_object(
      'toko_id', v_toko,
      'ok', false,
      'error', 'toko_not_branch',
      'mode', 'summary',
      'query', v_q,
      'skus_in_stock', 0,
      'by_kategori', '[]'::json,
      'matches', '[]'::json
    );
  end if;

  select exists(
    select 1 from public.toko_id t where upper(trim(t.id)) = v_toko
  ) into v_exists;

  if not v_exists then
    select exists(
      select 1
      from public.invoice_settings s
      where upper(trim(s.toko_id)) = v_toko
    ) into v_exists;
  end if;

  if not v_exists then
    return json_build_object(
      'toko_id', v_toko,
      'ok', false,
      'error', 'toko_not_found',
      'mode', 'summary',
      'query', v_q,
      'skus_in_stock', 0,
      'by_kategori', '[]'::json,
      'matches', '[]'::json
    );
  end if;

  -- Always compute category summary (useful footer even in search mode).
  select coalesce(json_agg(row_to_json(x) order by x.kategori), '[]'::json),
         coalesce(sum(x.skus_in_stock), 0)::int
  into v_summary, v_skus_in_stock
  from (
    select
      coalesce(nullif(trim(p.kategori), ''), 'Lainnya') as kategori,
      count(*) filter (
        where public.product_available_qty(
          coalesce(b.stock, 0),
          coalesce(b.reserved_qty, 0)
        ) > 0
      )::int as skus_in_stock,
      coalesce(sum(
        public.product_available_qty(
          coalesce(b.stock, 0),
          coalesce(b.reserved_qty, 0)
        )
      ), 0)::int as total_available
    from public.products p
    left join public.products b
      on upper(trim(b.toko_id)) = v_toko
     and upper(trim(b.sku)) = upper(trim(p.sku))
    where upper(trim(p.toko_id)) = 'PUSAT'
      and nullif(trim(p.sku), '') is not null
    group by 1
  ) x;

  -- Short / empty query → summary + sample of in-stock SKUs for tappable UI.
  if v_q is null or char_length(v_q) < 2 then
    select coalesce(
      json_agg(
        json_build_object(
          'sku', m.sku,
          'nama', m.nama,
          'kategori', m.kategori,
          'warna', m.warna,
          'available_qty', m.available_qty,
          'in_stock', m.in_stock
        )
        order by m.kategori, m.nama
      ),
      '[]'::json
    )
    into v_matches
    from (
      select
        p.sku,
        p.nama,
        coalesce(nullif(trim(p.kategori), ''), 'Lainnya') as kategori,
        p.warna,
        public.product_available_qty(
          coalesce(b.stock, 0),
          coalesce(b.reserved_qty, 0)
        ) as available_qty,
        true as in_stock
      from public.products p
      join public.products b
        on upper(trim(b.toko_id)) = v_toko
       and upper(trim(b.sku)) = upper(trim(p.sku))
      where upper(trim(p.toko_id)) = 'PUSAT'
        and nullif(trim(p.sku), '') is not null
        and public.product_available_qty(
          coalesce(b.stock, 0),
          coalesce(b.reserved_qty, 0)
        ) > 0
      order by 3, p.nama
      limit v_limit
    ) m;

    return json_build_object(
      'toko_id', v_toko,
      'ok', true,
      'mode', 'summary',
      'query', v_q,
      'skus_in_stock', v_skus_in_stock,
      'by_kategori', v_summary,
      'matches', v_matches
    );
  end if;

  select coalesce(
    json_agg(
      json_build_object(
        'sku', m.sku,
        'nama', m.nama,
        'kategori', m.kategori,
        'warna', m.warna,
        'available_qty', m.available_qty,
        'in_stock', m.in_stock
      )
      order by m.rank_score desc, m.nama
    ),
    '[]'::json
  )
  into v_matches
  from (
    with tokens as (
      select distinct lower(tok) as tok
      from unnest(
        regexp_split_to_array(lower(v_q), '[\s,/;]+')
      ) as tok
      where length(tok) >= 2
        and tok not in (
          'di', 'ke', 'dari', 'untuk', 'yang', 'dan', 'atau',
          'cabang', 'toko', 'stok', 'stock', 'ada', 'cek'
        )
    )
    select
      p.sku,
      p.nama,
      p.kategori,
      p.warna,
      public.product_available_qty(
        coalesce(b.stock, 0),
        coalesce(b.reserved_qty, 0)
      ) as available_qty,
      (
        public.product_available_qty(
          coalesce(b.stock, 0),
          coalesce(b.reserved_qty, 0)
        ) > 0
      ) as in_stock,
      (
        case when upper(trim(p.sku)) = upper(v_q) then 100 else 0 end
        + case when coalesce(p.barcode, '') ilike v_q then 90 else 0 end
        + case when p.nama ilike v_q then 80 else 0 end
        + case when p.nama ilike '%' || v_q || '%' then 40 else 0 end
        + case when p.sku ilike '%' || v_q || '%' then 35 else 0 end
        + (
          select coalesce(sum(
            case
              when p.nama ilike '%' || t.tok || '%' then 20
              when p.sku ilike '%' || t.tok || '%' then 18
              when coalesce(p.warna, '') ilike '%' || t.tok || '%' then 14
              when coalesce(p.kategori, '') ilike '%' || t.tok || '%' then 10
              when coalesce(p.sub_kategori, '') ilike '%' || t.tok || '%' then 8
              when coalesce(p.barcode, '') ilike '%' || t.tok || '%' then 16
              else 0
            end
          ), 0)
          from tokens t
        )
        + case
            when public.product_available_qty(
              coalesce(b.stock, 0),
              coalesce(b.reserved_qty, 0)
            ) > 0 then 10
            else 0
          end
      ) as rank_score
    from public.products p
    left join public.products b
      on upper(trim(b.toko_id)) = v_toko
     and upper(trim(b.sku)) = upper(trim(p.sku))
    where upper(trim(p.toko_id)) = 'PUSAT'
      and nullif(trim(p.sku), '') is not null
      and (
        p.nama ilike '%' || v_q || '%'
        or p.sku ilike '%' || v_q || '%'
        or coalesce(p.barcode, '') ilike '%' || v_q || '%'
        or coalesce(p.warna, '') ilike '%' || v_q || '%'
        or coalesce(p.kategori, '') ilike '%' || v_q || '%'
        or coalesce(p.sub_kategori, '') ilike '%' || v_q || '%'
        or exists (
          select 1
          from tokens t
          where p.nama ilike '%' || t.tok || '%'
             or p.sku ilike '%' || t.tok || '%'
             or coalesce(p.barcode, '') ilike '%' || t.tok || '%'
             or coalesce(p.warna, '') ilike '%' || t.tok || '%'
             or coalesce(p.kategori, '') ilike '%' || t.tok || '%'
             or coalesce(p.sub_kategori, '') ilike '%' || t.tok || '%'
        )
      )
    order by rank_score desc, p.nama
    limit v_limit
  ) m;

  return json_build_object(
    'toko_id', v_toko,
    'ok', true,
    'mode', 'search',
    'query', v_q,
    'skus_in_stock', v_skus_in_stock,
    'by_kategori', v_summary,
    'matches', v_matches
  );
end;
$$;

comment on function public.search_member_toko_stock(text, text, int) is
  'Member-safe system stock: category summary plus SKU matches (summary samples in-stock; search ranks by query). No PII, no modal price.';

revoke all on function public.search_member_toko_stock(text, text, int) from public;
grant execute on function public.search_member_toko_stock(text, text, int)
  to anon, authenticated, service_role;
