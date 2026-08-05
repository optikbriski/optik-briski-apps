-- Hold stok 15 menit saat pending pembayaran (Member Belanja Online).
-- stock_qty di-booking (ONLINE_HOLD) → available_qty turun untuk Member lain.
-- Lewat expires_at → expired + hold dilepas; lunas → hold dilepas lalu SALE.

-- ---------------------------------------------------------------------------
-- 1) Schema: expires_at + kind ONLINE_HOLD
-- ---------------------------------------------------------------------------
alter table public.online_orders
  add column if not exists expires_at timestamptz;

comment on column public.online_orders.expires_at is
  'Batas bayar (default created_at + 15 menit). Lewat → expire + lepas hold stok.';

update public.online_orders
set expires_at = created_at + interval '15 minutes'
where expires_at is null
  and status = 'pending_payment';

alter table public.stock_reservations
  drop constraint if exists stock_reservations_kind_check;

alter table public.stock_reservations
  add constraint stock_reservations_kind_check
  check (kind in ('DO_DRAFT', 'DO_PREPARING', 'RO', 'POS_HOLD', 'ONLINE_HOLD'));

create or replace function public.reserve_stock(
  p_toko text,
  p_sku text,
  p_qty integer,
  p_kind text,
  p_ref_type text,
  p_ref_id text,
  p_meta jsonb default '{}'::jsonb
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
  v_available integer;
  v_res public.stock_reservations;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'qty reservasi harus > 0';
  end if;
  if p_kind not in ('DO_DRAFT', 'DO_PREPARING', 'RO', 'POS_HOLD', 'ONLINE_HOLD') then
    raise exception 'kind tidak valid: %', p_kind;
  end if;

  select * into v_row
  from public.products
  where upper(trim(sku)) = upper(trim(v_sku))
    and upper(trim(toko_id)) = v_toko
  for update;

  if not found then
    raise exception 'Produk % tidak ada di %', v_sku, v_toko;
  end if;

  update public.stock_reservations
  set status = 'released', updated_at = now()
  where status = 'active'
    and kind = p_kind
    and ref_type = p_ref_type
    and ref_id = p_ref_id
    and upper(trim(sku)) = upper(trim(v_sku))
    and upper(trim(toko_id)) = v_toko;

  perform public.recompute_product_reserved_qty(v_toko, v_sku);

  select * into v_row
  from public.products
  where id = v_row.id
  for update;

  v_available := public.product_available_qty(v_row.stock, v_row.reserved_qty);
  if v_available < p_qty then
    raise exception
      'Stok tersedia tidak cukup di % untuk SKU % (real %, pending %, tersedia %, minta %)',
      v_toko, v_sku, v_row.stock, v_row.reserved_qty, v_available, p_qty;
  end if;

  insert into public.stock_reservations (
    sku, toko_id, qty, kind, ref_type, ref_id, status, meta
  ) values (
    v_row.sku, v_toko, p_qty, p_kind, p_ref_type, p_ref_id, 'active',
    coalesce(p_meta, '{}'::jsonb)
  )
  returning * into v_res;

  perform public.recompute_product_reserved_qty(v_toko, v_sku);

  select stock, reserved_qty into v_row.stock, v_row.reserved_qty
  from public.products where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'reservation_id', v_res.id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'qty', p_qty,
    'real_stock', v_row.stock,
    'pending_stock', v_row.reserved_qty,
    'available_qty', public.product_available_qty(v_row.stock, v_row.reserved_qty)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Lepas ONLINE_HOLD saat expire / cancel (dan safety saat paid)
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
     and NEW.status in ('expired', 'cancelled', 'paid', 'packing', 'ready', 'shipped', 'fulfilled') then
    perform public.release_reservation(
      'ONLINE_HOLD',
      'online_order',
      NEW.id::text
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_online_orders_release_stock_hold on public.online_orders;
create trigger trg_online_orders_release_stock_hold
  after update of status on public.online_orders
  for each row
  execute function public.trg_online_orders_release_stock_hold();

-- ---------------------------------------------------------------------------
-- 3) Soft-expire pending lewat expires_at (15 menit)
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
    and coalesce(expires_at, created_at + interval '15 minutes') < now();
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.expire_stale_online_orders()
  to anon, authenticated, service_role;

comment on function public.expire_stale_online_orders() is
  'Expire pending_payment yang lewat expires_at (15 menit). Trigger melepaskan ONLINE_HOLD.';

-- get detail Member: expire dulu agar countdown/status akurat
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
  perform public.expire_stale_online_orders();

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

-- ---------------------------------------------------------------------------
-- 4) create_online_order: set expires_at + hold stock_qty
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
    shipping_voucher_discount, product_promo_code, product_promo_discount,
    expires_at
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
    v_prod_disc,
    now() + interval '15 minutes'
  )
  returning id into v_id;

  -- Hold stok (stock_qty) → reserved_qty; Member lain lihat sisa available
  for v_item in select * from jsonb_array_elements(v_lines)
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_stock_qty := greatest(0, coalesce((v_item->>'stock_qty')::int, 0));
    if v_sku = '' or v_stock_qty <= 0 then
      continue;
    end if;
    begin
      perform public.reserve_stock(
        v_toko,
        v_sku,
        v_stock_qty,
        'ONLINE_HOLD',
        'online_order',
        v_id::text,
        jsonb_build_object(
          'midtrans_order_id', v_mid,
          'channel', 'member_online',
          'hold_minutes', 15
        )
      );
    exception when others then
      raise exception 'Gagal hold stok % ×%: %', v_sku, v_stock_qty, SQLERRM;
    end;
  end loop;

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
    'has_preorder', v_has_preorder,
    'expires_at', (select o.expires_at from public.online_orders o where o.id = v_id),
    'hold_minutes', 15
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

-- ---------------------------------------------------------------------------
-- 5) fulfill: lepas hold sebelum SALE; tolak bila lewat 15 menit
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

  if v_order.status = 'pending_payment'
     and coalesce(v_order.expires_at, v_order.created_at + interval '15 minutes') < now() then
    update public.online_orders
    set status = 'expired', updated_at = now()
    where id = v_order.id and status = 'pending_payment';
    return jsonb_build_object(
      'ok', false,
      'error',
      'Batas waktu bayar 15 menit habis — stok dikembalikan. Buat pesanan baru.'
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

  -- Lepas hold stok dulu, lalu SALE mengurangi stok riil
  perform public.release_reservation(
    'ONLINE_HOLD',
    'online_order',
    v_order.id::text
  );

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
  to service_role;

comment on function public.fulfill_online_order_payment(text, text, bigint) is
  'Lunas Midtrans: lepas ONLINE_HOLD lalu SALE/RO/finance; idempotent per online_order_id.';
