-- Seal voucher member_promos: POS + Belanja Online (anti kebocoran kuota/poin).
-- - redeem mendukung sale_id ATAU online_order_id
-- - lookup per channel (pos / online)
-- - create_online_order: hitung diskon server-side + redeem wajib

-- 1) Redemptions: boleh mengacu ke online_orders
alter table public.member_promo_redemptions
  alter column sale_id drop not null;

alter table public.member_promo_redemptions
  add column if not exists online_order_id uuid references public.online_orders(id) on delete cascade,
  add column if not exists channel text not null default 'pos';

alter table public.member_promo_redemptions
  drop constraint if exists member_promo_redemptions_sale_uidx;

drop index if exists member_promo_redemptions_sale_uidx;

create unique index if not exists member_promo_redemptions_sale_uidx
  on public.member_promo_redemptions (sale_id)
  where sale_id is not null;

create unique index if not exists member_promo_redemptions_online_uidx
  on public.member_promo_redemptions (online_order_id)
  where online_order_id is not null;

alter table public.member_promo_redemptions
  drop constraint if exists member_promo_redemptions_ref_check;

alter table public.member_promo_redemptions
  add constraint member_promo_redemptions_ref_check
  check (
    (sale_id is not null and online_order_id is null)
    or (sale_id is null and online_order_id is not null)
  );

-- 2) Lookup per channel
drop function if exists public.lookup_member_promo(text);
drop function if exists public.lookup_member_promo(text, text);

create or replace function public.lookup_member_promo(
  p_code text,
  p_channel text default 'pos'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.member_promos%rowtype;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_ch text := lower(trim(coalesce(p_channel, 'pos')));
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode kosong');
  end if;
  if v_ch not in ('pos', 'online', 'member', 'any') then
    v_ch := 'pos';
  end if;

  select * into v_row
  from public.member_promos
  where upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and (
      (v_ch = 'pos' and coalesce(show_on_pos, true) = true)
      or (v_ch in ('online', 'member') and coalesce(show_on_member, true) = true)
      or (
        v_ch = 'any'
        and (coalesce(show_on_pos, true) = true or coalesce(show_on_member, true) = true)
      )
    )
  order by sort_order nulls last, created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error',
      case
        when v_ch in ('online', 'member')
          then 'Voucher tidak ditemukan / tidak aktif di Member'
        else 'Voucher tidak ditemukan / tidak aktif di POS'
      end
    );
  end if;

  if v_row.valid_until is not null and v_row.valid_until < current_date then
    return jsonb_build_object('ok', false, 'error', 'Voucher kedaluwarsa');
  end if;

  if v_row.quantity_remaining is not null and v_row.quantity_remaining <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Kuota voucher habis');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'title', v_row.title,
    'description', v_row.description,
    'voucher_code', v_row.voucher_code,
    'discount_type', v_row.discount_type,
    'discount_value', v_row.discount_value,
    'quantity_remaining', v_row.quantity_remaining,
    'points_cost', v_row.points_cost,
    'terms', v_row.terms,
    'channel', v_ch
  );
end;
$$;

grant execute on function public.lookup_member_promo(text, text)
  to anon, authenticated, service_role;

-- 3) Redeem POS / Online
drop function if exists public.redeem_member_promo(text, uuid, text, bigint);
drop function if exists public.redeem_member_promo(text, uuid, text, bigint, uuid, text);

