-- Seal sinkron 100% pesanan online → cabang terpilih:
-- Master Data (products/stock) · Logistics (RO pending_requests) · Finance&Cash (sales + finance_transactions + GL trigger)

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

  v_toko := upper(trim(coalesce(v_order.toko_id, '')));
  if v_toko = '' or v_toko in ('PUSAT', 'CABANG-PUSAT') then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Cabang pemenuhan tidak valid untuk sync modul: ' || coalesce(v_order.toko_id, '-')
    );
  end if;
  if not exists (
    select 1 from public.toko_id t where upper(trim(t.id)) = v_toko
  ) then
    return jsonb_build_object('ok', false, 'error', 'Cabang tidak ada di master toko_id: ' || v_toko);
  end if;

  v_pay := coalesce(nullif(trim(p_payment_method), ''), 'Midtrans');
  v_invoice := 'ON-' || to_char(timezone('Asia/Jakarta', now()), 'YYYYMMDD')
            || '-' || substr(replace(v_order.id::text, '-', ''), 1, 8);

  -- 1) SALES (Finance&Cash omzet + Riwayat Transaksi cabang)
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

  -- 2) ITEMS + MASTER DATA (stok cabang) + LOGISTICS (RO bila kurang/gagal potong)
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

    -- Link master data: pastikan product_id cabang terisi
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
        v_stock_res := public.apply_stock_delta(
          v_toko,
          v_sku,
          -v_stock_qty,
          'SALE',
          'Online Member ' || v_invoice,
          'online_order',
          v_order.id::text,
          null,
          'MEMBER_APP',
          jsonb_build_object(
            'channel', 'member_online',
            'sale_id', v_sale_id,
            'no_invoice', v_invoice,
            'toko_id', v_toko
          ),
          false
        );
        v_stock_ok := v_stock_ok + 1;
      exception when others then
        -- Gagal potong stok → escalate ke RO logistics cabang (jangan hilang diam-diam)
        v_notes := v_notes || E'\n' || format('Stok gagal %s ×%s: %s → RO', v_sku, v_stock_qty, SQLERRM);
        v_preorder_qty := v_preorder_qty + v_stock_qty;
        v_stock_qty := 0;
        v_stock_fail := v_stock_fail + 1;
      end;
    end if;

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
  end loop;

  -- 3) FINANCE & CASH (Buku Besar / kas harian cabang)
  -- referensi_id = no_invoice (parity POS) agar omzet tidak double-count di kas harian
  -- (omzet dihitung dari sales; FT ini jejak jurnal APPROVED).
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
    where upper(trim(toko_id)) = v_toko
      and referensi_id = v_invoice
    limit 1;
  end if;

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

  -- GL otomatis via trigger sales (trg_gl_sales_ai) + finance APPROVED (trg_gl_finance_ai)
  return jsonb_build_object(
    'ok', true,
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
end;
$$;

grant execute on function public.fulfill_online_order_payment(text, text, bigint)
  to authenticated, service_role;

comment on function public.fulfill_online_order_payment(text, text, bigint) is
  'Lunas Midtrans → sales+items+stok cabang+RO logistics+finance APPROVED (semua toko_id order).';
