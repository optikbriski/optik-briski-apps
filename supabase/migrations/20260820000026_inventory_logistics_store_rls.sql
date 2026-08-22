-- =============================================================================
-- 000026 — Inventory / logistics end-to-end.
-- Apply di SQL Editor live SETELAH 000025.
--
-- Celah saat toko jalan:
-- - pending_requests / stock_move_history / draft_pengiriman using(true)
--   → merek lain baca/tulis RO/DO
-- - products FOR ALL tenant → PATCH stock tanpa ledger
-- - apply_stock_delta tanpa available/reserved (regress 000007)
-- - reserve/release/consume/recognize tanpa role/toko
-- - terima/TRANSIT/SUCCESS hanya di Flutter (bisa skip / buka ulang)
-- =============================================================================

create or replace function public.can_manage_inventory_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.toko_belongs_to_current_tenant(p_toko)
    and not public.is_owner_role()
    and (
      public.is_platform_user()
      or public.current_profile_role() in ('admin_pusat', 'super_admin')
      or (
        public.current_profile_role() = 'admin_toko'
        and public.same_store_toko(public.current_profile_toko_id(), p_toko)
      )
    );
$$;

comment on function public.can_manage_inventory_for_toko(text) is
  'Mutasi stok toko: pusat semua cabang tenant; admin_toko toko sendiri. Bukan owner/kasir.';

create or replace function public.can_request_ro_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.can_manage_inventory_for_toko(p_toko)
    or public.can_pos_checkout_for_toko(p_toko);
$$;

comment on function public.can_request_ro_for_toko(text) is
  'Ajukan RO: kasir/admin toko sendiri. Bukan cabang orang. Bukan merek lain.';

create or replace function public.can_receive_stock_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_inventory_for_toko(p_toko);
$$;

create or replace function public.can_edit_product_catalog()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.current_tenant_id() is not null
    and (
      public.is_platform_user()
      or public.current_profile_role() in (
        'owner', 'admin_pusat', 'super_admin', 'admin_toko'
      )
    );
$$;

create or replace function public.inventory_rpc_on()
returns void
language plpgsql
as $$
begin
  perform set_config('app.inventory_rpc', '1', true);
end;
$$;

revoke all on function public.can_manage_inventory_for_toko(text)
  from public, anon;
grant execute on function public.can_manage_inventory_for_toko(text)
  to authenticated, service_role;
revoke all on function public.can_request_ro_for_toko(text) from public, anon;
grant execute on function public.can_request_ro_for_toko(text)
  to authenticated, service_role;
revoke all on function public.can_receive_stock_for_toko(text)
  from public, anon;
grant execute on function public.can_receive_stock_for_toko(text)
  to authenticated, service_role;
revoke all on function public.can_edit_product_catalog() from public, anon;
grant execute on function public.can_edit_product_catalog()
  to authenticated, service_role;
revoke all on function public.inventory_rpc_on() from public, anon, authenticated;
grant execute on function public.inventory_rpc_on() to service_role;

-- -----------------------------------------------------------------------------
-- products: stok/reserved hanya lewat RPC (flag session)
-- -----------------------------------------------------------------------------
create or replace function public.products_stock_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if current_setting('app.inventory_rpc', true) is distinct from '1' then
      new.stock := 0;
      new.reserved_qty := 0;
    end if;
    return new;
  end if;

  if current_setting('app.inventory_rpc', true) is distinct from '1' then
    if coalesce(old.stock, 0) is distinct from coalesce(new.stock, 0)
       or coalesce(old.reserved_qty, 0) is distinct from coalesce(new.reserved_qty, 0)
    then
      raise exception
        'Stok hanya boleh diubah lewat mutasi berledger (bukan PATCH langsung).'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_products_stock_guard on public.products;
create trigger trg_products_stock_guard
  before insert or update on public.products
  for each row
  execute function public.products_stock_guard();

drop policy if exists products_tenant_all on public.products;
drop policy if exists products_select on public.products;
drop policy if exists products_insert on public.products;
drop policy if exists products_update on public.products;
drop policy if exists products_delete on public.products;

create policy products_select on public.products
  for select to authenticated
  using (
    tenant_id = public.current_tenant_id()
    or public.is_platform_user()
  );

