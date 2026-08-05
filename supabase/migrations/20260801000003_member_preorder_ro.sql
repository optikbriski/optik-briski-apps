-- Belanja Online: izinkan pre-order saat stok cabang kurang,
-- dan buat Request Order (pending_requests) ke cabang order saat lunas.

create or replace function public.create_online_order(
  p_phone text,
  p_member_id uuid,
  p_customer_name text,
  p_toko_id text,
  p_fulfillment text,
  p_courier text,
  p_address_text text,
  p_address_lat double precision,
  p_address_lng double precision,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_fulfill text := lower(trim(coalesce(p_fulfillment, '')));
  v_courier text := nullif(lower(trim(coalesce(p_courier, ''))), '');
  v_phone text := trim(coalesce(p_phone, ''));
  v_settings public.toko_delivery_settings%rowtype;
  v_item jsonb;
  v_sku text;
  v_qty int;
  v_kat text;
  v_sell jsonb;
  v_harga bigint;
  v_avail int;
  v_nama text;
  v_branch_pid uuid;
  v_pusat_pid uuid;
  v_stock_qty int;
  v_preorder_qty int;
  v_subtotal bigint := 0;
  v_ship bigint := 0;
  v_lines jsonb := '[]'::jsonb;
  v_id uuid;
  v_mid text;
  v_has_preorder boolean := false;
begin
  if v_phone = '' then
    return jsonb_build_object('ok', false, 'error', 'Login / nomor WA wajib');
  end if;
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'Pilih cabang');
  end if;
  if v_fulfill not in ('pickup', 'delivery') then
    return jsonb_build_object('ok', false, 'error', 'Metode ambil tidak valid');
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Keranjang kosong');
  end if;
  -- Alamat wajib (sinkron cabang terdekat + delivery/pickup context).
  if nullif(trim(coalesce(p_address_text, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Alamat wajib diisi dulu');
  end if;

  select * into v_settings from public.toko_delivery_settings where toko_id = v_toko;
  if not found then
    insert into public.toko_delivery_settings (toko_id) values (v_toko)
    returning * into v_settings;
  end if;

  if not coalesce(v_settings.online_selling_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang belum aktif jual online');
  end if;
  if v_fulfill = 'pickup' and not coalesce(v_settings.pickup_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang tidak menerima ambil di toko');
  end if;
  if v_fulfill = 'delivery' then
    if not coalesce(v_settings.delivery_enabled, true) then
      return jsonb_build_object('ok', false, 'error', 'Cabang tidak menerima pengiriman');
    end if;
    if v_courier is null or v_courier not in ('grab', 'gojek', 'other') then
      return jsonb_build_object('ok', false, 'error', 'Pilih kurir');
    end if;
    v_ship := case v_courier
      when 'grab' then coalesce(v_settings.fee_grab, 0)
      when 'gojek' then coalesce(v_settings.fee_gojek, 0)
      else coalesce(v_settings.fee_other, 0)
    end;
  else
    v_courier := null;
    v_ship := 0;
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(1, coalesce((v_item->>'qty')::int, 1));
    if v_sku = '' then
      return jsonb_build_object('ok', false, 'error', 'Item tanpa SKU');
    end if;

    select
      pp.kategori,
      pp.id,
      coalesce(pp.harga_jual, pp.harga, 0)::bigint,
      coalesce(nullif(trim(pp.nama), ''), v_sku)
    into v_kat, v_pusat_pid, v_harga, v_nama
    from public.products pp
    where upper(trim(pp.toko_id)) = 'PUSAT'
      and upper(trim(pp.sku)) = v_sku
    limit 1;

    if v_kat is null then
      return jsonb_build_object('ok', false, 'error', 'Produk tidak ada di katalog: ' || v_sku);
    end if;
    if lower(trim(v_kat)) = 'lensa' then
      return jsonb_build_object(
        'ok', false,
        'error',
        'Lensa custom tidak dijual online. Silakan lewat cabang / booking.'
      );
    end if;

    select elem into v_sell
    from jsonb_array_elements(
      public.list_branch_sellable(v_toko, array[v_sku])
    ) as elem
    limit 1;

    if v_sell is not null then
      v_avail := coalesce((v_sell->>'available_qty')::int, 0);
      v_harga := coalesce((v_sell->>'harga')::bigint, v_harga);
      v_nama := coalesce(nullif(trim(v_sell->>'nama'), ''), v_nama);
      v_branch_pid := nullif(v_sell->>'branch_product_id', '')::uuid;
      v_pusat_pid := coalesce(
        nullif(v_sell->>'pusat_product_id', '')::uuid,
        v_pusat_pid
      );
    else
      v_avail := 0;
      v_branch_pid := null;
    end if;

    if v_harga <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Harga tidak valid: ' || v_nama);
    end if;

    v_stock_qty := least(v_avail, v_qty);
    v_preorder_qty := greatest(0, v_qty - v_stock_qty);
    if v_preorder_qty > 0 then
      v_has_preorder := true;
    end if;

    v_subtotal := v_subtotal + (v_harga * v_qty);
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'sku', v_sku,
      'qty', v_qty,
      'stock_qty', v_stock_qty,
      'preorder_qty', v_preorder_qty,
      'pre_order', v_preorder_qty > 0,
      'harga', v_harga,
      'nama', v_nama,
      'kategori', v_kat,
      'subtotal', v_harga * v_qty,
      'branch_product_id', v_branch_pid,
      'pusat_product_id', v_pusat_pid,
      'image_url', case
        when v_sell is not null then v_sell->>'image_url'
        else null
      end
    ));
  end loop;

  v_mid := 'OBR-ON-' || to_char(timezone('utc', now()), 'YYYYMMDDHH24MISS')
        || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.online_orders (
    member_id, phone_e164, customer_name, toko_id, fulfillment, courier,
    address_text, address_lat, address_lng, shipping_fee, items,
    subtotal, total, status, midtrans_order_id,
    store_note
  ) values (
    p_member_id, v_phone, nullif(trim(coalesce(p_customer_name, '')), ''),
    v_toko, v_fulfill, v_courier,
    nullif(trim(coalesce(p_address_text, '')), ''),
    p_address_lat, p_address_lng, v_ship, v_lines,
    v_subtotal, v_subtotal + v_ship, 'pending_payment', v_mid,
    case when v_has_preorder
      then 'Ada item pre-order → RO cabang saat lunas'
      else null
    end
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'online_order_id', v_id,
    'midtrans_order_id', v_mid,
    'subtotal', v_subtotal,
    'shipping_fee', v_ship,
    'total', v_subtotal + v_ship,
    'toko_id', v_toko,
    'items', v_lines,
    'has_preorder', v_has_preorder
  );
end;
$$;

grant execute on function public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision, jsonb
) to anon, authenticated;

-- Fulfill: potong stok hanya stock_qty; sisanya jadi RO cabang (toko order).
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
      'online_order_id', v_order.id
    );
  end if;

  if v_order.status not in ('pending_payment', 'paid') then
    return jsonb_build_object('ok', false, 'error', 'Status order tidak bisa dilunasi: ' || v_order.status);
  end if;

  if p_gross_amount is not null and p_gross_amount <> v_order.total then
    return jsonb_build_object(
      'ok', false,
      'error',
      format('Nominal tidak cocok (expected %s got %s)', v_order.total, p_gross_amount)
    );
  end if;

  v_invoice := 'ON-' || to_char(timezone('Asia/Jakarta', now()), 'YYYYMMDD')
            || '-' || substr(replace(v_order.id::text, '-', ''), 1, 8);

  insert into public.sales (
    no_invoice, toko_id, nama_kasir, nama_pelanggan, no_wa, alamat,
    total_harga, dibayarkan, sisa_tagihan, kembalian,
    status_pembayaran, metode_pembayaran, tracking_status,
    channel, online_order_id, fulfillment, courier
  ) values (
    v_invoice,
    v_order.toko_id,
    'MEMBER_APP',
    coalesce(v_order.customer_name, 'Member Online'),
    v_order.phone_e164,
    case when v_order.fulfillment = 'delivery' then v_order.address_text else null end,
    v_order.total,
    v_order.total,
    0,
    0,
    'LUNAS',
    coalesce(nullif(trim(p_payment_method), ''), 'Midtrans'),
    'DIPROSES',
    'member_online',
    v_order.id,
    v_order.fulfillment,
    v_order.courier
  )
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(v_order.items)
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(1, coalesce((v_item->>'qty')::int, 1));
    v_pid := nullif(v_item->>'branch_product_id', '')::uuid;
    v_stock_qty := coalesce((v_item->>'stock_qty')::int, null);
    v_preorder_qty := coalesce((v_item->>'preorder_qty')::int, null);

    -- Backward compatible: order lama tanpa flag → anggap semua dari stok.
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
        v_stock_res := public.apply_stock_delta(
          v_order.toko_id,
          v_sku,
          -v_stock_qty,
          'SALE',
          'Online Member ' || v_invoice,
          'online_order',
          v_order.id::text,
          null,
          'MEMBER_APP',
          jsonb_build_object('channel', 'member_online', 'sale_id', v_sale_id),
          false
        );
      exception when others then
        update public.online_orders
        set store_note = coalesce(store_note || E'\n', '') ||
          ('Stok gagal: ' || v_sku || ' — ' || SQLERRM),
            updated_at = now()
        where id = v_order.id;
      end;
    end if;

    -- Pre-order → RO cabang pemenuhan order (bukan PUSAT sebagai toko_id RO).
    if v_preorder_qty > 0 then
      insert into public.pending_requests (
        toko_id,
        no_invoice,
        nama_pelanggan,
        sku,
        nama_produk,
        kategori,
        qty_request,
        tipe_request,
        status,
        tracking_status,
        detail_resep
      ) values (
        v_order.toko_id,
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
          'Online Member %s | order %s | alamat: %s',
          v_invoice,
          v_order.id::text,
          coalesce(v_order.address_text, '-')
        )
      )
      returning id into v_ro_id;
      v_ro_ids := array_append(v_ro_ids, v_ro_id);
    end if;
  end loop;

  insert into public.finance_transactions (
    toko_id, tanggal_transaksi, jenis_transaksi, kategori, deskripsi,
    nominal, status_pembayaran, metode_pembayaran, nama_kasir,
    status_konfirmasi, referensi_id, updated_at
  ) values (
    v_order.toko_id,
    (timezone('Asia/Jakarta', now()))::date,
    'PEMASUKAN',
    'Penjualan Online Member',
    format(
      'Online Member %s (%s) %s%s',
      v_invoice,
      coalesce(v_order.customer_name, v_order.phone_e164),
      case when v_order.fulfillment = 'delivery'
        then 'kirim ' || coalesce(v_order.courier, '')
        else 'pickup'
      end,
      case when cardinality(v_ro_ids) > 0 then ' + pre-order RO' else '' end
    ),
    v_order.total,
    'LUNAS',
    coalesce(nullif(trim(p_payment_method), ''), 'Midtrans'),
    'MEMBER_APP',
    'APPROVED',
    v_sale_id::text,
    now()
  );

  update public.online_orders
  set
    status = 'paid',
    sale_id = v_sale_id,
    payment_method = coalesce(nullif(trim(p_payment_method), ''), 'Midtrans'),
    paid_at = now(),
    updated_at = now(),
    store_note = case
      when cardinality(v_ro_ids) > 0 then
        trim(both E'\n' from coalesce(store_note, '') || E'\n' ||
          format('RO dibuat: %s', array_to_string(v_ro_ids, ', ')))
      else store_note
    end
  where id = v_order.id;

  return jsonb_build_object(
    'ok', true,
    'sale_id', v_sale_id,
    'no_invoice', v_invoice,
    'online_order_id', v_order.id,
    'toko_id', v_order.toko_id,
    'total', v_order.total,
    'ro_ids', to_jsonb(v_ro_ids)
  );
end;
$$;

grant execute on function public.fulfill_online_order_payment(text, text, bigint)
  to authenticated, service_role;
