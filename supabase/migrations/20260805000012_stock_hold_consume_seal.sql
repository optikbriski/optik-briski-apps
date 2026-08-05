-- Seal E2E: consume-hold→SALE atomik (tanpa window available),
-- hold POS tanpa temp table, katalog Member cabang-aware,
-- late Midtrans settlement, grant cancel ketat, trigger paid tidak melepaskan hold sebelum SALE.

-- ---------------------------------------------------------------------------
-- 1) Consume qty reservasi lalu SALE dalam satu transaksi (tanpa race)
-- ---------------------------------------------------------------------------
create or replace function public.consume_reservation_qty_into_sale(
  p_kind text,
  p_ref_type text,
  p_ref_id text,
  p_toko text,
  p_sku text,
  p_qty integer,
  p_alasan_text text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_ledger_ref_type text default null,
  p_ledger_ref_id text default null,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_sku text := upper(trim(coalesce(p_sku, '')));
  v_qty int := greatest(0, coalesce(p_qty, 0));
  v_res public.stock_reservations%rowtype;
  v_consumed int := 0;
  v_out jsonb;
begin
  if v_toko = '' or v_sku = '' or v_qty <= 0 then
    raise exception 'consume_reservation_qty_into_sale: argumen tidak valid';
  end if;

  -- Kunci baris hold aktif (jika ada) sebelum potong stok.
  select * into v_res
  from public.stock_reservations
  where status = 'active'
    and kind = p_kind
    and ref_type = p_ref_type
    and ref_id = p_ref_id
    and upper(trim(toko_id)) = v_toko
    and upper(trim(sku)) = v_sku
  order by created_at
  for update
  limit 1;

  if found then
    if v_res.qty > v_qty then
      update public.stock_reservations
      set qty = v_res.qty - v_qty, updated_at = now()
      where id = v_res.id;
      v_consumed := v_qty;
    else
      update public.stock_reservations
      set status = 'consumed', updated_at = now()
      where id = v_res.id;
      v_consumed := v_res.qty;
    end if;
    perform public.recompute_product_reserved_qty(v_toko, v_sku);
  end if;

  -- Setelah reserved turun (uncommitted), SALE aman; sesi lain belum lihat window.
  v_out := public.apply_stock_delta(
    v_toko,
    v_sku,
    -v_qty,
    'SALE',
    coalesce(p_alasan_text, 'Consume hold → SALE'),
    coalesce(p_ledger_ref_type, p_ref_type),
    coalesce(p_ledger_ref_id, p_ref_id),
    p_actor_id,
    p_actor_nama,
    coalesce(p_meta, '{}'::jsonb) || jsonb_build_object(
      'consumed_hold_qty', v_consumed,
      'hold_kind', p_kind
    ),
    false
  );

  return coalesce(v_out, '{}'::jsonb) || jsonb_build_object(
    'ok', true,
    'consumed_hold_qty', v_consumed
  );
end;
$$;

grant execute on function public.consume_reservation_qty_into_sale(
  text, text, text, text, text, integer, text, uuid, text, text, text, jsonb
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) POS: consume seluruh hold keranjang → SALE (atomik per panggilan)
-- ---------------------------------------------------------------------------
create or replace function public.consume_pos_cart_into_sale(
  p_toko text,
  p_ref_id text,
  p_items jsonb,
  p_invoice text,
  p_actor_id uuid default null,
  p_actor_nama text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_ref text := trim(coalesce(p_ref_id, ''));
  v_invoice text := trim(coalesce(p_invoice, ''));
  v_item jsonb;
  v_sku text;
  v_qty int;
  v_agg jsonb := '{}'::jsonb;
  v_key text;
  v_results jsonb := '[]'::jsonb;
  v_out jsonb;
begin
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'toko_id kosong');
  end if;
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'ref_id kosong');
  end if;
  if v_invoice = '' then
    return jsonb_build_object('ok', false, 'error', 'invoice kosong');
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'items harus array');
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(0, coalesce((v_item->>'qty')::int, 0));
    if v_sku = '' or v_qty <= 0 then
      continue;
    end if;
    v_agg := jsonb_set(
      v_agg,
      array[v_sku],
      to_jsonb(coalesce((v_agg->>v_sku)::int, 0) + v_qty)
    );
  end loop;

  for v_key in select key from jsonb_each_text(v_agg) order by 1
  loop
    v_qty := (v_agg->>v_key)::int;
    v_out := public.consume_reservation_qty_into_sale(
      'POS_HOLD',
      'pos_checkout',
      v_ref,
      v_toko,
      v_key,
      v_qty,
      'Penjualan POS ' || v_invoice,
      p_actor_id,
      p_actor_nama,
      'sale',
      v_invoice,
      jsonb_build_object('channel', 'pos', 'no_invoice', v_invoice)
    );
    v_results := v_results || jsonb_build_array(v_out);
  end loop;

  -- Sisa hold ref (SKU lain) dilepas.
  perform public.release_reservation('POS_HOLD', 'pos_checkout', v_ref);

  return jsonb_build_object(
    'ok', true,
    'ref_id', v_ref,
    'toko_id', v_toko,
    'invoice', v_invoice,
    'items', v_results
  );
