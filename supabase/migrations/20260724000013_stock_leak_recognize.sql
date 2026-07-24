-- Catat selisih stok vs ledger TANPA mengubah products.stock.
-- Dipakai fitur "Cek Kebocoran Stok" → samakan jejak agar rumus stock==sum(ledger) kembali valid.

create or replace function public.recognize_stock_variance(
  p_toko text,
  p_sku text,
  p_alasan_text text,
  p_actor_id uuid default null,
  p_actor_nama text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_sku text := trim(p_sku);
  v_row public.products;
  v_ledger_sum integer := 0;
  v_delta integer;
  v_ledger_id uuid;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  if p_alasan_text is null or trim(p_alasan_text) = '' then
    raise exception 'Alasan wajib diisi';
  end if;

  select * into v_row
  from public.products
  where upper(trim(sku)) = upper(v_sku)
    and upper(trim(toko_id)) = v_toko
  for update;

  if not found then
    raise exception 'Produk % tidak ada di %', v_sku, v_toko;
  end if;

  select coalesce(sum(qty_delta), 0) into v_ledger_sum
  from public.product_stock_ledger
  where sku = v_row.sku
    and upper(trim(toko_id)) = v_toko;

  v_delta := coalesce(v_row.stock, 0) - v_ledger_sum;
  if v_delta = 0 then
    return jsonb_build_object('ok', true, 'changed', false, 'message', 'Sudah sinkron');
  end if;

  insert into public.product_stock_ledger (
    sku, toko_id, product_id, qty_delta, stock_before, stock_after,
    reason, alasan_text, ref_type, actor_id, actor_nama, meta
  ) values (
    v_row.sku, v_toko, v_row.id, v_delta,
    coalesce(v_row.stock, 0), coalesce(v_row.stock, 0),
    'ADJUST',
    'Rekognisi selisih kebocoran (stok tidak diubah): ' || trim(p_alasan_text),
    'integrity_fix',
    p_actor_id, p_actor_nama,
    jsonb_build_object(
      'recognize_only', true,
      'stock', v_row.stock,
      'ledger_before', v_ledger_sum,
      'delta', v_delta
    )
  )
  returning id into v_ledger_id;

  return jsonb_build_object(
    'ok', true,
    'changed', true,
    'ledger_id', v_ledger_id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'stock', v_row.stock,
    'ledger_before', v_ledger_sum,
    'ledger_after', v_ledger_sum + v_delta,
    'qty_delta', v_delta
  );
end;
$$;

grant execute on function public.recognize_stock_variance(text, text, text, uuid, text)
  to authenticated;
