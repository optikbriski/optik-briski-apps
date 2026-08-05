-- Lock E2E pesanan online: grant pembayaran, bayar uji DEV_*, cancel aman,
-- list/expire sinkron, repair stock bila sales sudah ada.

-- ---------------------------------------------------------------------------
-- 1) fulfill HANYA service_role (webhook / Edge) — cabut dari client
-- ---------------------------------------------------------------------------
revoke execute on function public.fulfill_online_order_payment(text, text, bigint)
  from public, anon, authenticated;
grant execute on function public.fulfill_online_order_payment(text, text, bigint)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2) Bayar uji: WAJIB token DEV_* (tutup bypass token null)
-- ---------------------------------------------------------------------------
create or replace function public.dev_fulfill_online_order(p_midtrans_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_status text;
begin
  select midtrans_snap_token, status
    into v_token, v_status
  from public.online_orders
  where midtrans_order_id = trim(p_midtrans_order_id);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
  end if;

  if v_status <> 'pending_payment'
     and v_status not in ('expired', 'cancelled') then
    -- Izinkan late/idempotent lewat fulfill; selain itu tolak.
    if v_status in ('paid', 'packing', 'ready', 'shipped', 'fulfilled') then
      return public.fulfill_online_order_payment(
        trim(p_midtrans_order_id), 'DEV_MOCK', null
      );
    end if;
    return jsonb_build_object(
      'ok', false,
      'error',
      'Status tidak bisa bayar uji: ' || coalesce(v_status, '-')
    );
  end if;

  if v_token is null or v_token not like 'DEV_%' then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Bayar uji hanya untuk mode tanpa Midtrans (token DEV_*)'
    );
  end if;

  return public.fulfill_online_order_payment(
    trim(p_midtrans_order_id),
    'DEV_MOCK',
    null
  );
end;
$$;

-- Anon diizinkan HANYA karena token harus DEV_* (tanpa Midtrans).
-- Bypass token-null sudah ditutup.
revoke execute on function public.dev_fulfill_online_order(text)
  from public;
grant execute on function public.dev_fulfill_online_order(text)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Member batalkan pending sendiri (lepas hold) — bukti nomor HP
-- ---------------------------------------------------------------------------
create or replace function public.cancel_pending_online_order_for_member(
  p_phone text,
  p_online_order_id uuid,
  p_reason text default 'member_cancel'
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
  if v_phone is null or p_online_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'Argumen tidak valid');
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
    )
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

  return public.cancel_pending_online_order(
    p_online_order_id,
    coalesce(nullif(trim(p_reason), ''), 'member_cancel')
  );
end;
$$;

grant execute on function public.cancel_pending_online_order_for_member(text, uuid, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Admin: cancel HANYA pending_payment (hindari stok/finance nyangkut)
-- ---------------------------------------------------------------------------
create or replace function public.update_online_order_fulfillment(
  p_order_id uuid,
  p_status text,
  p_courier_tracking text default null,
  p_store_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_toko text;
  v_allowed boolean;
  v_phone text;
  v_invoice text;
  v_fulfill text;
  v_title text;
  v_body text;
  v_uid uuid := auth.uid();
  v_role text;
  v_staff_toko text;
  v_cur text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Login staf wajib');
  end if;

  if v_status not in ('packing', 'ready', 'shipped', 'fulfilled', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'Status tidak valid');
  end if;

  select toko_id, phone_e164, fulfillment, status
    into v_toko, v_phone, v_fulfill, v_cur
  from public.online_orders
  where id = p_order_id;
  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ada');
  end if;

  select lower(coalesce(p.role, '')), upper(trim(coalesce(p.toko_id, '')))
    into v_role, v_staff_toko
  from public.profiles p
  where p.id = v_uid;

  if v_role is null then
    return jsonb_build_object('ok', false, 'error', 'Profil staf tidak ditemukan');
  end if;

  v_allowed := v_role in ('owner', 'admin_pusat', 'super_admin')
    or v_staff_toko = upper(trim(v_toko));

  if not coalesce(v_allowed, false) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Tidak berwenang: order milik ' || v_toko || ', staf ' || coalesce(v_staff_toko, '-')
    );
  end if;

  -- Cancel setelah lunas butuh refund/restock manual — jangan soft-cancel.
  if v_status = 'cancelled' and v_cur <> 'pending_payment' then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Batalkan hanya untuk pending bayar. Order lunas: proses refund/retur stok terpisah.'
    );
  end if;

  update public.online_orders
  set
    status = v_status,
    courier_tracking = coalesce(nullif(trim(p_courier_tracking), ''), courier_tracking),
    store_note = coalesce(nullif(trim(p_store_note), ''), store_note),
    updated_at = now()
  where id = p_order_id
    and (
      (v_status = 'cancelled' and status = 'pending_payment')
      or (v_status <> 'cancelled' and status in ('paid', 'packing', 'ready', 'shipped', 'fulfilled'))
    );

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order belum lunas / tidak bisa diupdate');
  end if;

  update public.sales s
  set
    tracking_status = case v_status
      when 'ready' then 'SIAP_DIAMBIL'
      when 'shipped' then 'DIKIRIM'
      when 'fulfilled' then 'DIAMBIL'
      when 'packing' then 'DIPROSES_DI_CABANG'
      when 'cancelled' then tracking_status
      else tracking_status
    end,
    diambil_at = case
      when v_status = 'fulfilled' then coalesce(s.diambil_at, now())
      else s.diambil_at
    end
  from public.online_orders o
  where o.id = p_order_id
    and s.id = o.sale_id;

  select s.no_invoice into v_invoice
  from public.online_orders o
  left join public.sales s on s.id = o.sale_id
  where o.id = p_order_id;

  if v_invoice is not null and v_phone is not null and v_status <> 'cancelled' then
    v_title := case v_status
      when 'packing' then 'Pesanan dikemas'
      when 'ready' then case when v_fulfill = 'delivery'
        then 'Pesanan siap dikirim' else 'Pesanan siap diambil' end
      when 'shipped' then 'Pesanan dalam pengiriman'
      when 'fulfilled' then 'Pesanan selesai'
      else 'Update pesanan online'
    end;
    v_body := case v_status
      when 'packing' then 'Cabang sedang menyiapkan pesanan online Anda.'
      when 'ready' then case when v_fulfill = 'delivery'
        then 'Barang siap — menunggu kurir / resi.'
        else 'Silakan ambil di cabang.' end
      when 'shipped' then coalesce(
        nullif(trim(p_courier_tracking), ''),
        'Kurir sudah membawa pesanan Anda.'
      )
      when 'fulfilled' then 'Terima kasih sudah belanja di Optik B. Riski.'
      else v_status
    end;
    begin
      perform public.create_member_order_alert(
        v_invoice, v_phone, v_title, v_body, 'status'
      );
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', v_status,
    'toko_id', v_toko,
    'order_id', p_order_id,
    'no_invoice', v_invoice
  );
