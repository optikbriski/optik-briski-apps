-- =============================================================================
-- 000052 — Pesanan online: tenant wajib, toko yang sama, tanpa default Optik.
-- Apply di SQL Editor live SETELAH 000051. Idempotent.
--
-- Celah saat toko jalan:
-- - RLS online_orders: owner/pusat lihat SEMUA merek (tanpa tenant_id)
-- - update_online_order_fulfillment tanpa tenant + PUSAT exact
-- - expire_stale_online_orders GRANT anon (expire lintas merek)
-- - attach_online_order_snap / dev_fulfill anon tanpa tenant
-- - create_online_order redeem voucher tanpa p_tenant_id → tenant wajib
-- - katalog exact PUSAT ≠ CABANG-PUSAT; qty JSON 2.0 pecah ::int
-- =============================================================================

create or replace function public.expire_stale_online_orders_for_tenant(p_tenant_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n int := 0;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  update public.online_orders
  set status = 'expired', updated_at = now()
  where tenant_id = v_tenant
    and status = 'pending_payment'
    and coalesce(expires_at, created_at + interval '15 minutes') < now();
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.expire_stale_online_orders_for_tenant(uuid)
  from public, anon;
grant execute on function public.expire_stale_online_orders_for_tenant(uuid)
  to authenticated, service_role;

revoke execute on function public.expire_stale_online_orders()
  from public, anon;
grant execute on function public.expire_stale_online_orders()
  to authenticated, service_role;

create or replace function public.list_member_online_orders(
  p_phone text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  perform public.expire_stale_online_orders_for_tenant(v_tenant);

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
      where tenant_id = v_tenant
        and (
          phone_e164 = v_phone
          or phone_e164 = v_alt
          or public.wa_digits(phone_e164) = v_phone
        )
      order by created_at desc
      limit 40
    ) o
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_online_orders(text, uuid)
  to anon, authenticated;

create or replace function public.list_online_selling_stores(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
  v_pusat text := public.tenant_pusat_toko_id(v_tenant);
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
        coalesce(s.online_selling_enabled, true) as delivery_enabled,
        coalesce(s.fee_grab, 15000) as fee_grab,
        coalesce(s.fee_gojek, 15000) as fee_gojek,
        coalesce(s.fee_other, 20000) as fee_other,
        coalesce(s.obr_instant_enabled, true) as obr_instant_enabled,
        coalesce(s.obr_sameday_enabled, true) as obr_sameday_enabled,
        coalesce(s.obr_nextday_enabled, true) as obr_nextday_enabled
      from public.toko_id t
      left join public.toko_delivery_settings s
        on public.same_store_toko(s.toko_id, t.id)
      where t.tenant_id = v_tenant
        and coalesce(t.is_pusat, false) = false
        and not public.same_store_toko(t.id, coalesce(v_pusat, 'PUSAT'))
        and coalesce(s.online_selling_enabled, true) = true
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_online_selling_stores(uuid)
  to anon, authenticated;

create or replace function public.get_online_order_for_member(
  p_phone text,
  p_online_order_id uuid,
  p_tenant_id uuid default null
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
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  perform public.expire_stale_online_orders_for_tenant(v_tenant);

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
    and tenant_id = v_tenant
    and (
      phone_e164 = v_phone
      or phone_e164 = v_alt
      or public.wa_digits(phone_e164) = v_phone
    );

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Tidak ditemukan');
  end if;

  return jsonb_build_object('ok', true, 'order', to_jsonb(v_row));
end;
$$;
grant execute on function public.get_online_order_for_member(text, uuid, uuid)
  to anon, authenticated;

create or replace function public.cancel_pending_online_order_for_member(
  p_phone text,
  p_online_order_id uuid,
  p_reason text default 'member_cancel',
  p_tenant_id uuid default null
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
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
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
    and tenant_id = v_tenant
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
      'ok', true, 'already', true, 'status', v_row.status
    );
  end if;

  return public.cancel_pending_online_order(
    p_online_order_id,
    coalesce(nullif(trim(p_reason), ''), 'member_cancel')
  );
end;
$$;
grant execute on function public.cancel_pending_online_order_for_member(text, uuid, text, uuid)
  to anon, authenticated;

create or replace function public.quote_online_delivery(
  p_toko_id text,
  p_courier text,
  p_tenant_id uuid default null
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
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'Cabang wajib dipilih');
  end if;
  if not exists (
    select 1 from public.toko_id t
    where t.tenant_id = v_tenant
      and public.same_store_toko(t.id, v_toko)
  ) then
    return jsonb_build_object('ok', false, 'error', 'Cabang bukan milik usaha ini');
  end if;

  select * into v_row
  from public.toko_delivery_settings
  where public.same_store_toko(toko_id, v_toko)
  limit 1;
  if not found then
    insert into public.toko_delivery_settings (toko_id) values (v_toko)
    returning * into v_row;
  end if;
  if not coalesce(v_row.online_selling_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang belum aktif jual online');
  end if;
  v_fee := case v_courier
    when 'grab' then coalesce(v_row.fee_grab, 0)
    when 'gojek' then coalesce(v_row.fee_gojek, 0)
    when 'other' then coalesce(v_row.fee_other, 0)
    when 'obr' then greatest(
      0,
      least(
        coalesce(v_row.fee_grab, 15000),
        coalesce(v_row.fee_gojek, 15000),
        coalesce(v_row.fee_other, 15000)
      ) - 2000
    )
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
    'delivery_enabled', coalesce(v_row.online_selling_enabled, true)
  );
end;
$$;
grant execute on function public.quote_online_delivery(text, text, uuid)
  to anon, authenticated;

drop policy if exists online_orders_read_staff on public.online_orders;
create policy online_orders_read_staff on public.online_orders
  for select to authenticated
  using (
    public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and (
        public.current_profile_role() in ('owner', 'admin_pusat', 'super_admin')
        or public.same_store_toko(public.current_profile_toko_id(), toko_id)
      )
    )
  );

drop policy if exists online_orders_write_staff on public.online_orders;
create policy online_orders_write_staff on public.online_orders
  for update to authenticated
  using (
    public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and (
        public.current_profile_role() in ('owner', 'admin_pusat', 'super_admin')
        or public.same_store_toko(public.current_profile_toko_id(), toko_id)
      )
    )
  )
  with check (
    public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and (
        public.current_profile_role() in ('owner', 'admin_pusat', 'super_admin')
        or public.same_store_toko(public.current_profile_toko_id(), toko_id)
      )
    )
  );

