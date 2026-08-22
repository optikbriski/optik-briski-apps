-- =============================================================================
-- 000024 — POS / kasir end-to-end.
-- Apply di SQL Editor live SETELAH 000023.
--
-- Celah saat toko jalan:
-- - sales/sales_items INSERT tenant-wide: harga/qty/Lunas dari HP
-- - consume_pos_cart_into_sale potong stok tanpa POS_HOLD
-- - redeem_member_promo percaya p_discount_applied / voucher_discount client
-- - PosDutyGate hanya di Flutter
-- - stock_reservations / product_stock_ledger using(true)
-- - expire_all_stale_stock_holds grant ke anon
-- - karyawan cabang A bisa jual atas nama cabang B
-- =============================================================================

create or replace function public.can_pos_checkout_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.toko_belongs_to_current_tenant(p_toko)
    and not public.is_platform_user()
    and not public.is_owner_role()
    and (
      public.current_profile_role() in ('admin_pusat', 'super_admin')
      or (
        public.current_profile_role() in ('admin_toko', 'kasir')
        and public.same_store_toko(public.current_profile_toko_id(), p_toko)
      )
    );
$$;

comment on function public.can_pos_checkout_for_toko(text) is
  'Jual di toko: pusat semua cabang tenant; admin_toko/kasir toko sendiri. Bukan owner etalase.';

revoke all on function public.can_pos_checkout_for_toko(text)
  from public, anon;
grant execute on function public.can_pos_checkout_for_toko(text)
  to authenticated, service_role;