end;
$$;

grant execute on function public.update_online_order_fulfillment(uuid, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5) List Member: expire hold 15m dulu (sinkron countdown)
-- ---------------------------------------------------------------------------
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
  begin
    perform public.expire_all_stale_stock_holds();
  exception when undefined_function then
    begin
      perform public.expire_stale_online_orders();
    exception when undefined_function then
      null;
    end;
  end;

  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;
  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    when v_phone like '0%' then '62' || substr(v_phone, 2)
    else v_phone
  end;

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

-- ---------------------------------------------------------------------------
-- 6) fulfill repair: consume hold bila sales ada tanpa ledger SALE
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

    -- Repair: jika ledger SALE belum ada, consume hold → SALE (jangan hanya release).
    if not exists (
      select 1 from public.product_stock_ledger l
      where l.ref_type = 'online_order'
        and l.ref_id = v_order.id::text
        and l.reason = 'SALE'
    ) then
      for v_item in select * from jsonb_array_elements(coalesce(v_order.items, '[]'::jsonb))
      loop
        v_sku := upper(trim(coalesce(v_item->>'sku', '')));
        v_stock_qty := coalesce((v_item->>'stock_qty')::int, 0);
        if v_sku = '' or v_stock_qty <= 0 then
          continue;
        end if;
        begin
          perform public.consume_reservation_qty_into_sale(
            'ONLINE_HOLD',
            'online_order',
            v_order.id::text,
            v_toko,
            v_sku,
            v_stock_qty,
            'Online Member ' || v_invoice || ' (repair)',
            null,
            'MEMBER_APP',
            'online_order',
            v_order.id::text,
            jsonb_build_object(
              'channel', 'member_online',
              'sale_id', v_sale_id,
              'repair', true
            )
          );
          v_stock_ok := v_stock_ok + 1;
        exception when others then
          v_notes := v_notes || E'\n' || format(
            'Repair stok gagal %s ×%s: %s', v_sku, v_stock_qty, SQLERRM
          );
          v_stock_fail := v_stock_fail + 1;
        end;
      end loop;
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
      updated_at = now(),
      store_note = trim(both E'\n' from coalesce(store_note, '') || coalesce(v_notes, ''))
    where id = v_order.id;

    return jsonb_build_object(
      'ok', true,
      'repaired', true,
      'sale_id', v_sale_id,
      'no_invoice', v_invoice,
      'online_order_id', v_order.id,
      'toko_id', v_toko,
      'total', v_order.total,
      'finance_id', v_finance_id,
      'master_stock_ok', v_stock_ok,
      'master_stock_fail', v_stock_fail
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



revoke execute on function public.fulfill_online_order_payment(text, text, bigint)
  from public, anon, authenticated;
grant execute on function public.fulfill_online_order_payment(text, text, bigint)
  to service_role;
