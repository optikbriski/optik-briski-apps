-- Meta kurir Biteship + izinkan courier 'obr' di online_orders.

alter table public.online_orders
  add column if not exists courier_company text,
  add column if not exists courier_service_code text,
  add column if not exists courier_service_name text,
  add column if not exists shipping_category text,
  add column if not exists biteship_order_id text,
  add column if not exists biteship_waybill text,
  add column if not exists is_obr boolean not null default false;

alter table public.online_orders drop constraint if exists online_orders_courier_check;
alter table public.online_orders
  add constraint online_orders_courier_check
  check (courier is null or courier in ('grab', 'gojek', 'other', 'obr'));

drop function if exists public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision, jsonb
);
drop function if exists public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision, jsonb, bigint
);

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
  p_is_obr boolean default false
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

  v_mid := 'OBR-ON-' || to_char(timezone('utc', now()), 'YYYYMMDDHH24MISS')
        || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.online_orders (
    member_id, phone_e164, customer_name, toko_id, fulfillment, courier,
    address_text, address_lat, address_lng, shipping_fee, items,
    subtotal, total, status, midtrans_order_id,
    store_note,
    courier_company, courier_service_code, courier_service_name,
    shipping_category, is_obr
  ) values (
    p_member_id, v_phone, nullif(trim(coalesce(p_customer_name, '')), ''),
    v_toko, v_fulfill, v_courier,
    nullif(trim(coalesce(p_address_text, '')), ''),
    p_address_lat, p_address_lng, v_ship, v_lines,
    v_subtotal, v_subtotal + v_ship, 'pending_payment', v_mid,
    case when v_has_preorder
      then 'Ada item pre-order → RO cabang saat lunas'
      else null
    end,
    nullif(trim(coalesce(p_courier_company, '')), ''),
    nullif(trim(coalesce(p_courier_service_code, '')), ''),
    nullif(trim(coalesce(p_courier_service_name, '')), ''),
    nullif(lower(trim(coalesce(p_shipping_category, ''))), ''),
    coalesce(p_is_obr, false)
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
  text, uuid, text, text, text, text, text, double precision, double precision,
  jsonb, bigint, text, text, text, text, boolean
) to anon, authenticated, service_role;

create or replace function public.attach_biteship_shipment(
  p_order_id uuid,
  p_biteship_order_id text,
  p_waybill text default null,
  p_tracking text default null,
  p_mark_shipped boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text;
  v_allowed boolean;
begin
  select toko_id into v_toko from public.online_orders where id = p_order_id;
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
    biteship_order_id = nullif(trim(coalesce(p_biteship_order_id, '')), ''),
    biteship_waybill = coalesce(
      nullif(trim(coalesce(p_waybill, '')), ''),
      biteship_waybill
    ),
    courier_tracking = coalesce(
      nullif(trim(coalesce(p_tracking, p_waybill, '')), ''),
      courier_tracking
    ),
    status = case
      when p_mark_shipped and status in ('paid', 'packing', 'ready', 'shipped')
        then 'shipped'
      else status
    end,
    updated_at = now()
  where id = p_order_id;

  if p_mark_shipped then
    update public.sales s
    set tracking_status = 'DIKIRIM'
    from public.online_orders o
    where o.id = p_order_id
      and s.id = o.sale_id;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.attach_biteship_shipment(uuid, text, text, text, boolean)
  to authenticated, service_role;