create or replace function public.pos_duty_ok(p_karyawan uuid, p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_karyawan is not null
    and public.toko_belongs_to_current_tenant(p_toko)
    and exists (
      select 1
      from public.karyawan k
      where k.id = p_karyawan
        and k.tenant_id is not null
        and k.tenant_id is not distinct from public.current_tenant_id()
        and public.same_store_toko(k.toko_id, p_toko)
    )
    and (
      exists (
        select 1
        from public.karyawan k
        where k.id = p_karyawan
          and upper(trim(coalesce(k.nik, ''))) = 'TRAINING01'
      )
      or (
        exists (
          select 1
          from public.attendance_shifts s
          where s.karyawan_id = p_karyawan
            and upper(trim(coalesce(s.status, ''))) = 'OPEN'
            and public.same_store_toko(s.toko_id, p_toko)
            and (
              s.tenant_id is null
              or s.tenant_id is not distinct from public.current_tenant_id()
            )
        )
        and not exists (
          select 1
          from public.jadwal_kerja j
          where j.karyawan_id = p_karyawan
            and j.tanggal = public.jakarta_today()
            and coalesce(j.is_libur, false)
        )
      )
    );
$$;

comment on function public.pos_duty_ok(uuid, text) is
  'Kasir harus shift OPEN di toko itu, bukan libur. TRAINING01 lolos duty saja.';

revoke all on function public.pos_duty_ok(uuid, text) from public, anon;
grant execute on function public.pos_duty_ok(uuid, text)
  to authenticated, service_role;

create or replace function public.pos_catalog_unit_price(p_product uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    0,
    round(coalesce(p.harga_jual, p.harga, 0))::bigint
  )
  from public.products p
  where p.id = p_product
    and (
      public.current_tenant_id() is null
      or p.tenant_id is not distinct from public.current_tenant_id()
    );
$$;

create or replace function public.pos_voucher_discount_amount(
  p_code text,
  p_subtotal bigint
)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_sub bigint := greatest(0, coalesce(p_subtotal, 0));
  v_dtype text;
  v_dval bigint;
  v_disc bigint := 0;
begin
  if v_code = '' or v_sub <= 0 then
    return 0;
  end if;
  select
    lower(trim(coalesce(discount_type, 'nominal'))),
    greatest(0, coalesce(discount_value, 0))
    into v_dtype, v_dval
  from public.member_promos
  where tenant_id = public.current_tenant_id()
    and upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and coalesce(show_on_pos, true) = true
    and (valid_until is null or valid_until >= current_date)
  order by sort_order nulls last, created_at desc
  limit 1;
  if v_dtype is null or v_dtype = 'info' then
    return 0;
  end if;
  if v_dtype = 'percent' then
    v_disc := floor(v_sub * least(v_dval, 100) / 100.0)::bigint;
  else
    v_disc := v_dval;
  end if;
  if v_disc > v_sub then
    v_disc := v_sub;
  end if;
  return v_disc;
end;
$$;

revoke all on function public.pos_catalog_unit_price(uuid) from public, anon;
grant execute on function public.pos_catalog_unit_price(uuid)
  to authenticated, service_role;
revoke all on function public.pos_voucher_discount_amount(text, bigint)
  from public, anon;
grant execute on function public.pos_voucher_discount_amount(text, bigint)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Stok: hold wajib untuk POS; reserve/hold hanya toko usaha sendiri
-- -----------------------------------------------------------------------------
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
  perform public.assert_toko_in_caller_tenant(v_toko);
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

create or replace function public.consume_reservation_qty_into_sale(
  p_kind text,
  p_ref_type text,
  p_ref_id text,
  p_toko text,
  p_sku text,
  p_qty integer,
  p_alasan_text text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_ledger_ref_type text default null,
  p_ledger_ref_id text default null,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_sku text := upper(trim(coalesce(p_sku, '')));
  v_qty int := greatest(0, coalesce(p_qty, 0));
  v_res public.stock_reservations%rowtype;
  v_consumed int := 0;
  v_out jsonb;
begin
  perform public.assert_toko_in_caller_tenant(v_toko);
  if v_toko = '' or v_sku = '' or v_qty <= 0 then
    raise exception 'consume_reservation_qty_into_sale: argumen tidak valid';
  end if;

  select * into v_res
  from public.stock_reservations
  where status = 'active'
    and kind = p_kind
    and ref_type = p_ref_type
    and ref_id = p_ref_id
    and upper(trim(toko_id)) = v_toko
    and upper(trim(sku)) = v_sku
  order by created_at
  for update
  limit 1;

  if not found then
    if upper(trim(coalesce(p_kind, ''))) = 'POS_HOLD' then
      raise exception
        'Hold POS wajib sebelum potong stok. Buka konfirmasi ulang.'
        using errcode = '42501';
    end if;
  else
    if v_res.qty > v_qty then
      update public.stock_reservations
      set qty = v_res.qty - v_qty, updated_at = now()
      where id = v_res.id;
      v_consumed := v_qty;
    else
      update public.stock_reservations
      set status = 'consumed', updated_at = now()
      where id = v_res.id;
      v_consumed := v_res.qty;
    end if;
    perform public.recompute_product_reserved_qty(v_toko, v_sku);
  end if;

  v_out := public.apply_stock_delta(
    v_toko,
    v_sku,
    -v_qty,
    'SALE',
    coalesce(p_alasan_text, 'Consume hold → SALE'),
    coalesce(p_ledger_ref_type, p_ref_type),
    coalesce(p_ledger_ref_id, p_ref_id),
    p_actor_id,
    p_actor_nama,
    coalesce(p_meta, '{}'::jsonb) || jsonb_build_object(
      'consumed_hold_qty', v_consumed,
      'hold_kind', p_kind
    ),
    false
  );

  return coalesce(v_out, '{}'::jsonb) || jsonb_build_object(
    'ok', true,
    'consumed_hold_qty', v_consumed
  );
end;
$$;

create or replace function public.hold_pos_cart_stock(
  p_toko text,
  p_ref_id text,
  p_items jsonb,
  p_hold_minutes int default 15
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_ref text := trim(coalesce(p_ref_id, ''));
  v_minutes int := greatest(1, least(coalesce(p_hold_minutes, 15), 60));
  v_expires timestamptz := now() + make_interval(mins => v_minutes);
  v_item jsonb;
  v_sku text;
  v_qty int;
  v_agg jsonb := '{}'::jsonb;
  v_wanted text[] := '{}';
  v_holds jsonb := '[]'::jsonb;
  v_res jsonb;
  v_key text;
  r record;
begin
  perform public.assert_toko_in_caller_tenant(v_toko);
  if auth.uid() is not null
     and not public.can_pos_checkout_for_toko(v_toko) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Hanya kasir toko ini yang boleh hold stok POS.'
    );
  end if;

  perform public.expire_stale_pos_holds();
  begin
    perform public.expire_stale_online_orders();
  exception when undefined_function then
    null;
  end;

  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'toko_id kosong');
  end if;
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'ref_id kosong');
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'items harus array');
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(0, least(99, coalesce((v_item->>'qty')::int, 0)));
    if v_sku = '' or v_qty <= 0 then
      continue;
    end if;
    v_agg := jsonb_set(
      v_agg,
      array[v_sku],
      to_jsonb(coalesce((v_agg->>v_sku)::int, 0) + v_qty)
    );
  end loop;

  select coalesce(array_agg(k order by k), '{}')
  into v_wanted
  from jsonb_object_keys(v_agg) as k;

  for r in
    select *
    from public.stock_reservations
    where status = 'active'
      and kind = 'POS_HOLD'
      and ref_type = 'pos_checkout'
      and ref_id = v_ref
      and (cardinality(v_wanted) = 0 or upper(trim(sku)) <> all (v_wanted))
    for update
  loop
    update public.stock_reservations
    set status = 'released', updated_at = now()
    where id = r.id;
    perform public.recompute_product_reserved_qty(r.toko_id, r.sku);
  end loop;

  if v_agg = '{}'::jsonb then
    return jsonb_build_object(
      'ok', true,
      'expires_at', v_expires,
      'hold_minutes', v_minutes,
      'holds', '[]'::jsonb,
      'ref_id', v_ref,
      'toko_id', v_toko
    );
  end if;

  for v_key in select key from jsonb_each_text(v_agg) order by 1
  loop
    begin
      v_res := public.reserve_stock(
        v_toko,
        v_key,
        (v_agg->>v_key)::int,
        'POS_HOLD',
        'pos_checkout',
        v_ref,
        jsonb_build_object(
          'channel', 'pos',
          'hold_minutes', v_minutes,
          'expires_at', v_expires
        )
      );
      v_holds := v_holds || jsonb_build_array(v_res);
    exception when others then
      perform public.release_reservation('POS_HOLD', 'pos_checkout', v_ref);
      return jsonb_build_object(
        'ok', false,
        'error',
        format(
          'Stok tidak cukup untuk hold %s ×%s: %s',
          v_key, (v_agg->>v_key)::int, SQLERRM
        ),
        'sku', v_key,
        'qty', (v_agg->>v_key)::int
      );
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'expires_at', v_expires,
    'hold_minutes', v_minutes,
    'holds', v_holds,
    'ref_id', v_ref,
    'toko_id', v_toko
  );