drop function if exists public.update_online_order_fulfillment(uuid, text, text, text);
create function public.update_online_order_fulfillment(
  p_order_id uuid,
  p_status text,
  p_courier_tracking text default null,
  p_store_note text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_staff_toko text;
  v_toko text;
  v_phone text;
  v_fulfill text;
  v_cur text;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_allowed boolean := false;
  v_invoice text;
  v_title text;
  v_body text;
  v_tenant uuid;
  v_order_tenant uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_order_id is null or v_status = '' then
    return jsonb_build_object('ok', false, 'error', 'Parameter tidak lengkap');
  end if;
  if v_status not in ('packing', 'ready', 'shipped', 'fulfilled', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'Status tidak valid');
  end if;

  if public.is_platform_user() then
    v_tenant := null;
  else
    v_tenant := coalesce(
      public.current_tenant_id(),
      public.require_member_tenant(p_tenant_id)
    );
  end if;

  select o.toko_id, o.phone_e164, o.fulfillment, o.status, o.tenant_id
    into v_toko, v_phone, v_fulfill, v_cur, v_order_tenant
  from public.online_orders o
  where o.id = p_order_id
    and (v_tenant is null or o.tenant_id = v_tenant)
  for update;

  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
  end if;

  select p.role, p.toko_id into v_role, v_staff_toko
  from public.profiles p
  where p.id = v_uid;

  if v_role is null then
    return jsonb_build_object('ok', false, 'error', 'Profil staf tidak ditemukan');
  end if;

  v_allowed := public.is_platform_user()
    or v_role in ('owner', 'admin_pusat', 'super_admin')
    or public.same_store_toko(v_staff_toko, v_toko);

  if not coalesce(v_allowed, false) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Tidak berwenang: order milik ' || v_toko || ', staf ' || coalesce(v_staff_toko, '-')
    );
  end if;

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
    and (v_tenant is null or tenant_id = v_tenant)
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
    and s.id = o.sale_id
    and (v_tenant is null or s.tenant_id = v_tenant);

  select s.no_invoice into v_invoice
  from public.online_orders o
  left join public.sales s on s.id = o.sale_id
  where o.id = p_order_id;

  if v_phone is not null and v_status <> 'cancelled' then
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
      when 'fulfilled' then 'Terima kasih sudah belanja.'
      else v_status
    end;
    begin
      perform public.create_member_order_alert(
        coalesce(v_invoice, ''),
        v_phone,
        v_title,
        v_body,
        'status',
        p_order_id,
        coalesce(v_order_tenant, v_tenant)
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

grant execute on function public.update_online_order_fulfillment(uuid, text, text, text, uuid)
  to authenticated;

create or replace function public.attach_online_order_snap(
  p_online_order_id uuid,
  p_snap_token text,
  p_redirect_url text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := coalesce(
    public.current_tenant_id(),
    public.require_member_tenant(p_tenant_id)
  );
  n int := 0;
begin
  update public.online_orders
  set
    midtrans_snap_token = p_snap_token,
    midtrans_redirect_url = p_redirect_url,
    updated_at = now()
  where id = p_online_order_id
    and tenant_id = v_tenant
    and status = 'pending_payment';
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan / bukan pending');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

drop function if exists public.attach_online_order_snap(uuid, text, text);
grant execute on function public.attach_online_order_snap(uuid, text, text, uuid)
  to anon, authenticated, service_role;

revoke execute on function public.dev_fulfill_online_order(text)
  from public, anon;
grant execute on function public.dev_fulfill_online_order(text)
  to authenticated, service_role;

-- create_online_order: tenant + toko sama + qty JSON + redeem tenant
drop function if exists public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision,
  jsonb, bigint, text, text, text, text, boolean, bigint, text, bigint
);
drop function if exists public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision,
  jsonb, bigint, text, text, text, text, boolean, bigint, text, bigint, uuid
);
create function public.create_online_order(
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
,
  p_tenant_id uuid default null
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
  v_tenant uuid;
  v_pusat_toko text;
begin
  if v_phone is null or v_phone = '' then
    return jsonb_build_object('ok', false, 'error', 'Login / nomor WA wajib');
  end if;
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'Pilih cabang');
  end if;
  v_tenant := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  v_pusat_toko := public.tenant_pusat_toko_id(v_tenant);
  if not exists (
    select 1 from public.toko_id t
    where t.tenant_id = v_tenant
      and public.same_store_toko(t.id, v_toko)
  ) then
    return jsonb_build_object('ok', false, 'error', 'Cabang bukan milik usaha ini');
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

  select * into v_settings from public.toko_delivery_settings where public.same_store_toko(toko_id, v_toko) limit 1;
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
    v_qty := greatest(1, coalesce(round(nullif(v_item->>'qty','')::numeric), 1)::int);
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
    where pp.tenant_id = v_tenant
      and public.same_store_toko(pp.toko_id, coalesce(v_pusat_toko, 'PUSAT'))
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
      public.list_branch_sellable(v_toko, array[v_sku], v_tenant)
    ) as elem
    limit 1;

    if v_sell is not null then
      v_avail := coalesce(round(nullif(v_sell->>'available_qty','')::numeric), 0)::int;
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
    where tenant_id = v_tenant
      and upper(trim(coalesce(voucher_code, ''))) = v_promo_code
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
    where t.tenant_id = v_tenant
      and public.same_store_toko(t.id, v_toko)
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
    tenant_id, member_id, phone_e164, customer_name, toko_id, fulfillment, courier,
    address_text, address_lat, address_lng, shipping_fee, items,
    subtotal, total, status, midtrans_order_id,
    store_note,
    courier_company, courier_service_code, courier_service_name,
    shipping_category, is_obr,
    shipping_voucher_discount, product_promo_code, product_promo_discount,
    expires_at
  ) values (
    v_tenant, p_member_id, v_phone, nullif(trim(coalesce(p_customer_name, '')), ''),
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
    v_stock_qty := greatest(0, coalesce(round(nullif(v_item->>'stock_qty','')::numeric), 0)::int);
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
      'online',
      v_tenant
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
  jsonb, bigint, text, text, text, text, boolean, bigint, text, bigint, uuid
) to anon, authenticated, service_role;