exception when others then
  return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.consume_pos_cart_into_sale(
  text, text, jsonb, text, uuid, text
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) hold_pos_cart_stock tanpa temporary table (CTE/jsonb agg)
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
  v_agg jsonb := '{}'::jsonb;
  v_wanted text[] := '{}';
  v_holds jsonb := '[]'::jsonb;
  v_res jsonb;
  v_key text;
  r record;
begin
  perform public.expire_stale_pos_holds();
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

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(0, coalesce((v_item->>'qty')::int, 0));
    if v_sku = '' or v_qty <= 0 then
      continue;
    end if;
    v_agg := jsonb_set(
      v_agg,
      array[v_sku],
      to_jsonb(coalesce((v_agg->>v_sku)::int, 0) + v_qty)
    );
  end loop;

  select coalesce(array_agg(k order by k), '{}')
  into v_wanted
  from jsonb_object_keys(v_agg) as k;

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

  if v_agg = '{}'::jsonb then
    return jsonb_build_object(
      'ok', true,
      'expires_at', v_expires,
      'hold_minutes', v_minutes,
      'holds', '[]'::jsonb,
      'ref_id', v_ref,
      'toko_id', v_toko
    );
  end if;

  for v_key in select key from jsonb_each_text(v_agg) order by 1
  loop
    begin
      v_res := public.reserve_stock(
        v_toko,
        v_key,
        (v_agg->>v_key)::int,
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
      perform public.release_reservation('POS_HOLD', 'pos_checkout', v_ref);
      return jsonb_build_object(
        'ok', false,
        'error',
        format(
          'Stok tidak cukup untuk hold %s ×%s: %s',
          v_key, (v_agg->>v_key)::int, SQLERRM
        ),
        'sku', v_key,
        'qty', (v_agg->>v_key)::int
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

-- ---------------------------------------------------------------------------
-- 4) Trigger: lepas hold HANYA expire/cancel (paid memakai consume)
-- ---------------------------------------------------------------------------
create or replace function public.trg_online_orders_release_stock_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE'
     and OLD.status = 'pending_payment'
     and NEW.status in ('expired', 'cancelled') then
    perform public.release_reservation(
      'ONLINE_HOLD',
      'online_order',
      NEW.id::text
    );
  end if;
  return NEW;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) cancel_pending: pastikan ada (migrasi 11), lalu kunci ke service_role
