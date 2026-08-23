-- =============================================================================
-- 000045 — Request Order: antrian terbuka tidak boleh hilang.
-- Apply di SQL Editor live SETELAH 000044.
--
-- Celah saat toko proses RO:
-- - Flutter .limit(300) memotong SENT_TO_HQ / PREPARING / SHIPPING
-- - int.tryParse id/qty JSON `123.0` / `2.0` jadi 0
-- - send_request_orders_to_hq banding toko exact (PUSAT ≠ CABANG-PUSAT)
-- - RPC belum kunci anon
-- =============================================================================

create or replace function public.send_request_orders_to_hq(
  p_toko text,
  p_ids bigint[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_n int := 0;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if auth.uid() is null
     and coalesce(auth.jwt() ->> 'role', '') is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  perform public.assert_toko_in_caller_tenant(v_toko);
  if auth.uid() is not null
     and not public.can_request_ro_for_toko(v_toko) then
    raise exception 'Hanya kasir/admin toko ini yang boleh kirim RO ke Pusat.'
      using errcode = '42501';
  end if;
  if p_ids is null or array_length(p_ids, 1) is null then
    return 0;
  end if;

  update public.pending_requests
  set
    status = 'SENT_TO_HQ',
    tracking_status = 'MENUNGGU_APPROVAL'
  where public.same_store_toko(toko_id, v_toko)
    and status = 'PENDING'
    and id = any (p_ids);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

comment on function public.send_request_orders_to_hq(text, bigint[]) is
  'Cabang kirim antrian PENDING → SENT_TO_HQ. Bukan approve. Bukan anon.';

revoke all on function public.send_request_orders_to_hq(text, bigint[])
  from public, anon;
grant execute on function public.send_request_orders_to_hq(text, bigint[])
  to authenticated, service_role;

create or replace function public.approve_request_order(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.pending_requests;
  v_st text;
  v_sku text;
  v_qty int;
  v_prod public.products;
  v_tenant uuid;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.ro_rpc_on();
  if auth.uid() is null
     and coalesce(auth.jwt() ->> 'role', '') is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko('PUSAT') then
    raise exception 'Hanya gudang Pusat yang boleh setujui RO.'
      using errcode = '42501';
  end if;

  select * into v_row
  from public.pending_requests
  where id = p_id
  for update;
  if not found then
    raise exception 'RO tidak ditemukan.' using errcode = '42501';
  end if;
  perform public.assert_toko_in_caller_tenant(v_row.toko_id);
  v_st := upper(trim(coalesce(v_row.status, '')));
  if v_st not in ('PENDING', 'SENT_TO_HQ', 'APPROVED') then
    raise exception 'Hanya RO antrian/approval yang bisa disiapkan.';
  end if;
  v_qty := least(999, greatest(1, coalesce(v_row.qty_request, 1)));
  v_tenant := public.current_tenant_id();

  select * into v_prod
  from public.products
  where tenant_id is not distinct from v_tenant
    and upper(trim(toko_id)) = 'PUSAT'
    and (
      (nullif(trim(coalesce(v_row.sku, '')), '') is not null
       and upper(trim(sku)) = upper(trim(v_row.sku)))
      or (
        nullif(trim(coalesce(v_row.sku, '')), '') is null
        and nullif(trim(coalesce(v_row.nama_produk, '')), '') is not null
        and lower(trim(nama)) = lower(trim(v_row.nama_produk))
      )
    )
  for update;
  if not found then
    raise exception 'Produk tidak ditemukan di stok Pusat.';
  end if;
  v_sku := trim(v_prod.sku);

  if v_st is distinct from 'APPROVED' or coalesce(v_row.reserved_qty, 0) <= 0 then
    perform public.reserve_stock(
      'PUSAT', v_sku, v_qty, 'RO', 'pending_request', p_id::text,
      jsonb_build_object('nama', v_prod.nama)
    );
  end if;

  update public.pending_requests
  set
    status = 'PREPARING',
    tracking_status = 'DISIAPKAN',
    reserved_qty = v_qty,
    sku = v_sku,
    reviewed_at = now(),
    reviewed_by = auth.uid()
  where id = p_id;

  return jsonb_build_object(
    'ok', true,
    'id', p_id,
    'sku', v_sku,
    'status', 'PREPARING',
    'qty', v_qty
  );
end;
$$;

comment on function public.approve_request_order(bigint) is
  'Pusat reservasi stok + PREPARING. Bukan REST. Bukan anon.';

revoke all on function public.approve_request_order(bigint)
  from public, anon;
grant execute on function public.approve_request_order(bigint)
  to authenticated, service_role;

create or replace function public.reject_request_order(
  p_id bigint,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.pending_requests;
  v_st text;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.ro_rpc_on();
  if auth.uid() is null
     and coalesce(auth.jwt() ->> 'role', '') is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko('PUSAT') then
    raise exception 'Hanya gudang Pusat yang boleh tolak RO.'
      using errcode = '42501';
  end if;

  select * into v_row
  from public.pending_requests
  where id = p_id
  for update;
  if not found then
    raise exception 'RO tidak ditemukan.' using errcode = '42501';
  end if;
  v_st := upper(trim(coalesce(v_row.status, '')));
  if v_st not in ('PENDING', 'SENT_TO_HQ', 'APPROVED', 'PREPARING') then
    raise exception 'RO yang sudah jalan/selesai tidak bisa ditolak.';
  end if;
  perform public.assert_toko_in_caller_tenant(v_row.toko_id);
  perform public.release_reservation(
    'RO', 'pending_request', p_id::text, v_row.sku, 'PUSAT'
  );

  update public.pending_requests
  set
    status = 'REJECTED',
    tracking_status = 'DITOLAK',
    reserved_qty = 0,
    reviewed_at = now(),
    reviewed_by = auth.uid(),
    detail_resep = case
      when nullif(trim(coalesce(p_note, '')), '') is null then detail_resep
      else trim(p_note)
    end
  where id = p_id;

  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'REJECTED');
end;
$$;

comment on function public.reject_request_order(bigint, text) is
  'Pusat lepas reservasi + REJECTED. Bukan setelah SHIPPING. Bukan anon.';

revoke all on function public.reject_request_order(bigint, text)
  from public, anon;
grant execute on function public.reject_request_order(bigint, text)
  to authenticated, service_role;

create or replace function public.ship_request_order(
  p_id bigint,
  p_kurir_id text default null,
  p_kurir_nama text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.pending_requests;
  v_st text;
  v_sku text;
  v_qty int;
  v_prod public.products;
  v_tenant uuid;
  v_resi text;
  v_ket text;
  v_move uuid;
  v_items jsonb;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.ro_rpc_on();
  if auth.uid() is null
     and coalesce(auth.jwt() ->> 'role', '') is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko('PUSAT') then
    raise exception 'Hanya gudang Pusat yang boleh kirim RO.'
      using errcode = '42501';
  end if;

  select * into v_row
  from public.pending_requests
  where id = p_id
  for update;
  if not found then
    raise exception 'RO tidak ditemukan.' using errcode = '42501';
  end if;
  perform public.assert_toko_in_caller_tenant(v_row.toko_id);
  v_st := upper(trim(coalesce(v_row.status, '')));
  if v_st not in ('PREPARING', 'APPROVED') then
    raise exception 'Kirim hanya dari status Disiapkan.';
  end if;
  v_qty := least(999, greatest(1, coalesce(v_row.qty_request, 1)));
  v_tenant := public.current_tenant_id();

  select * into v_prod
  from public.products
  where tenant_id is not distinct from v_tenant
    and upper(trim(toko_id)) = 'PUSAT'
    and upper(trim(sku)) = upper(trim(coalesce(v_row.sku, '')))
  for update;
  if not found then
    raise exception 'Produk tidak ditemukan di stok Pusat.';
  end if;
  v_sku := trim(v_prod.sku);
  if coalesce(v_prod.stock, 0) < v_qty then
    raise exception
      'Stok real Pusat tidak cukup untuk dikirim (stok %, minta %).',
      v_prod.stock, v_qty;
  end if;

  v_resi := 'RO-' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_items := jsonb_build_array(
    jsonb_build_object(
      'nama', coalesce(v_prod.nama, v_row.nama_produk, '-'),
      'sku', v_sku,
      'barcode', coalesce(v_prod.barcode, v_sku),
      'qty', v_qty
    )
  );
  v_ket := format(
    'RequestOrder#%s | Invoice %s | %s',
    p_id,
    coalesce(v_row.no_invoice, '-'),
    v_items::text
  );

  insert into public.stock_move_history (
    product_name, dari_lokasi, ke_lokasi, jumlah, tipe, status, keterangan
  ) values (
    v_resi, 'PUSAT', upper(trim(v_row.toko_id)), v_qty,
    'REQUEST', 'PREPARING', v_ket
  )
  returning id into v_move;

  begin
    perform public.mark_stock_move_transit(
      v_move,
      nullif(trim(coalesce(p_kurir_id, '')), ''),
      nullif(trim(coalesce(p_kurir_nama, '')), ''),
      null
    );
  exception when others then
    delete from public.stock_move_history
    where id = v_move
      and upper(trim(coalesce(status, ''))) in ('PREPARING', 'WAITING');
    raise;
  end;

  update public.pending_requests
  set
    status = 'SHIPPING',
    tracking_status = 'DALAM_PERJALANAN',
    reserved_qty = 0,
    stock_move_id = v_move,
    stock_move_resi = v_resi,
    sku = v_sku
  where id = p_id;

  return jsonb_build_object(
    'ok', true,
    'id', p_id,
    'resi', v_resi,
    'stock_move_id', v_move,
    'status', 'SHIPPING'
  );
end;
$$;

comment on function public.ship_request_order(bigint, text, text) is
  'Kirim RO: reservasi → TRANSFER_OUT + surat jalan. Bukan REST. Bukan anon.';

revoke all on function public.ship_request_order(bigint, text, text)
  from public, anon;
grant execute on function public.ship_request_order(bigint, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Antrian RO terbuka — tanpa potong 300 baris REST
-- -----------------------------------------------------------------------------
create or replace function public.list_request_orders(
  p_toko text default null,
  p_statuses text[] default null
)
returns setof public.pending_requests
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
  v_all boolean := false;
  v_st text[];
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_statuses is null or array_length(p_statuses, 1) is null then
    v_st := array[
      'PENDING', 'SENT_TO_HQ', 'APPROVED', 'PREPARING', 'SHIPPING'
    ];
  else
    select array_agg(upper(btrim(s)))
      into v_st
    from unnest(p_statuses) as s
    where nullif(btrim(s), '') is not null;
    if v_st is null then
      return;
    end if;
  end if;

  if v_toko is not null then
    perform public.assert_toko_in_caller_tenant(v_toko);
    if not public.can_request_ro_for_toko(v_toko)
       and not public.can_manage_inventory_for_toko('PUSAT') then
      raise exception 'Tidak berhak antrian RO toko ini.'
        using errcode = '42501';
    end if;
  elsif public.can_manage_inventory_for_toko('PUSAT') then
    v_all := true;
  else
    v_toko := nullif(
      upper(trim(coalesce(public.current_profile_toko_id(), ''))),
      ''
    );
    if v_toko is null or not public.can_request_ro_for_toko(v_toko) then
      raise exception 'Tidak berhak antrian RO.'
        using errcode = '42501';
    end if;
  end if;

  return query
  select r.*
  from public.pending_requests r
  where public.toko_belongs_to_current_tenant(r.toko_id)
    and upper(btrim(coalesce(r.status, ''))) = any (v_st)
    and (
      v_all
      or public.same_store_toko(r.toko_id, v_toko)
    )
  order by r.created_at asc;
end;
$$;

comment on function public.list_request_orders(text, text[]) is
  'Antrian RO terbuka. Bukan potong 300 REST. Bukan anon. Bukan merek lain.';

revoke all on function public.list_request_orders(text, text[])
  from public, anon;
grant execute on function public.list_request_orders(text, text[])
  to authenticated, service_role;
