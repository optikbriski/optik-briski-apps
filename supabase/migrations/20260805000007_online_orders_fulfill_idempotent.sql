-- Idempotent fulfill: cegah double sales/stok/RO/finance bila webhook retry.
-- Unique: 1 online_order → max 1 sales.

-- Bersihkan duplikat legacy (keep paling lama) sebelum unique index.
delete from public.sales a
using public.sales b
where a.online_order_id is not null
  and a.online_order_id = b.online_order_id
  and a.created_at > b.created_at;

create unique index if not exists sales_online_order_uidx
  on public.sales (online_order_id)
  where online_order_id is not null;

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
  to authenticated, service_role;