-- ---------------------------------------------------------------------------
create or replace function public.cancel_pending_online_order(
  p_online_order_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.online_orders%rowtype;
begin
  if p_online_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'order_id kosong');
  end if;

  select * into v_row
  from public.online_orders
  where id = p_online_order_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
  end if;

  if v_row.status <> 'pending_payment' then
    return jsonb_build_object(
      'ok', true,
      'already', true,
      'status', v_row.status
    );
  end if;

  update public.online_orders
  set
    status = 'cancelled',
    store_note = case
      when nullif(trim(coalesce(p_reason, '')), '') is null then store_note
      else left(
        trim(coalesce(store_note || E'\n', '') || 'Cancel: ' || trim(p_reason)),
        500
      )
    end,
    updated_at = now()
  where id = v_row.id;

  begin
    perform public.release_reservation(
      'ONLINE_HOLD', 'online_order', v_row.id::text
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'ok', true,
    'cancelled', true,
    'online_order_id', v_row.id,
    'midtrans_order_id', v_row.midtrans_order_id
  );
end;
$$;

revoke execute on function public.cancel_pending_online_order(uuid, text)
  from public, anon, authenticated;
grant execute on function public.cancel_pending_online_order(uuid, text)
  to service_role;

-- Expire gabungan (aman bila migrasi 11 belum dijalankan)
create or replace function public.expire_all_stale_stock_holds()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  n_online int := 0;
  n_pos int := 0;
begin
  begin
    n_online := public.expire_stale_online_orders();
  exception when undefined_function then
    n_online := 0;
  end;
  begin
    n_pos := public.expire_stale_pos_holds();
  exception when undefined_function then
    n_pos := 0;
  end;
  return jsonb_build_object(
    'ok', true,
    'expired_online_orders', n_online,
    'expired_pos_holds', n_pos
  );
end;
$$;

grant execute on function public.expire_all_stale_stock_holds()
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) Katalog Member: available dari cabang pilihan (sku tetap dari PUSAT)
-- ---------------------------------------------------------------------------
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

