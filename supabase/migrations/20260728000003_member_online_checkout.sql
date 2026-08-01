-- =============================================================================
-- Member online checkout: pickup/delivery + Midtrans staging → sales/finance
-- Aman dijalankan meski migration member_app_features belum pernah di-run.
-- =============================================================================

create extension if not exists pgcrypto;

-- 0) Prasyarat: tabel members (dari 20260727000002) bila belum ada
create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null unique,
  phone_raw text,
  nama text,
  email text,
  alamat text,
  font_scale numeric not null default 1.0,
  locale text not null default 'id',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.members enable row level security;

-- 1) Pengaturan ongkir / jual online per cabang
create table if not exists public.toko_delivery_settings (
  toko_id text primary key references public.toko_id (id) on delete cascade,
  online_selling_enabled boolean not null default true,
  pickup_enabled boolean not null default true,
  delivery_enabled boolean not null default true,
  fee_grab bigint not null default 15000,
  fee_gojek bigint not null default 15000,
  fee_other bigint not null default 20000,
  updated_at timestamptz not null default now()
);

comment on table public.toko_delivery_settings is
  'Ongkir flat v1 + flag jual online per cabang untuk APK Member.';

insert into public.toko_delivery_settings (toko_id)
select t.id from public.toko_id t
on conflict (toko_id) do nothing;

alter table public.toko_delivery_settings enable row level security;

drop policy if exists toko_delivery_settings_read on public.toko_delivery_settings;
create policy toko_delivery_settings_read on public.toko_delivery_settings
  for select to anon, authenticated
  using (true);

drop policy if exists toko_delivery_settings_write on public.toko_delivery_settings;
create policy toko_delivery_settings_write on public.toko_delivery_settings
  for all to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(toko_delivery_settings.toko_id))
        )
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(toko_delivery_settings.toko_id))
        )
    )
  );

-- 2) Staging order sebelum / sesudah Midtrans
create table if not exists public.online_orders (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.members (id) on delete set null,
  phone_e164 text not null,
  customer_name text,
  toko_id text not null references public.toko_id (id),
  fulfillment text not null check (fulfillment in ('pickup', 'delivery')),
  courier text check (courier is null or courier in ('grab', 'gojek', 'other')),
  address_text text,
  address_lat double precision,
  address_lng double precision,
  shipping_fee bigint not null default 0,
  items jsonb not null default '[]'::jsonb,
  subtotal bigint not null default 0,
  total bigint not null default 0,
  status text not null default 'pending_payment'
    check (status in (
      'pending_payment', 'paid', 'expired', 'cancelled',
      'packing', 'ready', 'shipped', 'fulfilled'
    )),
  midtrans_order_id text unique,
  midtrans_snap_token text,
  midtrans_redirect_url text,
  payment_method text,
  sale_id uuid references public.sales (id) on delete set null,
  courier_tracking text,
  store_note text,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists online_orders_toko_status_idx
  on public.online_orders (toko_id, status, created_at desc);
create index if not exists online_orders_phone_idx
  on public.online_orders (phone_e164, created_at desc);
create index if not exists online_orders_member_idx
  on public.online_orders (member_id, created_at desc);

alter table public.online_orders enable row level security;

drop policy if exists online_orders_read_staff on public.online_orders;
create policy online_orders_read_staff on public.online_orders
  for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(online_orders.toko_id))
        )
    )
  );

drop policy if exists online_orders_write_staff on public.online_orders;
create policy online_orders_write_staff on public.online_orders
  for update to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(online_orders.toko_id))
        )
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(online_orders.toko_id))
        )
    )
  );

-- Insert/select via RPC / service role (Edge). Anon tidak insert langsung.
drop policy if exists online_orders_read_anon_none on public.online_orders;

-- 3) Kolom channel di sales
alter table public.sales
  add column if not exists channel text not null default 'pos',
  add column if not exists online_order_id uuid references public.online_orders (id) on delete set null,
  add column if not exists fulfillment text,
  add column if not exists courier text;

create index if not exists sales_channel_toko_idx
  on public.sales (channel, toko_id, created_at desc);

