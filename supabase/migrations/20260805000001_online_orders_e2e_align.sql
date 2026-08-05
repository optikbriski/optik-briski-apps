-- Align pesanan online E2E:
-- 1) pickup tanpa alamat wajib
-- 2) tracking sales DIPROSES_DI_CABANG + DIKIRIM label + diambil_at
-- 3) list online orders untuk Member
-- 4) alert status ke member_order_alerts
-- 5) expire pending_payment > 24 jam (saat list)

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
  p_items jsonb,
  p_shipping_fee bigint default null,
  p_courier_company text default null,
  p_courier_service_code text default null,
  p_courier_service_name text default null,
  p_shipping_category text default null,
  p_is_obr boolean default false,
  p_shipping_voucher_discount bigint default 0,
  p_product_promo_code text default null,
  p_product_promo_discount bigint default 0
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
  v_phone text := coalesce(
    public.wa_digits(p_phone),
    nullif(trim(coalesce(p_phone, '')), '')
  );
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
  v_ship_disc bigint := 0;
  v_prod_disc bigint := 0;
  v_prod_disc_server bigint := 0;
  v_total bigint := 0;
  v_lines jsonb := '[]'::jsonb;
  v_id uuid;
  v_mid text;
  v_has_preorder boolean := false;
  v_promo_code text := nullif(upper(trim(coalesce(p_product_promo_code, ''))), '');
  v_promo public.member_promos%rowtype;
  v_dtype text;
  v_dval bigint;
  v_redeem jsonb;
  v_client_disc bigint := greatest(0, coalesce(p_product_promo_discount, 0));