end;
$$;

create or replace function public.consume_pos_cart_into_sale(
  p_toko text,
  p_ref_id text,
  p_items jsonb,
  p_invoice text,
  p_actor_id uuid default null,
  p_actor_nama text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_ref text := trim(coalesce(p_ref_id, ''));
  v_invoice text := trim(coalesce(p_invoice, ''));
  v_item jsonb;
  v_sku text;
  v_qty int;
  v_agg jsonb := '{}'::jsonb;
  v_results jsonb := '[]'::jsonb;
  v_out jsonb;
  v_key text;
begin
  perform public.assert_toko_in_caller_tenant(v_toko);
  if auth.uid() is not null
     and not public.can_pos_checkout_for_toko(v_toko) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Hanya kasir toko ini yang boleh potong stok POS.'
    );
  end if;
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'toko_id kosong');
  end if;
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'ref_id kosong');
  end if;
  if v_invoice = '' then
    return jsonb_build_object('ok', false, 'error', 'invoice kosong');
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'items harus array');
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(0, least(99, coalesce((v_item->>'qty')::int, 0)));
    if v_sku = '' or v_qty <= 0 then
      continue;
    end if;
    v_agg := jsonb_set(
      v_agg,
      array[v_sku],
      to_jsonb(coalesce((v_agg->>v_sku)::int, 0) + v_qty)
    );
  end loop;

  for v_key in select key from jsonb_each_text(v_agg) order by 1
  loop
    v_qty := (v_agg->>v_key)::int;
    v_out := public.consume_reservation_qty_into_sale(
      'POS_HOLD',
      'pos_checkout',
      v_ref,
      v_toko,
      v_key,
      v_qty,
      'Penjualan POS ' || v_invoice,
      p_actor_id,
      p_actor_nama,
      'sale',
      v_invoice,
      jsonb_build_object('channel', 'pos', 'no_invoice', v_invoice)
    );
    v_results := v_results || jsonb_build_array(v_out);
  end loop;

  perform public.release_reservation('POS_HOLD', 'pos_checkout', v_ref);

  return jsonb_build_object(
    'ok', true,
    'ref_id', v_ref,
    'toko_id', v_toko,
    'invoice', v_invoice,
    'items', v_results
  );