-- 4) Stok tersedia di cabang untuk SKU katalog PUSAT
create or replace function public.list_branch_sellable(
  p_toko_id text,
  p_skus text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
begin
  if v_toko = '' then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.sku)
    from (
      select
        pp.sku,
        pp.id as pusat_product_id,
        pb.id as branch_product_id,
        coalesce(nullif(trim(pb.nama), ''), pp.nama) as nama,
        pp.kategori,
        coalesce(pb.harga_jual, pb.harga, pp.harga_jual, pp.harga, 0)::bigint as harga,
        greatest(
          0,
          coalesce(pb.stock, 0) - coalesce(pb.reserved_qty, 0)
        )::int as available_qty,
        coalesce(nullif(trim(pp.image_url), ''), nullif(trim(pp.foto_url), '')) as image_url
      from public.products pp
      left join public.products pb
        on upper(trim(pb.toko_id)) = v_toko
       and upper(trim(pb.sku)) = upper(trim(pp.sku))
      where upper(trim(pp.toko_id)) = 'PUSAT'
        and nullif(trim(pp.sku), '') is not null
        and (
          p_skus is null
          or upper(trim(pp.sku)) = any (
            select upper(trim(s)) from unnest(p_skus) s
          )
        )
    ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_branch_sellable(text, text[]) to anon, authenticated;

-- 5) Quote ongkir flat
create or replace function public.quote_online_delivery(
  p_toko_id text,
  p_courier text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_courier text := lower(trim(coalesce(p_courier, '')));
  v_row public.toko_delivery_settings%rowtype;
  v_fee bigint := 0;
begin
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'Cabang wajib dipilih');
  end if;

  select * into v_row from public.toko_delivery_settings where toko_id = v_toko;
  if not found then
    insert into public.toko_delivery_settings (toko_id) values (v_toko)
    returning * into v_row;
  end if;

  if not coalesce(v_row.online_selling_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang belum aktif jual online');
  end if;
  if not coalesce(v_row.delivery_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang tidak menerima pengiriman');
  end if;

  v_fee := case v_courier
    when 'grab' then coalesce(v_row.fee_grab, 0)
    when 'gojek' then coalesce(v_row.fee_gojek, 0)
    when 'other' then coalesce(v_row.fee_other, 0)
    else -1
  end;

  if v_fee < 0 then
    return jsonb_build_object('ok', false, 'error', 'Kurir tidak valid');
  end if;

  return jsonb_build_object(
    'ok', true,
    'toko_id', v_toko,
    'courier', v_courier,
    'shipping_fee', v_fee,
    'pickup_enabled', v_row.pickup_enabled,
    'delivery_enabled', v_row.delivery_enabled
  );
end;
$$;

grant execute on function public.quote_online_delivery(text, text) to anon, authenticated;

-- 6) Validasi + buat online_orders (dipanggil Edge / client sebelum Snap)
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
  v_subtotal bigint := 0;
  v_ship bigint := 0;
  v_lines jsonb := '[]'::jsonb;
  v_id uuid;
  v_mid text;
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
    if nullif(trim(coalesce(p_address_text, '')), '') is null then
      return jsonb_build_object('ok', false, 'error', 'Alamat pengiriman wajib');
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

    select pp.kategori into v_kat
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

    if v_sell is null then
      return jsonb_build_object('ok', false, 'error', 'Produk tidak tersedia di cabang: ' || v_sku);
    end if;

    v_avail := coalesce((v_sell->>'available_qty')::int, 0);
    v_harga := coalesce((v_sell->>'harga')::bigint, 0);
    v_nama := coalesce(v_sell->>'nama', v_sku);
    v_branch_pid := nullif(v_sell->>'branch_product_id', '')::uuid;

    if v_avail < v_qty then
      return jsonb_build_object(
        'ok', false,
        'error',
        format('Stok %s di cabang kurang (tersedia %s)', v_nama, v_avail)
      );
    end if;
    if v_harga <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Harga tidak valid: ' || v_nama);
    end if;

    v_subtotal := v_subtotal + (v_harga * v_qty);
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'sku', v_sku,
      'qty', v_qty,
      'harga', v_harga,
      'nama', v_nama,
      'kategori', v_kat,
      'subtotal', v_harga * v_qty,
      'branch_product_id', v_branch_pid,
      'pusat_product_id', nullif(v_sell->>'pusat_product_id', '')::uuid,
      'image_url', v_sell->>'image_url'
    ));
  end loop;

  v_mid := 'OBR-ON-' || to_char(timezone('utc', now()), 'YYYYMMDDHH24MISS')
        || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.online_orders (
    member_id, phone_e164, customer_name, toko_id, fulfillment, courier,
    address_text, address_lat, address_lng, shipping_fee, items,
    subtotal, total, status, midtrans_order_id
  ) values (
    p_member_id, v_phone, nullif(trim(coalesce(p_customer_name, '')), ''),
    v_toko, v_fulfill, v_courier,
    nullif(trim(coalesce(p_address_text, '')), ''),
    p_address_lat, p_address_lng, v_ship, v_lines,
    v_subtotal, v_subtotal + v_ship, 'pending_payment', v_mid
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
    'items', v_lines
  );
end;
$$;

grant execute on function public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision, jsonb
) to anon, authenticated;