create policy products_insert on public.products
  for insert to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and public.can_edit_product_catalog()
    and public.toko_belongs_to_current_tenant(toko_id)
  );

create policy products_update on public.products
  for update to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.can_edit_product_catalog()
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.can_edit_product_catalog()
  );

create policy products_delete on public.products
  for delete to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.current_profile_role() in ('admin_pusat', 'super_admin')
    and not public.is_owner_role()
  );

-- -----------------------------------------------------------------------------
-- apply_stock_delta: available/reserved + hak toko
-- -----------------------------------------------------------------------------
create or replace function public.apply_stock_delta(
  p_toko text,
  p_sku text,
  p_qty_delta integer,
  p_reason text,
  p_alasan_text text default null,
  p_ref_type text default null,
  p_ref_id text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_meta jsonb default '{}'::jsonb,
  p_allow_create boolean default true
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
  v_before integer;
  v_after integer;
  v_available integer;
  v_ledger_id uuid;
  v_tenant uuid;
  v_jwt text;
begin
  perform public.inventory_rpc_on();
  v_tenant := public.assert_toko_in_caller_tenant(v_toko);
  if p_qty_delta is null or p_qty_delta = 0 then
    raise exception 'qty_delta tidak boleh 0';
  end if;
  if p_reason not in (
    'OPENING','TRANSFER_OUT','TRANSFER_IN','RETURN_OUT','RETURN_IN',
    'SALE','WRITE_OFF','ADJUST'
  ) then
    raise exception 'reason tidak valid: %', p_reason;
  end if;
  if p_reason in ('WRITE_OFF','ADJUST')
     and (p_alasan_text is null or trim(p_alasan_text) = '') then
    raise exception 'alasan_text wajib untuk %', p_reason;
  end if;

  v_jwt := coalesce(auth.jwt() ->> 'role', '');
  if auth.uid() is not null then
    if p_reason = 'SALE' then
      -- Kasir POS atau fulfill online (member/webhook). Tenant sudah di-assert.
      -- Available/reserved di bawah mencegah potong stok yang sedang di-hold.
      null;
    elsif p_reason = 'TRANSFER_IN' then
      if not public.can_receive_stock_for_toko(v_toko)
         and not public.can_manage_inventory_for_toko(v_toko) then
        raise exception 'Hanya admin toko tujuan yang boleh terima stok.'
          using errcode = '42501';
      end if;
    elsif p_reason in ('TRANSFER_OUT', 'WRITE_OFF', 'ADJUST', 'OPENING',
                       'RETURN_OUT', 'RETURN_IN') then
      if not public.can_manage_inventory_for_toko(v_toko) then
        raise exception 'Hanya admin toko/cabang ini yang boleh mutasi stok.'
          using errcode = '42501';
      end if;
    end if;
  elsif v_jwt is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;

  if p_allow_create then
    v_row := public.ensure_product_at_toko(
      v_sku, v_toko, coalesce(p_meta->'product', '{}'::jsonb)
    );
  else
    select * into v_row
    from public.products
    where tenant_id = v_tenant
      and upper(trim(sku)) = upper(trim(v_sku))
      and upper(trim(toko_id)) = v_toko
    for update;
    if not found then
      raise exception 'Produk % tidak ada di %', v_sku, v_toko;
    end if;
  end if;

  select * into v_row
  from public.products
  where id = v_row.id
  for update;

  v_before := coalesce(v_row.stock, 0);
  v_after := v_before + p_qty_delta;
  if v_after < 0 then
    raise exception 'Stok tidak cukup di % untuk SKU % (stok %, delta %)',
      v_toko, v_sku, v_before, p_qty_delta;
  end if;

  if p_qty_delta < 0
     and p_reason in ('SALE', 'TRANSFER_OUT', 'WRITE_OFF', 'RETURN_OUT') then
    v_available := public.product_available_qty(v_before, v_row.reserved_qty);
    if abs(p_qty_delta) > v_available then
      raise exception
        'Stok tersedia tidak cukup di % untuk SKU % (real %, pending %, tersedia %, minta %)',
        v_toko, v_sku, v_before, v_row.reserved_qty, v_available, abs(p_qty_delta)
        using errcode = '42501';
    end if;
  end if;
  if v_after < coalesce(v_row.reserved_qty, 0)
     and p_reason = 'ADJUST'
     and p_qty_delta < 0 then
    raise exception
      'Revisi stok tidak boleh di bawah pending booking (%).'
      , v_row.reserved_qty
      using errcode = '42501';
  end if;

  update public.products
  set stock = v_after
  where id = v_row.id
    and tenant_id = v_tenant;

  insert into public.product_stock_ledger (
    sku, toko_id, product_id, qty_delta, stock_before, stock_after,
    reason, alasan_text, ref_type, ref_id, actor_id, actor_nama, meta
  ) values (
    v_row.sku, v_toko, v_row.id, p_qty_delta, v_before, v_after,
    p_reason, p_alasan_text, p_ref_type, p_ref_id, p_actor_id, p_actor_nama,
    coalesce(p_meta, '{}'::jsonb)
  )
  returning id into v_ledger_id;

  return jsonb_build_object(
    'ok', true,
    'ledger_id', v_ledger_id,
    'product_id', v_row.id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'stock_before', v_before,
    'stock_after', v_after,
    'pending_stock', coalesce(v_row.reserved_qty, 0),
    'available_qty', public.product_available_qty(v_after, v_row.reserved_qty),
    'qty_delta', p_qty_delta,
    'reason', p_reason
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- reserve / release / consume / recognize: tenant + role
-- -----------------------------------------------------------------------------
create or replace function public.recompute_product_reserved_qty(
  p_toko text,
  p_sku text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_sku text := trim(p_sku);
  v_sum integer;
begin
  perform public.inventory_rpc_on();
  select coalesce(sum(qty), 0)::integer into v_sum
  from public.stock_reservations
  where status = 'active'
    and upper(trim(toko_id)) = v_toko
    and upper(trim(sku)) = upper(trim(v_sku));

  update public.products
  set reserved_qty = v_sum
  where upper(trim(toko_id)) = v_toko
    and upper(trim(sku)) = upper(trim(v_sku));

  return v_sum;
end;
$$;

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
  perform public.inventory_rpc_on();
  perform public.assert_toko_in_caller_tenant(v_toko);
  if p_qty is null or p_qty <= 0 then
    raise exception 'qty reservasi harus > 0';
  end if;
  if p_kind not in ('DO_DRAFT', 'DO_PREPARING', 'RO', 'POS_HOLD', 'ONLINE_HOLD') then
    raise exception 'kind tidak valid: %', p_kind;
  end if;

  if auth.uid() is not null then
    if p_kind = 'POS_HOLD' then
      if not public.can_pos_checkout_for_toko(v_toko) then
        raise exception 'Hanya kasir toko ini yang boleh hold stok POS.'
          using errcode = '42501';
      end if;
    elsif p_kind in ('DO_DRAFT', 'DO_PREPARING', 'RO') then
      if not public.can_manage_inventory_for_toko(v_toko) then
        raise exception 'Hanya admin gudang toko ini yang boleh booking stok.'
          using errcode = '42501';
      end if;
    end if;
    -- ONLINE_HOLD: checkout Member (RPC definers). Tenant sudah di-assert.
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

  select * into v_row from public.products where id = v_row.id for update;
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

create or replace function public.release_reservation(
  p_kind text,
  p_ref_type text,
  p_ref_id text,
  p_sku text default null,
  p_toko text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count integer := 0;
begin
  perform public.inventory_rpc_on();
  for r in
    select *
    from public.stock_reservations
    where status = 'active'
      and kind = p_kind
      and ref_type = p_ref_type
      and ref_id = p_ref_id
      and (p_sku is null or upper(trim(sku)) = upper(trim(p_sku)))
      and (p_toko is null or upper(trim(toko_id)) = upper(trim(p_toko)))
    for update
  loop
    if not public.toko_belongs_to_current_tenant(r.toko_id)
       and not public.is_platform_user() then
      raise exception 'Hold stok bukan milik usaha ini.' using errcode = '42501';
    end if;
    if auth.uid() is not null then
      if r.kind = 'POS_HOLD' then
        if not public.can_pos_checkout_for_toko(r.toko_id) then
          raise exception 'Hanya kasir toko ini yang boleh lepas hold.'
            using errcode = '42501';
        end if;
      elsif r.kind = 'ONLINE_HOLD' then
        null; -- Member batal pesanan / expire. Tenant sudah dicek.
      elsif not public.can_manage_inventory_for_toko(r.toko_id) then
        raise exception 'Hanya admin toko ini yang boleh lepas booking.'
          using errcode = '42501';
      end if;
    end if;
    update public.stock_reservations
    set status = 'released', updated_at = now()
    where id = r.id;
    perform public.recompute_product_reserved_qty(r.toko_id, r.sku);
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'released', v_count);
end;
$$;

create or replace function public.consume_reservation_and_transfer_out(
  p_kind text,
  p_ref_type text,
  p_ref_id text,
  p_toko text,
  p_alasan_text text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_ledger_ref_type text default null,
  p_ledger_ref_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_out jsonb;
  v_results jsonb := '[]'::jsonb;
  v_toko text := upper(trim(p_toko));
begin
  perform public.inventory_rpc_on();
  perform public.assert_toko_in_caller_tenant(v_toko);
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko(v_toko) then
    raise exception 'Hanya admin gudang toko asal yang boleh kirim TRANSIT.'
      using errcode = '42501';
  end if;

  for r in
    select *
    from public.stock_reservations
    where status = 'active'
      and kind = p_kind
      and ref_type = p_ref_type
      and ref_id = p_ref_id
      and upper(trim(toko_id)) = v_toko
    for update
  loop
    update public.stock_reservations
    set status = 'consumed', updated_at = now()
    where id = r.id;
    perform public.recompute_product_reserved_qty(r.toko_id, r.sku);
    v_out := public.apply_stock_delta(
      r.toko_id,
      r.sku,
      -r.qty,
      'TRANSFER_OUT',
      coalesce(p_alasan_text, 'Consume reservation → TRANSIT'),
      coalesce(p_ledger_ref_type, p_ref_type),
      coalesce(p_ledger_ref_id, p_ref_id),
      p_actor_id,
      p_actor_nama,
      jsonb_build_object('reservation_id', r.id, 'kind', p_kind),
      false
    );
    v_results := v_results || jsonb_build_array(v_out);
  end loop;

  return jsonb_build_object('ok', true, 'items', v_results);
end;
$$;

create or replace function public.recognize_stock_variance(
  p_toko text,
  p_sku text,
  p_alasan_text text,
  p_actor_id uuid default null,
  p_actor_nama text default null
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
  v_ledger_sum integer := 0;
  v_delta integer;
  v_ledger_id uuid;
begin
  perform public.assert_toko_in_caller_tenant(v_toko);
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko(v_toko) then
    raise exception 'Hanya admin toko ini yang boleh rekognisi selisih stok.'
      using errcode = '42501';
  end if;
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  if p_alasan_text is null or trim(p_alasan_text) = '' then
    raise exception 'Alasan wajib diisi';
  end if;

  select * into v_row
  from public.products
  where upper(trim(sku)) = upper(v_sku)
    and upper(trim(toko_id)) = v_toko
  for update;
  if not found then
    raise exception 'Produk % tidak ada di %', v_sku, v_toko;
  end if;

  select coalesce(sum(qty_delta), 0) into v_ledger_sum
  from public.product_stock_ledger
  where upper(trim(sku)) = upper(trim(v_row.sku))
    and upper(trim(toko_id)) = v_toko;

  v_delta := coalesce(v_row.stock, 0) - v_ledger_sum;
  if v_delta = 0 then
    return jsonb_build_object('ok', true, 'changed', false, 'message', 'Sudah sinkron');
  end if;

  insert into public.product_stock_ledger (
    sku, toko_id, product_id, qty_delta, stock_before, stock_after,
    reason, alasan_text, ref_type, actor_id, actor_nama, meta
  ) values (
    v_row.sku, v_toko, v_row.id, v_delta,
    coalesce(v_row.stock, 0), coalesce(v_row.stock, 0),
    'ADJUST',
    'Rekognisi selisih kebocoran (stok tidak diubah): ' || trim(p_alasan_text),
    'integrity_fix',
    p_actor_id, p_actor_nama,
    jsonb_build_object(
      'recognize_only', true,
      'stock', v_row.stock,
      'ledger_before', v_ledger_sum,
      'delta', v_delta
    )
  )
  returning id into v_ledger_id;

  return jsonb_build_object(
    'ok', true,
    'changed', true,
    'ledger_id', v_ledger_id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'stock', v_row.stock,
    'ledger_before', v_ledger_sum,
    'ledger_after', v_ledger_sum + v_delta,
    'qty_delta', v_delta
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Mesin status DO/RO
-- -----------------------------------------------------------------------------
create or replace function public.stock_move_status_ok(p_old text, p_new text)
returns boolean
language sql
immutable
as $$
  select
    case
      when upper(trim(coalesce(p_old, ''))) = upper(trim(coalesce(p_new, '')))
        then true
      when upper(trim(coalesce(p_new, ''))) in ('BATAL', 'REJECTED')
        and upper(trim(coalesce(p_old, ''))) not in ('SUCCESS')
        then true
      when upper(trim(coalesce(p_old, ''))) in ('SUCCESS', 'BATAL', 'REJECTED')
        then false
      when upper(trim(coalesce(p_old, ''))) in ('PREPARING', 'WAITING')
        and upper(trim(coalesce(p_new, ''))) in ('TRANSIT', 'PENDING')
        then true
      when upper(trim(coalesce(p_old, ''))) in ('TRANSIT', 'PENDING')
        and upper(trim(coalesce(p_new, ''))) = 'SUCCESS'
        then true
      else false
    end;
$$;

create or replace function public.stock_move_history_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dari text;
  v_ke text;
begin
  if tg_op = 'DELETE' then
    if not public.can_manage_inventory_for_toko(old.dari_lokasi)
       and not public.is_platform_user() then
      raise exception 'Hanya admin gudang asal yang boleh hapus surat jalan.'
        using errcode = '42501';
    end if;
    if upper(trim(coalesce(old.status, ''))) = 'SUCCESS' then
      raise exception 'Surat jalan SUCCESS tidak boleh dihapus.'
        using errcode = '42501';
    end if;
    return old;
  end if;

  v_dari := upper(trim(coalesce(new.dari_lokasi, '')));
  v_ke := upper(trim(coalesce(new.ke_lokasi, '')));
  if v_dari = '' or v_ke = '' then
    raise exception 'dari_lokasi dan ke_lokasi wajib.' using errcode = '42501';
  end if;
  if not public.toko_belongs_to_current_tenant(v_dari)
     or not public.toko_belongs_to_current_tenant(v_ke) then
    raise exception 'Surat jalan harus toko usaha ini.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if auth.uid() is not null
       and not public.can_manage_inventory_for_toko(v_dari) then
      raise exception 'Hanya admin gudang asal yang boleh buat surat jalan.'
        using errcode = '42501';
    end if;
    if upper(trim(coalesce(new.status, ''))) in ('SUCCESS') then
      raise exception 'Tidak boleh insert surat jalan langsung SUCCESS.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if old.dari_lokasi is distinct from new.dari_lokasi
     or old.ke_lokasi is distinct from new.ke_lokasi then
    raise exception 'Asal/tujuan surat jalan tidak boleh dipindah.'
      using errcode = '42501';
  end if;
  if old.product_name is distinct from new.product_name then
    raise exception 'Nomor resi tidak boleh diganti.' using errcode = '42501';
  end if;

  if not public.stock_move_status_ok(old.status, new.status) then
    raise exception
      'Status surat jalan tidak boleh lompat / dibuka ulang.'
      using errcode = '42501';
  end if;

  if upper(trim(coalesce(new.status, ''))) in ('TRANSIT', 'PENDING', 'SUCCESS')
     and (
       coalesce(old.keterangan, '') is distinct from coalesce(new.keterangan, '')
       or coalesce(old.jumlah, 0) is distinct from coalesce(new.jumlah, 0)
     ) then
    raise exception 'Item surat jalan terkunci setelah dikirim.'
      using errcode = '42501';
  end if;

  if upper(trim(coalesce(new.status, ''))) = 'TRANSIT'
     and upper(trim(coalesce(old.status, ''))) is distinct from 'TRANSIT' then
    if auth.uid() is not null
       and not public.can_manage_inventory_for_toko(v_dari) then
      raise exception 'Cabang tujuan tidak boleh jemput / potong stok Pusat.'
        using errcode = '42501';
    end if;
  end if;

  if upper(trim(coalesce(new.status, ''))) = 'SUCCESS'
     and upper(trim(coalesce(old.status, ''))) is distinct from 'SUCCESS' then
    if auth.uid() is not null
       and not public.can_receive_stock_for_toko(v_ke) then
      raise exception 'Hanya admin toko tujuan yang boleh terima barang.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_stock_move_history_guard on public.stock_move_history;
create trigger trg_stock_move_history_guard
  before insert or update or delete on public.stock_move_history
  for each row
  execute function public.stock_move_history_guard();

create or replace function public.pending_requests_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_new text;
begin
  if tg_op = 'DELETE' then
    if not public.can_manage_inventory_for_toko(old.toko_id)
       and not public.can_request_ro_for_toko(old.toko_id) then
      raise exception 'Tidak boleh hapus RO toko lain.' using errcode = '42501';
    end if;
    if upper(trim(coalesce(old.status, ''))) in ('SUCCESS', 'SHIPPING')
       and not public.is_platform_user() then
      raise exception 'RO yang sudah jalan/selesai tidak boleh dihapus.'
        using errcode = '42501';
    end if;
    return old;
  end if;

  if new.toko_id is null or trim(new.toko_id) = '' then
    raise exception 'toko_id RO wajib.' using errcode = '42501';
  end if;
  if not public.toko_belongs_to_current_tenant(new.toko_id) then
    raise exception 'RO harus toko usaha ini.' using errcode = '42501';
  end if;
  new.qty_request := least(999, greatest(1, coalesce(new.qty_request, 1)));

  if tg_op = 'INSERT' then
    if auth.uid() is not null
       and not public.can_request_ro_for_toko(new.toko_id) then
      raise exception 'Hanya kasir/admin toko ini yang boleh ajukan RO.'
        using errcode = '42501';
    end if;
    if upper(trim(coalesce(new.status, ''))) not in (
      'PENDING', 'SENT_TO_HQ'
    ) then
      raise exception 'RO baru hanya PENDING / SENT_TO_HQ.' using errcode = '42501';
    end if;
    return new;
  end if;

  if old.toko_id is distinct from new.toko_id then
    raise exception 'toko_id RO tidak boleh dipindah.' using errcode = '42501';
  end if;
  if coalesce(new.qty_request, 0) > coalesce(old.qty_request, 0)
     and upper(trim(coalesce(old.status, ''))) not in ('PENDING', 'SENT_TO_HQ') then
    raise exception 'Qty RO tidak boleh ditambah setelah diproses.'
      using errcode = '42501';
  end if;

  v_old := upper(trim(coalesce(old.status, '')));
  v_new := upper(trim(coalesce(new.status, '')));
  if v_old is distinct from v_new then
    if v_old = 'SUCCESS' then
      raise exception 'RO selesai tidak boleh dibuka ulang.' using errcode = '42501';
    end if;
    if v_new in ('PREPARING', 'APPROVED', 'SHIPPING', 'REJECTED')
       and not public.can_manage_inventory_for_toko('PUSAT')
       and not public.can_manage_inventory_for_toko(new.toko_id)
       and auth.uid() is not null then
      -- Pusat proses RO; cabang hanya terima SUCCESS via markSuccess.
      if v_new <> 'SUCCESS' then
        if not public.can_manage_inventory_for_toko('PUSAT') then
          raise exception 'Hanya gudang Pusat yang boleh proses RO.'
            using errcode = '42501';
        end if;
      end if;
    end if;
    if v_new = 'SUCCESS'
       and auth.uid() is not null
       and not public.can_receive_stock_for_toko(new.toko_id)
       and not public.can_manage_inventory_for_toko('PUSAT') then
      raise exception 'Hanya admin toko tujuan yang boleh closing RO.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_pending_requests_guard on public.pending_requests;
create trigger trg_pending_requests_guard
  before insert or update or delete on public.pending_requests
  for each row
  execute function public.pending_requests_guard();

create or replace function public.draft_pengiriman_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if not public.can_manage_inventory_for_toko('PUSAT') then
      raise exception 'Hanya gudang Pusat yang boleh hapus draft kirim.'
        using errcode = '42501';
    end if;
    return old;
  end if;
  if not public.toko_belongs_to_current_tenant(new.tujuan)
     and new.tujuan is not null then
    raise exception 'Draft kirim harus tujuan usaha ini.' using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko('PUSAT') then
    raise exception 'Hanya gudang Pusat yang boleh draft pengiriman.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_draft_pengiriman_guard on public.draft_pengiriman;
create trigger trg_draft_pengiriman_guard
  before insert or update or delete on public.draft_pengiriman
  for each row
  execute function public.draft_pengiriman_guard();

-- -----------------------------------------------------------------------------
-- RLS: buang using(true)
-- -----------------------------------------------------------------------------
drop policy if exists pending_requests_authenticated_all on public.pending_requests;
drop policy if exists pending_requests_select on public.pending_requests;
drop policy if exists pending_requests_insert on public.pending_requests;
drop policy if exists pending_requests_update on public.pending_requests;
drop policy if exists pending_requests_delete on public.pending_requests;

create policy pending_requests_select on public.pending_requests
  for select to authenticated
  using (
    public.toko_belongs_to_current_tenant(toko_id)
    and (
      public.can_manage_inventory_for_toko(toko_id)
      or public.can_request_ro_for_toko(toko_id)
      or public.can_manage_inventory_for_toko('PUSAT')
    )
  );

create policy pending_requests_insert on public.pending_requests
  for insert to authenticated
  with check (public.can_request_ro_for_toko(toko_id));

create policy pending_requests_update on public.pending_requests
  for update to authenticated
  using (
    public.can_request_ro_for_toko(toko_id)
    or public.can_manage_inventory_for_toko('PUSAT')
    or public.can_receive_stock_for_toko(toko_id)
  )
  with check (
    public.can_request_ro_for_toko(toko_id)
    or public.can_manage_inventory_for_toko('PUSAT')
    or public.can_receive_stock_for_toko(toko_id)
  );

create policy pending_requests_delete on public.pending_requests
  for delete to authenticated
  using (
    public.can_request_ro_for_toko(toko_id)
    or public.can_manage_inventory_for_toko('PUSAT')
  );

drop policy if exists stock_move_history_authenticated_all on public.stock_move_history;
drop policy if exists stock_move_history_select on public.stock_move_history;
drop policy if exists stock_move_history_insert on public.stock_move_history;
drop policy if exists stock_move_history_update on public.stock_move_history;
drop policy if exists stock_move_history_delete on public.stock_move_history;

create policy stock_move_history_select on public.stock_move_history
  for select to authenticated
  using (
    public.toko_belongs_to_current_tenant(dari_lokasi)
    or public.toko_belongs_to_current_tenant(ke_lokasi)
  );

create policy stock_move_history_insert on public.stock_move_history
  for insert to authenticated
  with check (public.can_manage_inventory_for_toko(dari_lokasi));

create policy stock_move_history_update on public.stock_move_history
  for update to authenticated
  using (
    public.can_manage_inventory_for_toko(dari_lokasi)
    or public.can_receive_stock_for_toko(ke_lokasi)
  )
  with check (
    public.can_manage_inventory_for_toko(dari_lokasi)
    or public.can_receive_stock_for_toko(ke_lokasi)
  );

create policy stock_move_history_delete on public.stock_move_history
  for delete to authenticated
  using (public.can_manage_inventory_for_toko(dari_lokasi));

drop policy if exists draft_pengiriman_authenticated_all on public.draft_pengiriman;
drop policy if exists draft_pengiriman_select on public.draft_pengiriman;
drop policy if exists draft_pengiriman_write on public.draft_pengiriman;

create policy draft_pengiriman_select on public.draft_pengiriman
  for select to authenticated
  using (
    public.can_manage_inventory_for_toko('PUSAT')
    or (
      tujuan is not null
      and public.can_manage_inventory_for_toko(tujuan)
    )
  );

create policy draft_pengiriman_write on public.draft_pengiriman
  for all to authenticated
  using (public.can_manage_inventory_for_toko('PUSAT'))
  with check (public.can_manage_inventory_for_toko('PUSAT'));

revoke all on function public.products_stock_guard() from public, anon;
revoke all on function public.stock_move_history_guard() from public, anon;
revoke all on function public.pending_requests_guard() from public, anon;
revoke all on function public.draft_pengiriman_guard() from public, anon;
revoke all on function public.stock_move_status_ok(text, text) from public, anon;

comment on function public.can_manage_inventory_for_toko(text) is
  'Mutasi stok: pusat semua toko tenant; admin_toko toko sendiri. Bukan owner etalase.';