exception when others then
  return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

revoke execute on function public.expire_all_stale_stock_holds()
  from public, anon;
grant execute on function public.expire_all_stale_stock_holds()
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- RLS stok: bukan using(true)
-- -----------------------------------------------------------------------------
drop policy if exists stock_reservations_auth_all on public.stock_reservations;
drop policy if exists stock_reservations_select on public.stock_reservations;
drop policy if exists stock_reservations_write on public.stock_reservations;

create policy stock_reservations_select on public.stock_reservations
  for select to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      public.can_pos_checkout_for_toko(toko_id)
      or public.can_open_store_kiosk_for_toko(toko_id)
    )
  );

-- Tulis hanya RPC DEFINER (postgres). Client REST tidak menambah hold palsu.
create policy stock_reservations_write on public.stock_reservations
  for all to authenticated
  using (false)
  with check (false);

drop policy if exists product_stock_ledger_authenticated_all
  on public.product_stock_ledger;
drop policy if exists product_stock_ledger_select
  on public.product_stock_ledger;
drop policy if exists product_stock_ledger_write
  on public.product_stock_ledger;

create policy product_stock_ledger_select on public.product_stock_ledger
  for select to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
  );

create policy product_stock_ledger_write on public.product_stock_ledger
  for insert to authenticated
  with check (false);

