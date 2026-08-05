-- Harden E2E online orders (setelah 20260805000001)
-- 1) fulfill tracking DIPROSES_DI_CABANG (jangan andalkan trigger saja)
-- 2) list/get online orders: match phone via wa_digits (0↔ 62)

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
    'DIPROSES_DI_CABANG',
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

create or replace function public.list_member_online_orders(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
begin
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;
  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    when v_phone like '0%' then '62' || substr(v_phone, 2)
    else v_phone
  end;

  update public.online_orders
  set status = 'expired', updated_at = now()
  where status = 'pending_payment'
    and created_at < now() - interval '24 hours'
    and (
      phone_e164 = v_phone
      or phone_e164 = v_alt
      or public.wa_digits(phone_e164) = v_phone
    );

  return coalesce((
    select jsonb_agg(to_jsonb(o) order by o.created_at desc)
    from (
      select *
      from public.online_orders
      where phone_e164 = v_phone
         or phone_e164 = v_alt
         or public.wa_digits(phone_e164) = v_phone
      order by created_at desc
      limit 40
    ) o
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_member_online_orders(text)
  to anon, authenticated;

create or replace function public.get_online_order_for_member(
  p_phone text,
  p_online_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_row public.online_orders%rowtype;
begin
  if v_phone is null then
    return jsonb_build_object('ok', false, 'error', 'Nomor tidak valid');
  end if;
  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    when v_phone like '0%' then '62' || substr(v_phone, 2)
    else v_phone
  end;

  select * into v_row
  from public.online_orders
  where id = p_online_order_id
    and (
      phone_e164 = v_phone
      or phone_e164 = v_alt
      or public.wa_digits(phone_e164) = v_phone
    );

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Tidak ditemukan');
  end if;

  return jsonb_build_object(
    'ok', true,
    'order', to_jsonb(v_row)
  );
end;
$$;

grant execute on function public.get_online_order_for_member(text, uuid)
  to anon, authenticated;

-- Pastikan create_online_order menyimpan phone_e164 dinormalisasi
-- (patch ringan: wrap via trigger before insert)
create or replace function public.trg_online_orders_normalize_phone()
returns trigger
language plpgsql
as $$
declare
  d text;
begin
  d := public.wa_digits(NEW.phone_e164);
  if d is not null and length(d) >= 8 then
    NEW.phone_e164 := d;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_online_orders_normalize_phone on public.online_orders;
create trigger trg_online_orders_normalize_phone
  before insert or update of phone_e164
  on public.online_orders
  for each row
  execute function public.trg_online_orders_normalize_phone();