grant execute on function public.list_member_catalog(text, text, int, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) fulfill: consume hold → SALE + late Midtrans settlement
-- ---------------------------------------------------------------------------
create or replace function public.fulfill_online_order_payment(
  p_midtrans_order_id text,
  p_payment_method text default 'Midtrans',
  p_gross_amount bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.online_orders%rowtype;
  v_sale_id uuid;
  v_invoice text;
  v_item jsonb;
  v_sku text;
  v_qty int;
  v_stock_qty int;
  v_preorder_qty int;
  v_pid uuid;
  v_stock_res jsonb;
  v_ro_ids bigint[] := '{}';
  v_ro_id bigint;
  v_toko text;
  v_pay text;
  v_stock_ok int := 0;
  v_stock_fail int := 0;
  v_finance_id uuid;
  v_notes text := '';
  v_existing_sale public.sales%rowtype;
  v_late boolean := false;
begin
  if nullif(trim(coalesce(p_midtrans_order_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'order_id kosong');
  end if;

  select * into v_order
  from public.online_orders
  where midtrans_order_id = trim(p_midtrans_order_id)
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
  end if;

  if v_order.status in ('paid', 'packing', 'ready', 'shipped', 'fulfilled')
     and v_order.sale_id is not null then
    return jsonb_build_object(
      'ok', true,
      'already', true,
      'sale_id', v_order.sale_id,
      'online_order_id', v_order.id,
      'toko_id', v_order.toko_id
    );
  end if;

  -- Lewat 15 menit tapi Midtrans sudah settle → lanjut (late settlement).
  if v_order.status = 'pending_payment'
     and coalesce(v_order.expires_at, v_order.created_at + interval '15 minutes') < now() then
    v_late := true;
    v_notes := v_notes || E'\nLATE_SETTLEMENT: bayar setelah expires_at; hold mungkin sudah lepas.';
  end if;

  if v_order.status in ('expired', 'cancelled') then
    v_late := true;
    v_notes := v_notes || E'\nLATE_SETTLEMENT: status=' || v_order.status || ' saat webhook lunas.';
  elsif v_order.status not in ('pending_payment', 'paid') then
    return jsonb_build_object('ok', false, 'error', 'Status order tidak bisa dilunasi: ' || v_order.status);
  end if;

  if p_gross_amount is not null and p_gross_amount <> v_order.total then
    return jsonb_build_object(
      'ok', false,
      'error',
      format('Nominal tidak cocok (expected %s got %s)', v_order.total, p_gross_amount)
    );
  end if;

  v_toko := upper(trim(coalesce(v_order.toko_id, '')));
  if v_toko = '' or v_toko in ('PUSAT', 'CABANG-PUSAT') then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Cabang pemenuhan tidak valid: ' || coalesce(v_order.toko_id, '-')
    );
  end if;
  if not exists (
    select 1 from public.toko_id t where upper(trim(t.id)) = v_toko
  ) then
    return jsonb_build_object('ok', false, 'error', 'Cabang tidak ada di master: ' || v_toko);
  end if;

  v_pay := coalesce(nullif(trim(p_payment_method), ''), 'Midtrans');

  -- Resume bila sales sudah terbuat (retry webhook / crash tengah jalan)
  select * into v_existing_sale
  from public.sales
  where online_order_id = v_order.id
  limit 1;

  if found then
    v_sale_id := v_existing_sale.id;
    v_invoice := v_existing_sale.no_invoice;

    if not exists (
      select 1 from public.finance_transactions ft
      where upper(trim(ft.toko_id)) = v_toko
        and ft.referensi_id = v_invoice
    ) then
      insert into public.finance_transactions (
        toko_id, tanggal_transaksi, jenis_transaksi, kategori, deskripsi,
        nominal, status_pembayaran, metode_pembayaran, nama_kasir,
        status_konfirmasi, referensi_id, updated_at
      ) values (
        v_toko,
        (timezone('Asia/Jakarta', now()))::date,
        'PEMASUKAN',
        'Penjualan Online Member',
        format('Online Member %s (repair sync) · toko %s', v_invoice, v_toko),
        v_order.total,
        'LUNAS',
        v_pay,
        'MEMBER_APP',
        'APPROVED',
        v_invoice,
        now()
      )
      returning id into v_finance_id;
    else
      select id into v_finance_id
      from public.finance_transactions
      where upper(trim(toko_id)) = v_toko and referensi_id = v_invoice
      limit 1;
    end if;

    perform public.release_reservation(
      'ONLINE_HOLD',
      'online_order',
      v_order.id::text
    );

    update public.online_orders
    set
      status = 'paid',
      sale_id = v_sale_id,
      payment_method = coalesce(payment_method, v_pay),
      paid_at = coalesce(paid_at, now()),
      updated_at = now()
    where id = v_order.id;

    return jsonb_build_object(
      'ok', true,
      'repaired', true,
      'sale_id', v_sale_id,
      'no_invoice', v_invoice,
      'online_order_id', v_order.id,
      'toko_id', v_toko,
      'total', v_order.total,
      'finance_id', v_finance_id
    );
  end if;

  -- Hold di-consume atomik per baris (jangan release dulu — race available).
  v_invoice := 'ON-' || to_char(timezone('Asia/Jakarta', now()), 'YYYYMMDD')
            || '-' || substr(replace(v_order.id::text, '-', ''), 1, 8);

  insert into public.sales (
    no_invoice, toko_id, nama_kasir, nama_pelanggan, no_wa, alamat,
    total_harga, dibayarkan, sisa_tagihan, kembalian,
    status_pembayaran, metode_pembayaran, tracking_status,
    channel, online_order_id, fulfillment, courier
  ) values (
    v_invoice,
    v_toko,
    'MEMBER_APP',
    coalesce(v_order.customer_name, 'Member Online'),
    v_order.phone_e164,
    case when v_order.fulfillment = 'delivery' then v_order.address_text else null end,
    v_order.total,
    v_order.total,
    0,
    0,
    'LUNAS',
    v_pay,
    'DIPROSES_DI_CABANG',
    'member_online',
    v_order.id,
    v_order.fulfillment,
    v_order.courier
  )
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(coalesce(v_order.items, '[]'::jsonb))
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(1, coalesce((v_item->>'qty')::int, 1));
    v_pid := nullif(v_item->>'branch_product_id', '')::uuid;
    v_stock_qty := coalesce((v_item->>'stock_qty')::int, null);
    v_preorder_qty := coalesce((v_item->>'preorder_qty')::int, null);

    if v_sku = '' then
      continue;
    end if;

    if v_pid is null then
      select p.id into v_pid
      from public.products p
      where upper(trim(p.toko_id)) = v_toko
        and upper(trim(p.sku)) = v_sku
      limit 1;
    end if;

    if v_stock_qty is null and v_preorder_qty is null then
      if coalesce((v_item->>'pre_order')::boolean, false) then
        v_stock_qty := 0;
        v_preorder_qty := v_qty;
      else
        v_stock_qty := v_qty;
        v_preorder_qty := 0;
      end if;
    end if;
    v_stock_qty := greatest(0, least(coalesce(v_stock_qty, 0), v_qty));
    v_preorder_qty := greatest(0, coalesce(v_preorder_qty, v_qty - v_stock_qty));

    insert into public.sales_items (
      sale_id, product_id, tipe_produk, nama_produk,
      harga_satuan, qty, subtotal
    ) values (
      v_sale_id,
      v_pid,
      coalesce(v_item->>'kategori', 'Lainnya'),
      coalesce(v_item->>'nama', v_sku),
      coalesce((v_item->>'harga')::bigint, 0),
      v_qty,
      coalesce((v_item->>'subtotal')::bigint, 0)
    );

    if v_stock_qty > 0 then
      begin
        v_stock_res := public.consume_reservation_qty_into_sale(
          'ONLINE_HOLD',
          'online_order',
          v_order.id::text,
          v_toko,
          v_sku,
          v_stock_qty,
          'Online Member ' || v_invoice,
          null,
          'MEMBER_APP',
          'online_order',
          v_order.id::text,
          jsonb_build_object(
            'channel', 'member_online',
            'sale_id', v_sale_id,
            'no_invoice', v_invoice,
            'toko_id', v_toko,
            'late_settlement', v_late
          )
        );
        v_stock_ok := v_stock_ok + 1;
      exception when others then
        v_notes := v_notes || E'\n' || format('Stok gagal %s ×%s: %s → RO', v_sku, v_stock_qty, SQLERRM);
        v_preorder_qty := v_preorder_qty + v_stock_qty;
        v_stock_qty := 0;
        v_stock_fail := v_stock_fail + 1;
      end;
    end if;

    if v_preorder_qty > 0 then
      -- Hindari double RO pada repair (invoice+sku sudah ada PENDING)
      if not exists (
        select 1 from public.pending_requests pr
        where pr.no_invoice = v_invoice
          and upper(trim(pr.sku)) = v_sku
          and upper(trim(pr.toko_id)) = v_toko
          and upper(trim(pr.status)) = 'PENDING'
      ) then
        insert into public.pending_requests (
          toko_id, no_invoice, nama_pelanggan, sku, nama_produk, kategori,
          qty_request, tipe_request, status, tracking_status, detail_resep
        ) values (
          v_toko,
          v_invoice,
          coalesce(v_order.customer_name, v_order.phone_e164, 'Member Online'),
          v_sku,
          coalesce(v_item->>'nama', v_sku),
          coalesce(v_item->>'kategori', 'Lainnya'),
          v_preorder_qty,
          'PRE_ORDER',
          'PENDING',
          'DIPROSES_DI_CABANG',
          format(
            'Online Member %s | order %s | channel=member_online | alamat: %s',
            v_invoice,
            v_order.id::text,
            coalesce(v_order.address_text, '-')
          )
        )
        returning id into v_ro_id;
        v_ro_ids := array_append(v_ro_ids, v_ro_id);
      end if;
    end if;
  end loop;

  if not exists (
    select 1 from public.finance_transactions ft
    where upper(trim(ft.toko_id)) = v_toko
      and ft.referensi_id = v_invoice
  ) then
    insert into public.finance_transactions (
      toko_id, tanggal_transaksi, jenis_transaksi, kategori, deskripsi,
      nominal, status_pembayaran, metode_pembayaran, nama_kasir,
      status_konfirmasi, referensi_id, updated_at
    ) values (
      v_toko,
      (timezone('Asia/Jakarta', now()))::date,
      'PEMASUKAN',
      'Penjualan Online Member',
      format(
        'Online Member %s (%s) %s%s · toko %s',
        v_invoice,
        coalesce(v_order.customer_name, v_order.phone_e164),
        case when v_order.fulfillment = 'delivery'
          then 'kirim ' || coalesce(v_order.courier, '')
          else 'pickup'
        end,
        case when cardinality(v_ro_ids) > 0 then ' + pre-order RO' else '' end,
        v_toko
      ),
      v_order.total,
      'LUNAS',
      v_pay,
      'MEMBER_APP',
      'APPROVED',
      v_invoice,
      now()
    )
    returning id into v_finance_id;
  else
    select id into v_finance_id
    from public.finance_transactions
    where upper(trim(toko_id)) = v_toko and referensi_id = v_invoice
    limit 1;
  end if;

  -- Safety: sisa ONLINE_HOLD aktif (qty tak terpakai) dilepas.
  perform public.release_reservation(
    'ONLINE_HOLD',
    'online_order',
    v_order.id::text
  );

  update public.online_orders
  set
    status = 'paid',
    sale_id = v_sale_id,
    payment_method = v_pay,
    paid_at = now(),
    updated_at = now(),
    store_note = trim(both E'\n' from coalesce(store_note, '') || coalesce(v_notes, '') ||
      case when cardinality(v_ro_ids) > 0 then
        E'\n' || format('RO dibuat: %s', array_to_string(v_ro_ids, ', '))
      else '' end)
  where id = v_order.id;

  return jsonb_build_object(
    'ok', true,
    'late_settlement', v_late,
    'sale_id', v_sale_id,
    'no_invoice', v_invoice,
    'online_order_id', v_order.id,
    'toko_id', v_toko,
    'total', v_order.total,
    'finance_id', v_finance_id,
    'ro_ids', to_jsonb(v_ro_ids),
    'sync', jsonb_build_object(
      'sales', true,
      'master_stock_ok', v_stock_ok,
      'master_stock_fail_to_ro', v_stock_fail,
      'logistics_ro', cardinality(v_ro_ids),
      'finance', v_finance_id is not null,
      'channel', 'member_online'
    )
  );
exception
  when unique_violation then
    -- Race: sales sudah dibuat proses paralel → resume
    select id, no_invoice into v_sale_id, v_invoice
    from public.sales
    where online_order_id = (
      select id from public.online_orders
      where midtrans_order_id = trim(p_midtrans_order_id)
      limit 1
    )
    limit 1;
    if v_sale_id is not null then
      update public.online_orders
      set status = 'paid', sale_id = v_sale_id,
          paid_at = coalesce(paid_at, now()), updated_at = now()
      where midtrans_order_id = trim(p_midtrans_order_id)
        and status = 'pending_payment';
      return jsonb_build_object(
        'ok', true,
        'already', true,
        'race', true,
        'sale_id', v_sale_id,
        'no_invoice', v_invoice
      );
    end if;
    return jsonb_build_object('ok', false, 'error', 'unique_violation fulfill');
end;
$$;


grant execute on function public.fulfill_online_order_payment(text, text, bigint)
  to service_role;

comment on function public.fulfill_online_order_payment(text, text, bigint) is
  'Lunas Midtrans: consume ONLINE_HOLD→SALE atomik (+ late settlement); idempotent.';