-- -----------------------------------------------------------------------------
-- sales / items: harga katalog, duty, toko sendiri
-- -----------------------------------------------------------------------------
create or replace function public.pos_recompute_sale_totals(p_sale uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sum bigint;
  v_code text;
  v_disc bigint;
  v_total bigint;
  v_bayar bigint;
  v_status text;
begin
  if exists (
    select 1 from public.sales s
    where s.id = p_sale
      and (
        coalesce(s.channel, '') = 'member_online'
        or s.online_order_id is not null
      )
  ) then
    return;
  end if;

  select coalesce(sum(subtotal), 0), s.voucher_code, s.dibayarkan, s.status_pembayaran
    into v_sum, v_code, v_bayar, v_status
  from public.sales s
  left join public.sales_items i on i.sale_id = s.id
  where s.id = p_sale
  group by s.voucher_code, s.dibayarkan, s.status_pembayaran;

  if not found then
    return;
  end if;

  v_disc := public.pos_voucher_discount_amount(v_code, v_sum);
  v_total := greatest(0, v_sum - v_disc);
  v_bayar := least(coalesce(v_bayar, 0), v_total);

  update public.sales
  set
    voucher_discount = v_disc,
    total_harga = v_total,
    dibayarkan = v_bayar,
    sisa_tagihan = greatest(0, v_total - v_bayar),
    status_pembayaran = case
      when v_total <= 0 then status_pembayaran
      when v_bayar <= 0 then 'DP'
      when v_bayar < v_total then 'DP'
      else 'LUNAS'
    end
  where id = p_sale;
end;
$$;

create or replace function public.sales_pos_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jwt_role text;
begin
  if tg_op = 'DELETE' then
    if auth.uid() is not null
       and not public.can_pos_checkout_for_toko(old.toko_id)
       and not public.is_platform_user() then
      raise exception 'Hanya kasir toko ini yang boleh batalkan nota.'
        using errcode = '42501';
    end if;
    return old;
  end if;

  if new.toko_id is null or trim(new.toko_id) = '' then
    raise exception 'toko_id nota wajib.' using errcode = '42501';
  end if;
  if new.tenant_id is null then
    new.tenant_id := public.current_tenant_id();
  end if;

  if coalesce(new.channel, '') = 'member_online'
     or new.online_order_id is not null then
    return new;
  end if;

  v_jwt_role := coalesce(auth.jwt() ->> 'role', '');

  if auth.uid() is not null then
    if not public.can_pos_checkout_for_toko(new.toko_id) then
      raise exception 'Hanya kasir toko/cabang ini yang boleh menulis nota.'
        using errcode = '42501';
    end if;
    if new.kasir_karyawan_id is null then
      raise exception 'Kasir bertugas wajib sebelum checkout.'
        using errcode = '42501';
    end if;
    if not public.pos_duty_ok(new.kasir_karyawan_id, new.toko_id) then
      raise exception
        'Kasir harus sudah absen masuk (shift OPEN) di toko ini.'
        using errcode = '42501';
    end if;
  elsif v_jwt_role is distinct from 'service_role' then
    raise exception 'Login kasir dulu.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' and coalesce(new.voucher_code, '') = '' then
    new.voucher_discount := 0;
  end if;

  if tg_op = 'UPDATE' then
    if not public.same_store_toko(old.toko_id, new.toko_id) then
      raise exception 'toko_id nota tidak boleh dipindah' using errcode = '42501';
    end if;
    if old.kasir_karyawan_id is not null
       and new.kasir_karyawan_id is distinct from old.kasir_karyawan_id then
      raise exception 'kasir nota tidak boleh diganti' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sales_pos_guard on public.sales;
create trigger trg_sales_pos_guard
  before insert or update or delete on public.sales
  for each row
  execute function public.sales_pos_guard();

create or replace function public.sales_items_pos_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_harga bigint;
begin
  if tg_op = 'DELETE' then
    if auth.uid() is not null then
      select * into v_sale from public.sales where id = old.sale_id;
      if found and not public.can_pos_checkout_for_toko(v_sale.toko_id) then
        raise exception 'Hanya kasir toko ini yang boleh hapus item nota.'
          using errcode = '42501';
      end if;
    end if;
    return old;
  end if;

  select * into v_sale from public.sales where id = new.sale_id;
  if not found then
    raise exception 'Nota penjualan tidak ditemukan.' using errcode = '42501';
  end if;

  if coalesce(v_sale.channel, '') = 'member_online'
     or v_sale.online_order_id is not null then
    new.qty := least(99, greatest(1, coalesce(new.qty, 1)));
    return new;
  end if;

  if auth.uid() is not null
     and not public.can_pos_checkout_for_toko(v_sale.toko_id) then
    raise exception 'Hanya kasir toko ini yang boleh menambah item nota.'
      using errcode = '42501';
  end if;

  if new.product_id is null then
    raise exception 'product_id item wajib.' using errcode = '42501';
  end if;

  v_harga := public.pos_catalog_unit_price(new.product_id);
  if v_harga is null then
    raise exception 'Produk item bukan milik usaha ini.' using errcode = '42501';
  end if;

  new.qty := least(99, greatest(1, coalesce(new.qty, 1)));
  new.harga_satuan := v_harga;
  new.subtotal := v_harga * new.qty;
  return new;
end;
$$;

drop trigger if exists trg_sales_items_pos_guard on public.sales_items;
create trigger trg_sales_items_pos_guard
  before insert or update on public.sales_items
  for each row
  execute function public.sales_items_pos_guard();

create or replace function public.sales_items_pos_after()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.pos_recompute_sale_totals(old.sale_id);
    return old;
  end if;
  perform public.pos_recompute_sale_totals(new.sale_id);
  return new;
end;
$$;

drop trigger if exists trg_sales_items_pos_after on public.sales_items;
create trigger trg_sales_items_pos_after
  after insert or update or delete on public.sales_items
  for each row
  execute function public.sales_items_pos_after();

drop policy if exists sales_insert on public.sales;
drop policy if exists sales_update on public.sales;
drop policy if exists sales_delete on public.sales;

create policy sales_insert on public.sales
  for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.can_pos_checkout_for_toko(toko_id)
  );

