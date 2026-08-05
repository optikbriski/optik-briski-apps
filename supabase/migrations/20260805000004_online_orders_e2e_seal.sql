-- Seal E2E Belanja Online (setelah 000003):
-- 1) expire pending global + kembalikan kuota/poin voucher
-- 2) grant alert ke service_role (Edge Biteship)
-- 3) create_online_order: ongkir wajib + validasi voucher ongkir OBR

-- ---------------------------------------------------------------------------
-- 1) Lepas redeem voucher bila order pending dibatalkan / expired
-- ---------------------------------------------------------------------------
create or replace function public.release_online_order_promo(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  if p_order_id is null then
    return;
  end if;

  for r in
    select promo_id, points_spent, member_id, voucher_code
    from public.member_promo_redemptions
    where online_order_id = p_order_id
  loop
    if r.promo_id is not null then
      update public.member_promos
      set quantity_remaining = quantity_remaining + 1
      where id = r.promo_id
        and quantity_remaining is not null;
    end if;

    if coalesce(r.points_spent, 0) > 0 and r.member_id is not null then
      insert into public.member_points_ledger (
        member_id, delta, reason, sale_id, meta
      ) values (
        r.member_id,
        r.points_spent,
        'voucher_release_online',
        null,
        jsonb_build_object(
          'online_order_id', p_order_id,
          'voucher_code', r.voucher_code,
          'promo_id', r.promo_id
        )
      );
    end if;
  end loop;

  delete from public.member_promo_redemptions
  where online_order_id = p_order_id;
end;
$$;

create or replace function public.trg_online_orders_release_promo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE'
     and OLD.status = 'pending_payment'
     and NEW.status in ('expired', 'cancelled') then
    perform public.release_online_order_promo(NEW.id);
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_online_orders_release_promo on public.online_orders;
create trigger trg_online_orders_release_promo
  after update of status on public.online_orders
  for each row
  execute function public.trg_online_orders_release_promo();

-- ---------------------------------------------------------------------------
-- 2) Soft-expire semua pending > 24 jam (global)
-- ---------------------------------------------------------------------------
create or replace function public.expire_stale_online_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n int := 0;
begin
  update public.online_orders
  set status = 'expired', updated_at = now()
  where status = 'pending_payment'
    and created_at < now() - interval '24 hours';
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.expire_stale_online_orders()
  to anon, authenticated, service_role;

-- Member list: expire global dulu
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
  perform public.expire_stale_online_orders();

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
-- 3) Alert dari Edge (service_role)
-- ---------------------------------------------------------------------------
grant execute on function public.create_member_order_alert(text, text, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4) Helper: max diskon voucher ongkir OBR (parity Dart)
-- ---------------------------------------------------------------------------
create or replace function public.obr_shipping_voucher_max(
  p_subtotal bigint,
  p_category text
)
returns bigint
language plpgsql
immutable
as $$
declare
  v_cat text := lower(trim(coalesce(p_category, '')));
  v_sub bigint := greatest(0, coalesce(p_subtotal, 0));
  v_max bigint := 0;
begin
  if v_cat in ('same_day') then v_cat := 'sameday'; end if;
  if v_cat in ('next_day') then v_cat := 'nextday'; end if;

  if v_sub >= 1000000 then
    if v_cat in ('instant', 'sameday', 'nextday') then
      v_max := 30000;
    end if;
  elsif v_sub >= 600000 then
    if v_cat in ('sameday', 'nextday') then
      v_max := 16000;
    end if;
  elsif v_sub >= 400000 then
    if v_cat in ('sameday', 'nextday') then
      v_max := 8000;
    end if;
  elsif v_sub >= 150000 then
    if v_cat = 'nextday' then
      v_max := 6000;
    end if;
  else
    if v_cat = 'nextday' then
      v_max := 2000;
    end if;
  end if;

  return v_max;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) create_online_order: ongkir wajib + voucher ongkir OBR tervalidasi