create or replace function public.redeem_member_promo(
  p_code text,
  p_sale_id uuid default null,
  p_phone text default null,
  p_discount_applied bigint default 0,
  p_online_order_id uuid default null,
  p_channel text default 'pos'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_row public.member_promos%rowtype;
  v_sale public.sales%rowtype;
  v_online public.online_orders%rowtype;
  v_member_id uuid;
  v_digits text;
  v_alt text;
  v_phone text := trim(coalesce(p_phone, ''));
  v_balance int := 0;
  v_points int := 0;
  v_disc bigint := greatest(0, coalesce(p_discount_applied, 0));
  v_updated int := 0;
  v_existing uuid;
  v_ch text := lower(trim(coalesce(p_channel, 'pos')));
  v_ref_label text;
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode voucher kosong');
  end if;

  if (p_sale_id is null and p_online_order_id is null)
     or (p_sale_id is not null and p_online_order_id is not null) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Harus ada tepat satu: sale_id atau online_order_id'
    );
  end if;

  if v_ch not in ('pos', 'online', 'member', 'any') then
    v_ch := case when p_online_order_id is not null then 'online' else 'pos' end;
  end if;

  if p_sale_id is not null then
    select * into v_sale from public.sales where id = p_sale_id limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Nota penjualan tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_sale.no_invoice, p_sale_id::text);
    select id into v_existing
    from public.member_promo_redemptions
    where sale_id = p_sale_id
    limit 1;
  else
    select * into v_online from public.online_orders where id = p_online_order_id limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Pesanan online tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_online.midtrans_order_id, p_online_order_id::text);
    select id into v_existing
    from public.member_promo_redemptions
    where online_order_id = p_online_order_id
    limit 1;
  end if;

  if v_existing is not null then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_redeemed',
      'redemption_id', v_existing
    );
  end if;

  select * into v_row
  from public.member_promos
  where upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and (
      (v_ch = 'pos' and coalesce(show_on_pos, true) = true)
      or (v_ch in ('online', 'member') and coalesce(show_on_member, true) = true)
      or (
        v_ch = 'any'
        and (coalesce(show_on_pos, true) = true or coalesce(show_on_member, true) = true)
      )
    )
  order by sort_order nulls last, created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Voucher tidak ditemukan / tidak aktif');
  end if;

  if v_row.valid_until is not null and v_row.valid_until < current_date then
    return jsonb_build_object('ok', false, 'error', 'Voucher kedaluwarsa');
  end if;

  if lower(trim(coalesce(v_row.discount_type, 'nominal'))) = 'info' then
    return jsonb_build_object('ok', false, 'error', 'Voucher info tidak bisa di-redeem');
  end if;

  v_points := greatest(0, coalesce(v_row.points_cost, 0));

  if v_phone = '' then
    if p_sale_id is not null then
      v_phone := coalesce(v_sale.no_wa, '');
    else
      v_phone := coalesce(v_online.phone_e164, '');
    end if;
  end if;

  v_digits := public.wa_digits(v_phone);
  if v_digits is not null and length(v_digits) >= 8 then
    v_alt := case
      when v_digits like '62%' then '0' || substr(v_digits, 3)
      when v_digits like '0%' then '62' || substr(v_digits, 2)
      else v_digits
    end;
    select m.id into v_member_id
    from public.members m
    where public.wa_digits(m.phone_e164) in (v_digits, v_alt)
       or regexp_replace(coalesce(m.phone_e164, ''), '\D', '', 'g') in (v_digits, v_alt)
       or regexp_replace(coalesce(m.phone_raw, ''), '\D', '', 'g') in (v_digits, v_alt)
    order by m.created_at
    limit 1;
  end if;

  if v_points > 0 then
    if v_member_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'Voucher butuh ' || v_points || ' poin — nomor WA harus terdaftar member'
      );
    end if;
    select coalesce(sum(delta), 0)::int into v_balance
    from public.member_points_ledger
    where member_id = v_member_id;
    if v_balance < v_points then
      return jsonb_build_object(
        'ok', false,
        'error',
        'Poin member tidak cukup (saldo ' || v_balance || ', butuh ' || v_points || ')'
      );
    end if;
  end if;

  if v_row.quantity_remaining is not null then
    update public.member_promos
    set quantity_remaining = quantity_remaining - 1
    where id = v_row.id
      and quantity_remaining is not null
      and quantity_remaining > 0;
    get diagnostics v_updated = row_count;
    if v_updated = 0 then
      return jsonb_build_object('ok', false, 'error', 'Kuota voucher habis');
    end if;
  end if;

  if v_points > 0 and v_member_id is not null then
    insert into public.member_points_ledger (
      member_id, delta, reason, sale_id, meta
    ) values (
      v_member_id,
      -v_points,
      'voucher_redeem',
      p_sale_id,
      jsonb_build_object(
        'voucher_code', v_code,
        'promo_id', v_row.id,
        'ref', v_ref_label,
        'channel', v_ch,
        'online_order_id', p_online_order_id,
        'discount_applied', v_disc
      )
    );
  end if;

  insert into public.member_promo_redemptions (
    promo_id, sale_id, online_order_id, voucher_code,
    discount_applied, points_spent, member_id, channel
  ) values (
    v_row.id, p_sale_id, p_online_order_id, v_code,
    v_disc, v_points, v_member_id, v_ch
  );

  if p_sale_id is not null then
    update public.sales
    set
      voucher_code = v_code,
      voucher_discount = case
        when coalesce(voucher_discount, 0) > 0 then voucher_discount
        else v_disc
      end
    where id = p_sale_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'promo_id', v_row.id,
    'voucher_code', v_code,
    'points_spent', v_points,
    'member_id', v_member_id,
    'channel', v_ch,
    'quantity_remaining', (
      select quantity_remaining from public.member_promos where id = v_row.id
    )
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_redeemed_race'
    );
end;
$$;

grant execute on function public.redeem_member_promo(text, uuid, text, bigint, uuid, text)
  to authenticated, service_role, anon;

-- 4) create_online_order: diskon server-side + redeem wajib
drop function if exists public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision,
  jsonb, bigint, text, text, text, text, boolean, bigint, text, bigint
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
