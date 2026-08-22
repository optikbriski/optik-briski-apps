-- =============================================================================
-- 000030 — Stok rusak / write-off end-to-end.
-- Apply di SQL Editor live SETELAH 000029.
--
-- Celah saat toko jalan (setelah 000026/000027):
-- - apply_stock_delta(WRITE_OFF, +qty) menambah stok sebagai "rusak"
-- - p_allow_create=true + WRITE_OFF positif = produk hantu + stok
-- - alasan cukup non-kosong (1 huruf) padahal UI minta 3 karakter
-- - actor_id/nama dari HP, bukan auth.uid()
-- - cabang A baca ledger WRITE_OFF cabang B (tenant-wide SELECT)
-- =============================================================================

create or replace function public.write_off_rpc_on()
returns void
language plpgsql
as $$
begin
  perform set_config('app.write_off_rpc', '1', true);
  perform public.inventory_rpc_on();
end;
$$;

comment on function public.write_off_rpc_on() is
  'GUC internal. Hanya write_off_stock yang boleh nyalakan.';

revoke all on function public.write_off_rpc_on() from public, anon, authenticated;
grant execute on function public.write_off_rpc_on() to service_role;

create or replace function public.can_view_product_stock_ledger(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.toko_belongs_to_current_tenant(p_toko)
    and (
      public.is_platform_user()
      or public.is_pusat_logistics_operator()
      or public.is_owner_role()
      or (
        public.current_profile_role() in (
          'admin_toko', 'admin_pusat', 'super_admin', 'kasir'
        )
        and public.same_store_toko(
          public.current_profile_toko_id(),
          p_toko
        )
      )
    );
$$;

comment on function public.can_view_product_stock_ledger(text) is
  'Baca jejak stok: operator/owner semua cabang tenant; admin_toko/kasir toko sendiri. Bukan merek lain.';

revoke all on function public.can_view_product_stock_ledger(text)
  from public, anon;
grant execute on function public.can_view_product_stock_ledger(text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- WRITE_OFF hanya lewat write_off_stock (qty selalu potong, tidak create SKU)
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
  v_actor uuid;
  v_nama text;
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
  if p_reason = 'ADJUST'
     and (p_alasan_text is null or trim(p_alasan_text) = '') then
    raise exception 'alasan_text wajib untuk ADJUST';
  end if;
  if p_reason = 'WRITE_OFF'
     and (p_alasan_text is null or length(trim(p_alasan_text)) < 3) then
    raise exception 'Alasan write-off minimal 3 karakter.';
  end if;

  v_jwt := coalesce(auth.jwt() ->> 'role', '');
  if p_reason in ('TRANSFER_IN', 'RETURN_IN')
     and current_setting('app.do_receive_rpc', true) is distinct from '1'
     and v_jwt is distinct from 'service_role' then
    raise exception
      'Terima stok hanya lewat surat jalan (receive_stock_move).'
      using errcode = '42501';
  end if;

  if p_reason = 'WRITE_OFF' then
    if current_setting('app.write_off_rpc', true) is distinct from '1'
       and v_jwt is distinct from 'service_role' then
      raise exception 'Stok rusak hanya lewat write_off_stock.'
        using errcode = '42501';
    end if;
    if p_qty_delta >= 0 then
      raise exception 'WRITE_OFF hanya boleh mengurangi stok.'
        using errcode = '42501';
    end if;
    if coalesce(p_allow_create, false) then
      raise exception 'WRITE_OFF tidak boleh membuat produk baru.'
        using errcode = '42501';
    end if;
  end if;

  if auth.uid() is not null then
    if p_reason = 'SALE' then
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

  if p_allow_create and p_reason is distinct from 'WRITE_OFF' then
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

  v_actor := p_actor_id;
  v_nama := p_actor_nama;
  if p_reason = 'WRITE_OFF' and auth.uid() is not null then
    v_actor := auth.uid();
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
    p_reason, p_alasan_text, p_ref_type, p_ref_id, v_actor, v_nama,
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

revoke all on function public.apply_stock_delta(
  text, text, integer, text, text, text, text, uuid, text, jsonb, boolean
) from public, anon;
grant execute on function public.apply_stock_delta(
  text, text, integer, text, text, text, text, uuid, text, jsonb, boolean
) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Pintu resmi: qty > 0 → selalu −qty. Tidak create SKU. Actor = login.
-- -----------------------------------------------------------------------------
create or replace function public.write_off_stock(
  p_toko text,
  p_sku text,
  p_qty integer,
  p_alasan text,
  p_actor_nama text default null,
  p_ref_id text default null,
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
  v_alasan text := trim(coalesce(p_alasan, ''));
  v_actor uuid;
  v_nama text;
  v_ref text;
  v_jwt text;
begin
  perform public.write_off_rpc_on();
  v_jwt := coalesce(auth.jwt() ->> 'role', '');
  v_actor := auth.uid();
  if v_actor is null and v_jwt is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Qty rusak harus lebih dari 0.';
  end if;
  if length(v_alasan) < 3 then
    raise exception 'Alasan write-off minimal 3 karakter.';
  end if;
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib untuk write-off.';
  end if;
  perform public.assert_toko_in_caller_tenant(v_toko);
  if v_actor is not null
     and not public.can_manage_inventory_for_toko(v_toko) then
    raise exception 'Hanya admin toko/cabang ini yang boleh catat stok rusak.'
      using errcode = '42501';
  end if;

  if v_actor is not null then
    select nullif(trim(coalesce(nama, email, '')), '')
      into v_nama
    from public.profiles
    where id = v_actor;
  end if;
  v_nama := coalesce(
    nullif(trim(coalesce(p_actor_nama, '')), ''),
    v_nama,
    ''
  );

  v_ref := nullif(trim(coalesce(p_ref_id, '')), '');
  if v_ref is null then
    v_ref := 'WO-' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
  end if;

  return public.apply_stock_delta(
    v_toko,
    v_sku,
    -p_qty,
    'WRITE_OFF',
    v_alasan,
    'write_off',
    v_ref,
    v_actor,
    v_nama,
    coalesce(p_meta, '{}'::jsonb),
    false
  );
end;
$$;

comment on function public.write_off_stock(text, text, integer, text, text, text, jsonb) is
  'Potong stok rusak. Qty selalu negatif. Bukan nambah stok. Bukan create SKU.';

revoke all on function public.write_off_stock(
  text, text, integer, text, text, text, jsonb
) from public, anon;
grant execute on function public.write_off_stock(
  text, text, integer, text, text, text, jsonb
) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Ledger: cabang tidak baca jejak cabang lain
-- -----------------------------------------------------------------------------
drop policy if exists product_stock_ledger_select
  on public.product_stock_ledger;

create policy product_stock_ledger_select on public.product_stock_ledger
  for select to authenticated
  using (public.can_view_product_stock_ledger(toko_id));