-- ---------------------------------------------------------------------------

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
  v_ship_cat text;
  v_origin_lat double precision;
  v_origin_lng double precision;
  v_dist_m double precision;
  v_obr_max_m double precision;
  v_goods bigint;
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
    -- Biteship selalu boleh selama toko jual online (abaikan delivery_enabled).
    if v_courier is null or v_courier not in ('grab', 'gojek', 'other', 'obr') then
      return jsonb_build_object('ok', false, 'error', 'Pilih kurir');
    end if;
    -- OBR hanya bila toggle kategori cabang aktif.
    if coalesce(p_is_obr, false) or v_courier = 'obr' then
      v_ship_cat := lower(trim(coalesce(p_shipping_category, '')));
      if v_ship_cat in ('same_day') then v_ship_cat := 'sameday'; end if;
      if v_ship_cat in ('next_day') then v_ship_cat := 'nextday'; end if;
      if v_ship_cat = 'instant' and not coalesce(v_settings.obr_instant_enabled, true) then
        return jsonb_build_object('ok', false, 'error', 'OBR Instant tidak aktif di cabang ini');
      elsif v_ship_cat = 'sameday' and not coalesce(v_settings.obr_sameday_enabled, true) then
        return jsonb_build_object('ok', false, 'error', 'OBR Same Day tidak aktif di cabang ini');
      elsif v_ship_cat = 'nextday' and not coalesce(v_settings.obr_nextday_enabled, true) then
        return jsonb_build_object('ok', false, 'error', 'OBR Next Day tidak aktif di cabang ini');
      elsif v_ship_cat not in ('instant', 'sameday', 'nextday') then
        return jsonb_build_object('ok', false, 'error', 'Kategori OBR tidak valid');
      end if;
    end if;

    -- Ongkir wajib dari quote Member (Biteship/OBR). Jangan terima null.
    if p_shipping_fee is null then
      return jsonb_build_object('ok', false, 'error', 'Ongkir wajib dari pilihan kurir');
    end if;
    if p_shipping_fee < 0 or p_shipping_fee > 500000 then
      return jsonb_build_object('ok', false, 'error', 'Ongkir tidak valid');
    end if;
    v_ship := p_shipping_fee;
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
    if v_ship_disc > 0 then
      if not (coalesce(p_is_obr, false) or v_courier = 'obr') then
        return jsonb_build_object('ok', false, 'error', 'Voucher ongkir hanya untuk OBR Delivery');
      end if;
      v_ship_cat := lower(trim(coalesce(p_shipping_category, '')));
      if v_ship_cat in ('same_day') then v_ship_cat := 'sameday'; end if;
      if v_ship_cat in ('next_day') then v_ship_cat := 'nextday'; end if;
      v_ship_disc := least(
        v_ship_disc,
        v_ship,
        public.obr_shipping_voucher_max(v_subtotal, v_ship_cat)
      );
      if v_ship_disc <= 0 and coalesce(p_shipping_voucher_discount, 0) > 0 then
        return jsonb_build_object(
          'ok', false,
          'error', 'Voucher ongkir tidak berlaku untuk kategori/subtotal ini'
        );
      end if;
    end if;
  else
    v_ship_disc := 0;
  end if;

  -- OBR: jangkauan server-side (≤10 km; ≤15 km bila belanja > 1jt)
  if v_fulfill = 'delivery' and (coalesce(p_is_obr, false) or v_courier = 'obr') then
    if p_address_lat is null or p_address_lng is null then
      return jsonb_build_object('ok', false, 'error', 'Koordinat alamat wajib untuk OBR');
    end if;
    select t.latitude, t.longitude
      into v_origin_lat, v_origin_lng
    from public.toko_id t
    where upper(trim(t.id)) = v_toko
    limit 1;
    if v_origin_lat is null or v_origin_lng is null
       or (v_origin_lat = 0 and v_origin_lng = 0) then
      return jsonb_build_object('ok', false, 'error', 'Koordinat cabang belum ada untuk OBR');
    end if;
    v_dist_m := public.haversine_meters(
      v_origin_lat, v_origin_lng, p_address_lat, p_address_lng
    );
    v_goods := greatest(0, v_subtotal - coalesce(v_prod_disc, 0));
    v_obr_max_m := case when v_goods > 1000000 then 15000.0 else 10000.0 end;
    if v_dist_m is null or v_dist_m > (v_obr_max_m + 0.5) then
      return jsonb_build_object(
        'ok', false,
        'error',
        'OBR di luar jangkauan ('
          || to_char(round((coalesce(v_dist_m, 0) / 1000.0)::numeric, 1), 'FM999990.0')
          || ' km). Pilih kurir Biteship.'
      );
    end if;
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