-- 7) Finalize setelah Midtrans settlement (service role / Edge / admin simulate)
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
  v_pid uuid;
  v_stock_res jsonb;
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

    begin
      v_stock_res := public.apply_stock_delta(
        v_order.toko_id,
        v_sku,
        -v_qty,
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
      -- jangan gagalkan lunas jika stok ledger gagal; log di store_note
      update public.online_orders
      set store_note = coalesce(store_note || E'\n', '') ||
        ('Stok gagal: ' || v_sku || ' — ' || SQLERRM),
          updated_at = now()
      where id = v_order.id;
    end;
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
      'Online Member %s (%s) %s',
      v_invoice,
      coalesce(v_order.customer_name, v_order.phone_e164),
      case when v_order.fulfillment = 'delivery'
        then 'kirim ' || coalesce(v_order.courier, '')
        else 'pickup'
      end
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
    updated_at = now()
  where id = v_order.id;

  return jsonb_build_object(
    'ok', true,
    'sale_id', v_sale_id,
    'no_invoice', v_invoice,
    'online_order_id', v_order.id,
    'toko_id', v_order.toko_id,
    'total', v_order.total
  );
end;
$$;

-- Dipanggil Edge (service role) + staff pusat untuk simulate
grant execute on function public.fulfill_online_order_payment(text, text, bigint)
  to authenticated, service_role;

-- 8) Simpan token Snap dari Edge
create or replace function public.attach_online_order_snap(
  p_online_order_id uuid,
  p_snap_token text,
  p_redirect_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.online_orders
  set
    midtrans_snap_token = p_snap_token,
    midtrans_redirect_url = p_redirect_url,
    updated_at = now()
  where id = p_online_order_id
    and status = 'pending_payment';

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan / bukan pending');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.attach_online_order_snap(uuid, text, text)
  to anon, authenticated, service_role;

-- 9) Status order untuk Member (by phone + id)
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
  v_phone text := trim(coalesce(p_phone, ''));
  v_row public.online_orders%rowtype;
begin
  select * into v_row
  from public.online_orders
  where id = p_online_order_id
    and phone_e164 = v_phone;

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

-- 10) List cabang yang jual online
create or replace function public.list_online_selling_stores()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.label)
    from (
      select
        t.id as toko_id,
        coalesce(nullif(trim(t.toko_id), ''), t.id) as label,
        t.latitude,
        t.longitude,
        coalesce(s.online_selling_enabled, true) as online_selling_enabled,
        coalesce(s.pickup_enabled, true) as pickup_enabled,
        coalesce(s.delivery_enabled, true) as delivery_enabled,
        coalesce(s.fee_grab, 15000) as fee_grab,
        coalesce(s.fee_gojek, 15000) as fee_gojek,
        coalesce(s.fee_other, 20000) as fee_other
      from public.toko_id t
      left join public.toko_delivery_settings s on s.toko_id = t.id
      where coalesce(s.online_selling_enabled, true) = true
        and upper(trim(t.id)) not in ('PUSAT', 'CABANG-PUSAT')
    ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_online_selling_stores() to anon, authenticated;

-- 11) Update status fulfillment staf
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
begin
  if v_status not in ('packing', 'ready', 'shipped', 'fulfilled', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'Status tidak valid');
  end if;

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
    status = v_status,
    courier_tracking = coalesce(nullif(trim(p_courier_tracking), ''), courier_tracking),
    store_note = coalesce(nullif(trim(p_store_note), ''), store_note),
    updated_at = now()
  where id = p_order_id
    and status in ('paid', 'packing', 'ready', 'shipped', 'fulfilled');

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order belum lunas / tidak bisa diupdate');
  end if;

  -- Sinkron tracking sales bila ada
  update public.sales s
  set tracking_status = case v_status
    when 'ready' then 'SIAP_DIAMBIL'
    when 'shipped' then 'DIKIRIM'
    when 'fulfilled' then 'DIAMBIL'
    when 'packing' then 'DIPROSES'
    else tracking_status
  end
  from public.online_orders o
  where o.id = p_order_id
    and s.id = o.sale_id;

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

grant execute on function public.update_online_order_fulfillment(uuid, text, text, text)
  to authenticated;

-- 12) Bayar uji (hanya order Snap DEV_*) — Member app pakai anon key
create or replace function public.dev_fulfill_online_order(p_midtrans_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  select midtrans_snap_token into v_token
  from public.online_orders
  where midtrans_order_id = trim(p_midtrans_order_id);

  if v_token is null then
    -- belum attach snap: izinkan jika order pending (fallback tanpa Edge)
    if not exists (
      select 1 from public.online_orders
      where midtrans_order_id = trim(p_midtrans_order_id)
        and status = 'pending_payment'
    ) then
      return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
    end if;
  elsif v_token not like 'DEV_%' then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Bayar uji hanya untuk mode tanpa Midtrans (DEV)'
    );
  end if;

  return public.fulfill_online_order_payment(
    trim(p_midtrans_order_id),
    'DEV_MOCK',
    null
  );
end;
$$;

grant execute on function public.dev_fulfill_online_order(text) to anon, authenticated;