create policy sales_update on public.sales
  for update to authenticated
  using (public.can_pos_checkout_for_toko(toko_id))
  with check (public.can_pos_checkout_for_toko(toko_id));

create policy sales_delete on public.sales
  for delete to authenticated
  using (public.can_pos_checkout_for_toko(toko_id));

-- -----------------------------------------------------------------------------
-- Voucher: nominal selalu dari server
-- -----------------------------------------------------------------------------
create or replace function public.redeem_member_promo(
  p_code text,
  p_sale_id uuid default null,
  p_phone text default null,
  p_discount_applied bigint default 0,
  p_online_order_id uuid default null,
  p_channel text default 'pos',
  p_tenant_id uuid default null
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
  v_phone text := trim(coalesce(p_phone, ''));
  v_balance int := 0;
  v_points int := 0;
  v_disc bigint := 0;
  v_sub bigint := 0;
  v_updated int := 0;
  v_existing uuid;
  v_ch text := lower(trim(coalesce(p_channel, 'pos')));
  v_ref_label text;
  v_tenant uuid;
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode voucher kosong');
  end if;
  if (p_sale_id is null and p_online_order_id is null)
     or (p_sale_id is not null and p_online_order_id is not null) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Harus ada tepat satu: sale_id atau online_order_id'
    );
  end if;
  v_tenant := coalesce(public.current_tenant_id(), p_tenant_id);
  if v_tenant is null then
    raise exception 'tenant wajib';
  end if;
  v_tenant := public.require_member_tenant(v_tenant);

  if v_ch not in ('pos', 'online', 'member', 'any') then
    v_ch := case when p_online_order_id is not null then 'online' else 'pos' end;
  end if;

  if p_sale_id is not null then
    select * into v_sale
    from public.sales
    where id = p_sale_id and tenant_id = v_tenant
    limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Nota penjualan tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_sale.no_invoice, p_sale_id::text);
    select coalesce(sum(subtotal), 0) into v_sub
    from public.sales_items
    where sale_id = p_sale_id;
    if v_sub <= 0 then
      v_sub := greatest(0, coalesce(v_sale.total_harga, 0));
    end if;
    select id into v_existing
    from public.member_promo_redemptions
    where sale_id = p_sale_id
    limit 1;
  else
    select * into v_online
    from public.online_orders
    where id = p_online_order_id and tenant_id = v_tenant
    limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Pesanan online tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_online.midtrans_order_id, p_online_order_id::text);
    v_sub := greatest(0, coalesce(v_online.total, 0));
    select id into v_existing
    from public.member_promo_redemptions
    where online_order_id = p_online_order_id
    limit 1;
  end if;
  if v_existing is not null then
    return jsonb_build_object(
      'ok', true, 'skipped', true, 'reason', 'already_redeemed',
      'redemption_id', v_existing
    );
  end if;

  select * into v_row
  from public.member_promos
  where tenant_id = v_tenant
    and upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and (
      (v_ch = 'pos' and coalesce(show_on_pos, true) = true)
      or (v_ch in ('online', 'member') and coalesce(show_on_member, true) = true)
      or (v_ch = 'any' and (
        coalesce(show_on_pos, true) = true
        or coalesce(show_on_member, true) = true
      ))
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

  -- Abaikan p_discount_applied client.
  if p_sale_id is not null then
    v_disc := public.pos_voucher_discount_amount(v_code, v_sub);
  else
    if lower(trim(coalesce(v_row.discount_type, 'nominal'))) = 'percent' then
      v_disc := floor(v_sub * least(greatest(0, coalesce(v_row.discount_value, 0)), 100) / 100.0)::bigint;
    else
      v_disc := greatest(0, coalesce(v_row.discount_value, 0));
    end if;
    if v_disc > v_sub then
      v_disc := v_sub;
    end if;
  end if;

  v_points := greatest(0, coalesce(v_row.points_cost, 0));
  if v_phone = '' then
    if p_sale_id is not null then
      v_phone := coalesce(v_sale.no_wa, '');
    else
      v_phone := coalesce(v_online.phone_e164, '');
    end if;
  end if;
  v_member_id := public.lookup_member_id_in_tenant(v_phone, v_tenant);

  if v_points > 0 then
    if v_member_id is null then
      return jsonb_build_object(
        'ok', false,
        'error',
        'Voucher butuh ' || v_points || ' poin — nomor WA harus terdaftar member'
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
    insert into public.member_points_ledger (member_id, delta, reason, sale_id, meta)
    values (
      v_member_id, -v_points, 'voucher_redeem', p_sale_id,
      jsonb_build_object(
        'voucher_code', v_code, 'promo_id', v_row.id, 'ref', v_ref_label,
        'channel', v_ch, 'online_order_id', p_online_order_id,
        'discount_applied', v_disc, 'tenant_id', v_tenant
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
    set voucher_code = v_code,
        voucher_discount = v_disc
    where id = p_sale_id and tenant_id = v_tenant;
    perform public.pos_recompute_sale_totals(p_sale_id);
  end if;
  return jsonb_build_object(
    'ok', true, 'promo_id', v_row.id, 'voucher_code', v_code,
    'points_spent', v_points, 'member_id', v_member_id, 'channel', v_ch,
    'discount_applied', v_disc,
    'quantity_remaining', (
      select quantity_remaining from public.member_promos where id = v_row.id
    )
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', true, 'skipped', true, 'reason', 'already_redeemed_race'
    );
end;
$$;

-- -----------------------------------------------------------------------------
-- Finance POS + poin INVOICE: tidak boleh nominal/poin palsu
-- -----------------------------------------------------------------------------
create or replace function public.finance_pos_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;
  if upper(trim(coalesce(new.kategori, ''))) <> 'PENJUALAN KASIR' then
    return new;
  end if;
  if auth.uid() is null then
    return new;
  end if;
  if not public.can_pos_checkout_for_toko(new.toko_id) then
    raise exception 'Hanya kasir toko ini yang boleh catat pemasukan POS.'
      using errcode = '42501';
  end if;
  select * into v_sale
  from public.sales
  where no_invoice = new.referensi_id
    and public.same_store_toko(toko_id, new.toko_id)
    and tenant_id is not distinct from public.current_tenant_id()
  limit 1;
  if not found then
    raise exception 'Pemasukan kasir wajib nota penjualan di toko yang sama.'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.sales_items i where i.sale_id = v_sale.id
  ) then
    raise exception 'Pemasukan kasir wajib nota yang sudah ada item.'
      using errcode = '42501';
  end if;
  if coalesce(new.nominal, 0) > coalesce(v_sale.dibayarkan, 0) then
    raise exception 'Nominal buku besar tidak boleh lebih dari yang dibayar.'
      using errcode = '42501';
  end if;
  if coalesce(new.nominal, 0) <= 0 then
    raise exception 'Nominal pemasukan kasir wajib > 0.' using errcode = '42501';
  end if;
  new.status_konfirmasi := coalesce(nullif(trim(new.status_konfirmasi), ''), 'APPROVED');
  return new;
end;
$$;

drop trigger if exists trg_finance_pos_guard on public.finance_transactions;
create trigger trg_finance_pos_guard
  before insert on public.finance_transactions
  for each row
  execute function public.finance_pos_guard();

create or replace function public.poin_logs_invoice_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
begin
  if tg_op = 'INSERT' and upper(trim(coalesce(new.sumber, ''))) = 'INVOICE' then
    if coalesce(new.poin, 0) <> 5 then
      raise exception 'Poin INVOICE hanya +5 per nota.' using errcode = '42501';
    end if;
    if new.ref_id is null or trim(new.ref_id) = '' then
      raise exception 'Poin INVOICE wajib ref nota.' using errcode = '42501';
    end if;
    select * into v_sale
    from public.sales
    where id::text = trim(new.ref_id)
       or no_invoice = trim(new.ref_id)
    limit 1;
    if not found then
      raise exception 'Poin INVOICE hanya untuk nota yang ada.'
        using errcode = '42501';
    end if;
    if not public.can_pos_checkout_for_toko(v_sale.toko_id)
       and auth.uid() is not null then
      raise exception 'Poin INVOICE hanya dari kasir toko nota.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_poin_logs_invoice_guard on public.poin_logs;
create trigger trg_poin_logs_invoice_guard
  before insert on public.poin_logs
  for each row
  execute function public.poin_logs_invoice_guard();

-- Midtrans: toko + kasir. Dev fulfill tetap hanya token DEV_*.
create or replace function public.create_pos_payment(
  p_amount_idr bigint,
  p_purpose text,
  p_toko_id text default null,
  p_sale_id uuid default null,
  p_invoice_no text default null,
  p_customer_name text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tid uuid := public.current_tenant_id();
  v_uid uuid := auth.uid();
  v_purpose text := lower(trim(coalesce(p_purpose, 'sale')));
  v_mid text;
  v_id uuid := gen_random_uuid();
  v_toko text := nullif(trim(coalesce(p_toko_id, '')), '');
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Login kasir dulu');
  end if;
  if v_tid is null then
    return jsonb_build_object('ok', false, 'error', 'Kode usaha belum terikat');
  end if;
  if public.is_platform_user() then
    return jsonb_build_object('ok', false, 'error', 'Etalase Rekasa bukan kasir');
  end if;
  if v_toko is not null then
    if not public.can_pos_checkout_for_toko(v_toko) then
      return jsonb_build_object('ok', false, 'error', 'Bukan kasir toko ini');
    end if;
  end if;
  if v_purpose not in ('sale', 'pelunasan') then
    return jsonb_build_object('ok', false, 'error', 'Tujuan bayar tidak valid');
  end if;
  if coalesce(p_amount_idr, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Nominal Midtrans harus > 0');
  end if;
  if v_purpose = 'pelunasan' and p_sale_id is null then
    return jsonb_build_object('ok', false, 'error', 'Pelunasan butuh nota');
  end if;

  v_mid := 'POS-' || replace(v_id::text, '-', '');

  insert into public.pos_payments (
    id, tenant_id, toko_id, sale_id, purpose, amount_idr,
    midtrans_order_id, invoice_no, customer_name, customer_phone, created_by
  ) values (
    v_id, v_tid, v_toko,
    p_sale_id, v_purpose, p_amount_idr, v_mid,
    nullif(trim(coalesce(p_invoice_no, '')), ''),
    nullif(trim(coalesce(p_customer_name, '')), ''),
    nullif(trim(coalesce(p_phone, '')), ''),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'midtrans_order_id', v_mid,
    'amount_idr', p_amount_idr,
    'purpose', v_purpose,
    'status', 'pending'
  );
end;
$$;

revoke all on function public.sales_pos_guard() from public, anon;
revoke all on function public.sales_items_pos_guard() from public, anon;
revoke all on function public.sales_items_pos_after() from public, anon;
revoke all on function public.finance_pos_guard() from public, anon;
revoke all on function public.poin_logs_invoice_guard() from public, anon;
revoke all on function public.pos_recompute_sale_totals(uuid)
  from public, anon, authenticated;
grant execute on function public.pos_recompute_sale_totals(uuid)
  to service_role;
