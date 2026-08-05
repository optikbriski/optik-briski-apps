-- POS hold stok 15 menit saat masuk mode bayar (preview invoice).
-- reserved_qty naik → Tersedia turun di POS / Member / Master Data.
-- Expire / batal / lunas → lepas POS_HOLD.

-- ---------------------------------------------------------------------------
-- 1) Expire hold POS yang lewat 15 menit
-- ---------------------------------------------------------------------------
create or replace function public.expire_stale_pos_holds()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id, toko_id, sku
    from public.stock_reservations
    where status = 'active'
      and kind = 'POS_HOLD'
      and ref_type = 'pos_checkout'
      and coalesce(
        nullif(meta->>'expires_at', '')::timestamptz,
        created_at + interval '15 minutes'
      ) < now()
    for update
  loop
    update public.stock_reservations
    set status = 'released', updated_at = now()
    where id = r.id;
    perform public.recompute_product_reserved_qty(r.toko_id, r.sku);
    n := n + 1;
  end loop;
  return n;
end;
$$;

grant execute on function public.expire_stale_pos_holds()
  to authenticated, service_role;

comment on function public.expire_stale_pos_holds() is
  'Lepas POS_HOLD aktif yang lewat expires_at (default 15 menit).';

-- ---------------------------------------------------------------------------
-- 2) Hold keranjang POS (ready stock only)
-- ---------------------------------------------------------------------------
create or replace function public.hold_pos_cart_stock(
  p_toko text,
  p_ref_id text,
  p_items jsonb,
  p_hold_minutes int default 15
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_ref text := trim(coalesce(p_ref_id, ''));
  v_minutes int := greatest(1, least(coalesce(p_hold_minutes, 15), 60));
  v_expires timestamptz := now() + make_interval(mins => v_minutes);
  v_item jsonb;
  v_sku text;
  v_qty int;
  v_wanted text[] := '{}';
  v_holds jsonb := '[]'::jsonb;
  v_res jsonb;
  r record;
begin
  perform public.expire_stale_pos_holds();
  -- Juga bersihkan hold online basi supaya available akurat saat race.
  begin
    perform public.expire_stale_online_orders();
  exception when undefined_function then
    null;
  end;

  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'toko_id kosong');
  end if;
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'ref_id kosong');
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'items harus array');
  end if;

  -- Agregasi qty per SKU (keranjang bisa punya baris ganda).
  create temporary table if not exists _pos_hold_agg (
    sku text primary key,
    qty int not null
  ) on commit drop;
  delete from _pos_hold_agg;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(0, coalesce((v_item->>'qty')::int, 0));
    if v_sku = '' or v_qty <= 0 then
      continue;
    end if;
    insert into _pos_hold_agg (sku, qty) values (v_sku, v_qty)
    on conflict (sku) do update set qty = _pos_hold_agg.qty + excluded.qty;
  end loop;

  select coalesce(array_agg(sku), '{}') into v_wanted from _pos_hold_agg;

  -- Lepas hold SKU yang tidak lagi di keranjang ready.
  for r in
    select *
    from public.stock_reservations
    where status = 'active'
      and kind = 'POS_HOLD'
      and ref_type = 'pos_checkout'
      and ref_id = v_ref
      and (cardinality(v_wanted) = 0 or upper(trim(sku)) <> all (v_wanted))
    for update
  loop
    update public.stock_reservations
    set status = 'released', updated_at = now()
    where id = r.id;
    perform public.recompute_product_reserved_qty(r.toko_id, r.sku);
  end loop;

  -- Tidak ada item ready → cukup lepas semua (di atas) dan selesai.
  if not exists (select 1 from _pos_hold_agg) then
    return jsonb_build_object(
      'ok', true,
      'expires_at', v_expires,
      'hold_minutes', v_minutes,
      'holds', '[]'::jsonb,
      'ref_id', v_ref,
      'toko_id', v_toko
    );
  end if;

  for r in select sku, qty from _pos_hold_agg order by sku
  loop
    begin
      v_res := public.reserve_stock(
        v_toko,
        r.sku,
        r.qty,
        'POS_HOLD',
        'pos_checkout',
        v_ref,
        jsonb_build_object(
          'channel', 'pos',
          'hold_minutes', v_minutes,
          'expires_at', v_expires
        )
      );
      v_holds := v_holds || jsonb_build_array(v_res);
    exception when others then
      -- Rollback partial: lepas semua hold ref ini.
      perform public.release_reservation(
        'POS_HOLD', 'pos_checkout', v_ref
      );
      return jsonb_build_object(
        'ok', false,
        'error',
        format(
          'Stok tidak cukup untuk hold %s ×%s: %s',
          r.sku, r.qty, SQLERRM
        ),
        'sku', r.sku,
        'qty', r.qty
      );
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'expires_at', v_expires,
    'hold_minutes', v_minutes,
    'holds', v_holds,
    'ref_id', v_ref,
    'toko_id', v_toko
  );
end;
$$;

grant execute on function public.hold_pos_cart_stock(text, text, jsonb, int)
  to authenticated, service_role;

comment on function public.hold_pos_cart_stock(text, text, jsonb, int) is
  'Hold stok ready keranjang POS (POS_HOLD) selama hold_minutes; sync reserved_qty.';

-- ---------------------------------------------------------------------------
-- 3) Release hold POS
-- ---------------------------------------------------------------------------
create or replace function public.release_pos_cart_stock(p_ref_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text := trim(coalesce(p_ref_id, ''));
  v_res jsonb;
begin
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'ref_id kosong');
  end if;
  v_res := public.release_reservation('POS_HOLD', 'pos_checkout', v_ref);
  return jsonb_build_object(
    'ok', true,
    'ref_id', v_ref,
    'released', coalesce(v_res->>'released', '0')::int
  );
end;
$$;

grant execute on function public.release_pos_cart_stock(text)
  to authenticated, service_role;

comment on function public.release_pos_cart_stock(text) is
  'Lepas semua POS_HOLD aktif untuk ref checkout POS.';