begin
  if v_phone is null or v_phone = '' then
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
  -- Alamat wajib hanya untuk pengiriman; pickup cukup pilih cabang.
  if v_fulfill = 'delivery'
     and nullif(trim(coalesce(p_address_text, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Alamat pengiriman wajib diisi');
  end if;

  -- Diskon tanpa kode = ditolak (anti bypass redeem)
  if v_client_disc > 0 and v_promo_code is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Diskon produk wajib pakai kode voucher yang valid'
    );
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
    if v_courier is null or v_courier not in ('grab', 'gojek', 'other', 'obr') then
      return jsonb_build_object('ok', false, 'error', 'Pilih kurir');
    end if;

    if p_shipping_fee is not null then
      if p_shipping_fee < 0 or p_shipping_fee > 500000 then
        return jsonb_build_object('ok', false, 'error', 'Ongkir tidak valid');
      end if;
      v_ship := p_shipping_fee;
    else
      v_ship := case v_courier
        when 'grab' then coalesce(v_settings.fee_grab, 0)
        when 'gojek' then coalesce(v_settings.fee_gojek, 0)
        when 'obr' then greatest(
          0,
          least(
            coalesce(v_settings.fee_grab, 15000),
            coalesce(v_settings.fee_gojek, 15000),
            coalesce(v_settings.fee_other, 15000)
          ) - 2000
        )
        else coalesce(v_settings.fee_other, 0)
      end;
    end if;
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

  -- Voucher produk: hitung ulang di server (jangan percaya client)
  if v_promo_code is not null then
    select * into v_promo
    from public.member_promos
    where upper(trim(coalesce(voucher_code, ''))) = v_promo_code
      and active = true
      and coalesce(show_on_member, true) = true
    order by sort_order nulls last, created_at desc
    limit 1;

    if not found then
      return jsonb_build_object('ok', false, 'error', 'Voucher produk tidak valid untuk Member');
    end if;
    if v_promo.valid_until is not null and v_promo.valid_until < current_date then
      return jsonb_build_object('ok', false, 'error', 'Voucher produk kedaluwarsa');
    end if;
    if v_promo.quantity_remaining is not null and v_promo.quantity_remaining <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Kuota voucher produk habis');
    end if;

    v_dtype := lower(trim(coalesce(v_promo.discount_type, 'nominal')));
    v_dval := greatest(0, coalesce(v_promo.discount_value, 0));

    if v_dtype = 'info' then
      -- Info saja: tidak ada potongan & tidak redeem
      v_promo_code := null;
      v_prod_disc := 0;
    else
      if v_dtype = 'percent' then
        v_prod_disc_server := floor(v_subtotal * least(v_dval, 100) / 100.0)::bigint;
      else
        v_prod_disc_server := v_dval;
      end if;
      if v_prod_disc_server > v_subtotal then
        v_prod_disc_server := v_subtotal;
      end if;
      -- Anti cheat: nilai diskon selalu dari server (abaikan nominal client).
      v_prod_disc := v_prod_disc_server;
    end if;
  else
    v_prod_disc := 0;
  end if;

  if v_fulfill = 'delivery' then
    v_ship_disc := greatest(0, coalesce(p_shipping_voucher_discount, 0));
    if v_ship_disc > v_ship then
      v_ship_disc := v_ship;
    end if;
  else
    v_ship_disc := 0;
  end if;

  v_total := (v_subtotal - v_prod_disc) + (v_ship - v_ship_disc);
  if v_total < 0 then
    v_total := 0;
  end if;

  v_mid := 'OBR-ON-' || to_char(timezone('utc', now()), 'YYYYMMDDHH24MISS')
        || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.online_orders (
    member_id, phone_e164, customer_name, toko_id, fulfillment, courier,
    address_text, address_lat, address_lng, shipping_fee, items,
    subtotal, total, status, midtrans_order_id,
    store_note,
    courier_company, courier_service_code, courier_service_name,
    shipping_category, is_obr,
    shipping_voucher_discount, product_promo_code, product_promo_discount
  ) values (
    p_member_id, v_phone, nullif(trim(coalesce(p_customer_name, '')), ''),
    v_toko, v_fulfill, v_courier,
    nullif(trim(coalesce(p_address_text, '')), ''),
    p_address_lat, p_address_lng, v_ship, v_lines,
    v_subtotal, v_total, 'pending_payment', v_mid,
    case when v_has_preorder
      then 'Ada item pre-order → RO cabang saat lunas'
      else null
    end,
    nullif(trim(coalesce(p_courier_company, '')), ''),
    nullif(trim(coalesce(p_courier_service_code, '')), ''),
    nullif(trim(coalesce(p_courier_service_name, '')), ''),
    nullif(lower(trim(coalesce(p_shipping_category, ''))), ''),
    coalesce(p_is_obr, false),
    v_ship_disc,
    v_promo_code,
    v_prod_disc
  )
  returning id into v_id;

  -- Redeem wajib bila ada kode produk (bukan info)
  if v_promo_code is not null then
    v_redeem := public.redeem_member_promo(
      v_promo_code,
      null,                 -- sale_id
      v_phone,
      v_prod_disc,
      v_id,                 -- online_order_id
      'online'
    );
    if coalesce((v_redeem->>'ok')::boolean, false) is not true then
      raise exception '%', coalesce(v_redeem->>'error', 'Redeem voucher online gagal');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'online_order_id', v_id,
    'midtrans_order_id', v_mid,
    'subtotal', v_subtotal,
    'shipping_fee', v_ship,
    'shipping_voucher_discount', v_ship_disc,
    'product_promo_code', v_promo_code,
    'product_promo_discount', v_prod_disc,
    'total', v_total,
    'toko_id', v_toko,
    'items', v_lines,
    'has_preorder', v_has_preorder
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision,
  jsonb, bigint, text, text, text, text, boolean, bigint, text, bigint
) to anon, authenticated, service_role;


-- Backfill tracking lama
update public.sales
set tracking_status = 'DIPROSES_DI_CABANG'
where upper(trim(coalesce(channel, ''))) = 'MEMBER_ONLINE'
  and upper(trim(coalesce(tracking_status, ''))) = 'DIPROSES';

-- Normalisasi insert sales online ke label tracking baku
create or replace function public.trg_normalize_member_online_tracking()
returns trigger
language plpgsql
as $$
begin
  if upper(trim(coalesce(NEW.channel, ''))) = 'MEMBER_ONLINE'
     and upper(trim(coalesce(NEW.tracking_status, ''))) = 'DIPROSES' then
    NEW.tracking_status := 'DIPROSES_DI_CABANG';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_sales_normalize_member_online_tracking on public.sales;
create trigger trg_sales_normalize_member_online_tracking
  before insert or update of tracking_status, channel
  on public.sales
  for each row
  execute function public.trg_normalize_member_online_tracking();

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
begin
  if v_status not in ('packing', 'ready', 'shipped', 'fulfilled', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'Status tidak valid');
  end if;

  select toko_id, phone_e164, fulfillment
    into v_toko, v_phone, v_fulfill
  from public.online_orders
  where id = p_order_id;
  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ada');
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (
        lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
        or upper(trim(p.toko_id)) = upper(trim(v_toko))
      )
  ) into v_allowed;

  if not coalesce(v_allowed, false) then
    return jsonb_build_object('ok', false, 'error', 'Tidak berwenang');
  end if;

  update public.online_orders
  set
    status = v_status,
    courier_tracking = coalesce(nullif(trim(p_courier_tracking), ''), courier_tracking),
    store_note = coalesce(nullif(trim(p_store_note), ''), store_note),
    updated_at = now()
  where id = p_order_id
    and (
      (v_status = 'cancelled' and status in ('pending_payment', 'paid', 'packing', 'ready'))
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

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

grant execute on function public.update_online_order_fulfillment(uuid, text, text, text)
  to authenticated;

create or replace function public.list_member_online_orders(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := trim(coalesce(p_phone, ''));
begin
  if v_phone = '' then
    return '[]'::jsonb;
  end if;

  -- Soft-expire pending yang tertinggal
  update public.online_orders
  set status = 'expired', updated_at = now()
  where phone_e164 = v_phone
    and status = 'pending_payment'
    and created_at < now() - interval '24 hours';

  return coalesce((
    select jsonb_agg(to_jsonb(o) order by o.created_at desc)
    from (
      select *
      from public.online_orders
      where phone_e164 = v_phone
      order by created_at desc
      limit 40
    ) o
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_member_online_orders(text)
  to anon, authenticated;


-- list_member_sales: sertakan channel / online_order_id agar UI tidak dobel
create or replace function public.list_member_sales(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        s.id, s.no_invoice, s.toko_id, s.nama_pelanggan, s.status_pembayaran,
        s.tracking_status, s.diambil_at, s.foto_hasil_url, s.sisa_tagihan,
        s.total_harga, s.dibayarkan, s.created_at, s.lunas_at,
        s.channel, s.online_order_id, s.fulfillment, s.courier,
        (s.qr_dp_token is not null and length(trim(s.qr_dp_token)) >= 8) as has_qr_dp,
        (s.qr_lunas_token is not null and length(trim(s.qr_lunas_token)) >= 8) as has_qr_lunas,
        (s.qr_claim_token is not null and length(trim(s.qr_claim_token)) >= 8) as has_qr_claim
      from public.sales s
      where public.wa_digits(s.no_wa) = v_phone
         or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
      order by s.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_member_sales(text) to anon, authenticated;
