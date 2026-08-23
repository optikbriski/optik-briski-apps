-- =============================================================================
-- 000039 — Delivery Order atomik: buat + booking satu transaksi.
-- Apply di SQL Editor live SETELAH 000038.
--
-- Celah saat toko jalan (setelah 000027–000033):
-- - INSERT surat + reserve_stock terpisah → crash di tengah
--   = cabang terima semua SKU, Pusat hanya potong sebagian
-- - qty JSON `2.0` pecah `::int` saat TRANSIT/terima
-- - EXECUTE PUBLIC: JWT anon bisa coba RPC DO
-- =============================================================================

create or replace function public.stock_move_item_qty(p_it jsonb)
returns integer
language plpgsql
immutable
as $$
declare
  v_n numeric;
begin
  begin
    v_n := nullif(btrim(coalesce(p_it->>'qty', '')), '')::numeric;
  exception when others then
    return 0;
  end;
  if v_n is null or v_n <= 0 then
    return 0;
  end if;
  return least(9999, greatest(1, floor(v_n)))::int;
end;
$$;

comment on function public.stock_move_item_qty(jsonb) is
  'Qty baris DO. JSON 2.0 / "2" tidak pecah.';

revoke all on function public.stock_move_item_qty(jsonb) from public, anon;
grant execute on function public.stock_move_item_qty(jsonb)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Buat DELIVERY PREPARING + DO_PREPARING atomik
-- -----------------------------------------------------------------------------
create or replace function public.create_delivery_stock_move(
  p_ke text,
  p_items jsonb,
  p_bukti_foto_pengirim text default null,
  p_resi text default null,
  p_actor text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ke text := upper(trim(coalesce(p_ke, '')));
  v_it jsonb;
  v_sku text;
  v_qty int;
  v_n int := 0;
  v_total int := 0;
  v_resi text;
  v_id uuid;
  v_foto text;
  v_meta jsonb;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.do_write_rpc_on();
  if v_ke = '' then
    raise exception 'Cabang tujuan wajib.' using errcode = '42501';
  end if;
  if public.is_pusat_warehouse(v_ke) then
    raise exception 'Surat jalan restock hanya ke cabang, bukan Pusat.'
      using errcode = '42501';
  end if;
  perform public.assert_toko_in_caller_tenant(v_ke);
  perform public.assert_toko_in_caller_tenant('PUSAT');
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko('PUSAT') then
    raise exception 'Hanya gudang Pusat yang boleh buat surat jalan.'
      using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) is distinct from 'array'
     or p_items = '[]'::jsonb then
    raise exception 'Item surat jalan wajib.' using errcode = '42501';
  end if;

  for v_it in select value from jsonb_array_elements(p_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    v_n := v_n + 1;
    v_total := v_total + v_qty;
  end loop;
  if v_n = 0 then
    raise exception 'Tidak ada item valid (SKU + qty).' using errcode = '42501';
  end if;

  v_resi := nullif(trim(coalesce(p_resi, '')), '');
  if v_resi is null then
    v_resi := 'DO-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  end if;
  v_foto := nullif(trim(coalesce(p_bukti_foto_pengirim, '')), '');
  if v_foto = '-' then
    v_foto := null;
  end if;

  insert into public.stock_move_history (
    product_name, dari_lokasi, ke_lokasi, jumlah, tipe, status,
    keterangan, bukti_foto_pengirim
  ) values (
    v_resi, 'PUSAT', v_ke, v_total, 'DELIVERY', 'PREPARING',
    p_items::text, v_foto
  )
  returning id into v_id;

  v_meta := jsonb_build_object(
    'resi', v_resi,
    'tujuan', v_ke,
    'actor', nullif(trim(coalesce(p_actor, '')), '')
  );

  for v_it in select value from jsonb_array_elements(p_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    perform public.reserve_stock(
      'PUSAT', v_sku, v_qty, 'DO_PREPARING', 'stock_move', v_id::text, v_meta
    );
  end loop;

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'resi', v_resi,
    'status', 'PREPARING',
    'jumlah', v_total
  );
end;
$$;

comment on function public.create_delivery_stock_move(text, jsonb, text, text, text) is
  'Buat DO PREPARING + booking Pending atomik. Bukan REST insert + reserve.';

revoke all on function public.create_delivery_stock_move(text, jsonb, text, text, text)
  from public, anon;
grant execute on function public.create_delivery_stock_move(text, jsonb, text, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Draf restock + booking DO_DRAFT atomik
-- -----------------------------------------------------------------------------
create or replace function public.create_delivery_draft(
  p_ke text,
  p_items jsonb,
  p_actor text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ke text := upper(trim(coalesce(p_ke, '')));
  v_it jsonb;
  v_sku text;
  v_qty int;
  v_n int := 0;
  v_id uuid;
  v_meta jsonb;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.do_write_rpc_on();
  if v_ke = '' or public.is_pusat_warehouse(v_ke) then
    raise exception 'Draf restock hanya ke cabang.' using errcode = '42501';
  end if;
  perform public.assert_toko_in_caller_tenant(v_ke);
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko('PUSAT') then
    raise exception 'Hanya gudang Pusat yang boleh draf pengiriman.'
      using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) is distinct from 'array'
     or p_items = '[]'::jsonb then
    raise exception 'Item draf wajib.' using errcode = '42501';
  end if;

  for v_it in select value from jsonb_array_elements(p_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'Tidak ada item draf valid.' using errcode = '42501';
  end if;

  insert into public.draft_pengiriman (tujuan, items)
  values (v_ke, p_items::text)
  returning id into v_id;

  v_meta := jsonb_build_object(
    'tujuan', v_ke,
    'actor', nullif(trim(coalesce(p_actor, '')), '')
  );

  for v_it in select value from jsonb_array_elements(p_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    perform public.reserve_stock(
      'PUSAT', v_sku, v_qty, 'DO_DRAFT', 'draft', v_id::text, v_meta
    );
  end loop;

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'tujuan', v_ke
  );
end;
$$;

comment on function public.create_delivery_draft(text, jsonb, text) is
  'Draf restock + booking Pending atomik.';

revoke all on function public.create_delivery_draft(text, jsonb, text)
  from public, anon;
grant execute on function public.create_delivery_draft(text, jsonb, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Promote draf → PREPARING atomik (lepas DO_DRAFT, book DO_PREPARING)
-- -----------------------------------------------------------------------------
create or replace function public.promote_delivery_draft(
  p_draft_id uuid,
  p_items jsonb default null,
  p_bukti_foto_pengirim text default null,
  p_resi text default null,
  p_actor text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tujuan text;
  v_raw text;
  v_items jsonb;
  v_it jsonb;
  v_sku text;
  v_qty int;
  v_n int := 0;
  v_total int := 0;
  v_resi text;
  v_id uuid;
  v_foto text;
  v_meta jsonb;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.do_write_rpc_on();
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko('PUSAT') then
    raise exception 'Hanya gudang Pusat yang boleh jadikan surat jalan.'
      using errcode = '42501';
  end if;

  select tujuan, items into v_tujuan, v_raw
  from public.draft_pengiriman
  where id = p_draft_id
  for update;
  if not found then
    raise exception 'Draf tidak ditemukan.' using errcode = '42501';
  end if;
  v_tujuan := upper(trim(coalesce(v_tujuan, '')));
  if v_tujuan = '' or public.is_pusat_warehouse(v_tujuan) then
    raise exception 'Tujuan draf tidak valid.' using errcode = '42501';
  end if;
  perform public.assert_toko_in_caller_tenant(v_tujuan);

  if p_items is not null and jsonb_typeof(p_items) = 'array'
     and p_items <> '[]'::jsonb then
    v_items := p_items;
  else
    v_items := public.stock_move_items_json(coalesce(v_raw, ''));
  end if;
  if v_items = '[]'::jsonb then
    raise exception 'Item draf kosong.' using errcode = '42501';
  end if;

  for v_it in select value from jsonb_array_elements(v_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    v_n := v_n + 1;
    v_total := v_total + v_qty;
  end loop;
  if v_n = 0 then
    raise exception 'Tidak ada item draf valid.' using errcode = '42501';
  end if;

  perform public.release_reservation(
    'DO_DRAFT', 'draft', p_draft_id::text, null, 'PUSAT'
  );

  v_resi := nullif(trim(coalesce(p_resi, '')), '');
  if v_resi is null then
    v_resi := 'DO-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  end if;
  v_foto := nullif(trim(coalesce(p_bukti_foto_pengirim, '')), '');
  if v_foto = '-' then
    v_foto := null;
  end if;

  insert into public.stock_move_history (
    product_name, dari_lokasi, ke_lokasi, jumlah, tipe, status,
    keterangan, bukti_foto_pengirim
  ) values (
    v_resi, 'PUSAT', v_tujuan, v_total, 'DELIVERY', 'PREPARING',
    v_items::text, v_foto
  )
  returning id into v_id;

  v_meta := jsonb_build_object(
    'resi', v_resi,
    'from_draft', p_draft_id::text,
    'actor', nullif(trim(coalesce(p_actor, '')), '')
  );

  for v_it in select value from jsonb_array_elements(v_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    perform public.reserve_stock(
      'PUSAT', v_sku, v_qty, 'DO_PREPARING', 'stock_move', v_id::text, v_meta
    );
  end loop;

  delete from public.draft_pengiriman where id = p_draft_id;

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'resi', v_resi,
    'status', 'PREPARING',
    'jumlah', v_total
  );
end;
$$;

comment on function public.promote_delivery_draft(uuid, jsonb, text, text, text) is
  'Draf → PREPARING + pindah booking atomik.';

revoke all on function public.promote_delivery_draft(uuid, jsonb, text, text, text)
  from public, anon;
grant execute on function public.promote_delivery_draft(uuid, jsonb, text, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Batal PREPARING + lepas booking
-- -----------------------------------------------------------------------------
create or replace function public.cancel_preparing_stock_move(p_move_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.stock_move_history;
  v_st text;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.do_write_rpc_on();
  select * into v_row
  from public.stock_move_history
  where id = p_move_id
  for update;
  if not found then
    raise exception 'Surat jalan tidak ditemukan.' using errcode = '42501';
  end if;
  v_st := upper(trim(coalesce(v_row.status, '')));
  if v_st in ('BATAL', 'REJECTED') then
    return jsonb_build_object(
      'ok', true, 'already_done', true, 'id', v_row.id, 'status', v_st
    );
  end if;
  if v_st not in ('PREPARING', 'WAITING', 'QUEUED') then
    raise exception 'Hanya surat yang belum dikirim yang boleh dibatalkan (status: %).', v_st
      using errcode = '42501';
  end if;
  perform public.assert_toko_in_caller_tenant(v_row.dari_lokasi);
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko(v_row.dari_lokasi) then
    raise exception 'Hanya gudang asal yang boleh batalkan surat jalan.'
      using errcode = '42501';
  end if;

  update public.stock_move_history
  set status = 'BATAL'
  where id = p_move_id;

  return jsonb_build_object(
    'ok', true,
    'already_done', false,
    'id', p_move_id,
    'status', 'BATAL'
  );
end;
$$;

comment on function public.cancel_preparing_stock_move(uuid) is
  'BATAL + lepas booking. Bukan REST PATCH terpisah.';

revoke all on function public.cancel_preparing_stock_move(uuid)
  from public, anon;
grant execute on function public.cancel_preparing_stock_move(uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- TRANSIT: potong sisa SKU keranjang jika booking parsial
-- -----------------------------------------------------------------------------
create or replace function public.mark_stock_move_transit(
  p_move_id uuid,
  p_kurir_id text default null,
  p_kurir_nama text default null,
  p_bukti_foto_kurir text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.stock_move_history;
  v_dari text;
  v_st text;
  v_tipe text;
  v_resi text;
  v_consumed jsonb;
  v_items jsonb;
  v_it jsonb;
  v_sku text;
  v_qty int;
  v_ro_id text;
  v_actor uuid;
  v_n int := 0;
  v_cut int := 0;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.do_transit_rpc_on();
  select * into v_row
  from public.stock_move_history
  where id = p_move_id
  for update;
  if not found then
    raise exception 'Surat jalan tidak ditemukan.' using errcode = '42501';
  end if;

  v_dari := upper(trim(coalesce(v_row.dari_lokasi, '')));
  v_st := upper(trim(coalesce(v_row.status, '')));
  v_tipe := upper(trim(coalesce(v_row.tipe, 'DELIVERY')));
  v_resi := coalesce(v_row.product_name, '');
  perform public.assert_toko_in_caller_tenant(v_dari);

  if v_st = 'TRANSIT' then
    return jsonb_build_object(
      'ok', true,
      'already_transit', true,
      'id', v_row.id,
      'resi', v_resi,
      'status', 'TRANSIT'
    );
  end if;
  if v_st not in ('PREPARING', 'WAITING') then
    raise exception 'Hanya PREPARING yang boleh jadi TRANSIT (status: %).', v_st
      using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko(v_dari) then
    raise exception 'Hanya admin gudang asal yang boleh kirim TRANSIT.'
      using errcode = '42501';
  end if;

  if v_tipe = 'DELIVERY'
     and (
       nullif(trim(coalesce(v_row.bukti_foto_pengirim, '')), '') is null
       or trim(v_row.bukti_foto_pengirim) = '-'
     ) then
    raise exception
      'Foto packing belum ada. Gudang harus foto dulu di halaman Disiapkan.'
      using errcode = '42501';
  end if;

  begin
    v_actor := nullif(trim(coalesce(p_kurir_id, '')), '')::uuid;
  exception when others then
    v_actor := auth.uid();
  end;

  v_consumed := public.consume_reservation_and_transfer_out(
    'DO_PREPARING',
    'stock_move',
    p_move_id::text,
    v_dari,
    'DO ' || v_resi || ' → TRANSIT',
    v_actor,
    nullif(trim(coalesce(p_kurir_nama, '')), ''),
    'stock_move',
    p_move_id::text
  );
  v_n := jsonb_array_length(coalesce(v_consumed->'items', '[]'::jsonb));

  if v_n = 0 and v_tipe = 'REQUEST' then
    v_ro_id := public.stock_move_ro_id(v_row.keterangan);
    if v_ro_id is not null then
      v_consumed := public.consume_reservation_and_transfer_out(
        'RO',
        'pending_request',
        v_ro_id,
        v_dari,
        'RO ' || v_resi || ' → TRANSIT',
        v_actor,
        nullif(trim(coalesce(p_kurir_nama, '')), ''),
        'stock_move',
        p_move_id::text
      );
      v_n := jsonb_array_length(coalesce(v_consumed->'items', '[]'::jsonb));
    end if;
  end if;

  -- Rekonsiliasi keranjang: SKU yang belum TRANSFER_OUT tetap dipotong
  -- (booking parsial / crash sebelum 000039).
  v_items := public.stock_move_items_json(v_row.keterangan);
  if v_items = '[]'::jsonb and v_n = 0 then
    raise exception 'Surat jalan tanpa item/SKU tidak bisa dikirim.'
      using errcode = '42501';
  end if;
  for v_it in select value from jsonb_array_elements(v_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    if exists (
      select 1
      from public.product_stock_ledger l
      where l.ref_type = 'stock_move'
        and l.ref_id = p_move_id::text
        and upper(trim(l.sku)) = upper(v_sku)
        and l.reason = 'TRANSFER_OUT'
        and l.qty_delta < 0
    ) then
      v_cut := v_cut + 1;
      continue;
    end if;
    perform public.apply_stock_delta(
      v_dari, v_sku, -v_qty, 'TRANSFER_OUT',
      v_tipe || ' ' || v_resi || ' → TRANSIT',
      'stock_move', p_move_id::text,
      v_actor, nullif(trim(coalesce(p_kurir_nama, '')), ''),
      jsonb_build_object('product', v_it),
      false
    );
    v_cut := v_cut + 1;
  end loop;
  if v_cut = 0 and v_n = 0 then
    raise exception 'Tidak ada item valid untuk dipotong saat TRANSIT.'
      using errcode = '42501';
  end if;

  update public.stock_move_history
  set
    status = 'TRANSIT',
    kurir_karyawan_id = case
      when v_row.kurir_karyawan_id is null
           and nullif(trim(coalesce(p_kurir_id, '')), '') is not null
        then
          case
            when p_kurir_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then p_kurir_id::uuid
            else v_row.kurir_karyawan_id
          end
      else v_row.kurir_karyawan_id
    end,
    kurir_nama = case
      when coalesce(v_row.kurir_nama, '') = ''
           and nullif(trim(coalesce(p_kurir_nama, '')), '') is not null
        then trim(p_kurir_nama)
      else v_row.kurir_nama
    end,
    bukti_foto_kurir = coalesce(
      nullif(trim(coalesce(p_bukti_foto_kurir, '')), ''),
      v_row.bukti_foto_kurir
    )
  where id = p_move_id;

  return jsonb_build_object(
    'ok', true,
    'already_transit', false,
    'id', p_move_id,
    'resi', v_resi,
    'status', 'TRANSIT',
    'cut_count', greatest(v_n, v_cut)
  );
end;
$$;

revoke all on function public.mark_stock_move_transit(uuid, text, text, text)
  from public, anon;
grant execute on function public.mark_stock_move_transit(uuid, text, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Terima: qty JSON aman + anon dikunci
-- -----------------------------------------------------------------------------
create or replace function public.receive_stock_move(
  p_move_id uuid,
  p_verified_by text default null,
  p_verified_by_name text default null,
  p_bukti_foto_penerima text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.stock_move_history;
  v_ke text;
  v_st text;
  v_tipe text;
  v_resi text;
  v_reason text;
  v_items jsonb;
  v_it jsonb;
  v_sku text;
  v_qty int;
  v_n int := 0;
  v_actor uuid;
  v_name text;
  v_foto text;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.do_receive_rpc_on();
  select * into v_row
  from public.stock_move_history
  where id = p_move_id
  for update;
  if not found then
    raise exception 'Surat jalan tidak ditemukan.' using errcode = '42501';
  end if;

  v_ke := upper(trim(coalesce(v_row.ke_lokasi, '')));
  v_st := upper(trim(coalesce(v_row.status, '')));
  v_tipe := upper(trim(coalesce(v_row.tipe, 'DELIVERY')));
  v_resi := coalesce(v_row.product_name, '');
  perform public.assert_toko_in_caller_tenant(v_ke);

  if v_st = 'SUCCESS' then
    return jsonb_build_object(
      'ok', true,
      'already_done', true,
      'id', v_row.id,
      'resi', v_resi,
      'status', 'SUCCESS',
      'verified_by_name', v_row.verified_by_name,
      'verified_at', v_row.verified_at
    );
  end if;
  if v_st not in ('TRANSIT', 'PENDING') then
    raise exception
      'Paket masih %. Kurir harus TRANSIT dulu sebelum diterima.', v_st
      using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_receive_stock_for_toko(v_ke) then
    raise exception 'Hanya admin toko tujuan yang boleh terima barang.'
      using errcode = '42501';
  end if;

  v_foto := nullif(trim(coalesce(
    p_bukti_foto_penerima, v_row.bukti_foto_penerima, ''
  )), '');
  if v_foto is null or v_foto = '-' then
    raise exception 'Foto terima wajib sebelum stok masuk.'
      using errcode = '42501';
  end if;

  v_reason := case
    when v_tipe = 'RETUR' or v_resi ilike 'RET-%' then 'RETURN_IN'
    else 'TRANSFER_IN'
  end;
  v_items := public.stock_move_items_json(v_row.keterangan);
  if v_items = '[]'::jsonb then
    raise exception 'Paket tanpa detail SKU tidak bisa diterima.'
      using errcode = '42501';
  end if;

  v_actor := auth.uid();
  v_name := nullif(trim(coalesce(p_verified_by_name, '')), '');

  for v_it in select value from jsonb_array_elements(v_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    if exists (
      select 1
      from public.product_stock_ledger l
      where l.ref_type = 'stock_move'
        and l.ref_id = p_move_id::text
        and upper(trim(l.sku)) = upper(v_sku)
        and l.reason in ('TRANSFER_IN', 'RETURN_IN')
        and l.qty_delta > 0
    ) then
      v_n := v_n + 1;
      continue;
    end if;
    perform public.apply_stock_delta(
      v_ke, v_sku, v_qty, v_reason,
      case when v_reason = 'RETURN_IN' then 'Terima retur' else 'Terima kiriman' end,
      'stock_move', p_move_id::text,
      v_actor, v_name,
      jsonb_build_object('product', v_it),
      true
    );
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'Tidak ada item valid untuk diterima.' using errcode = '42501';
  end if;

  update public.stock_move_history
  set
    status = 'SUCCESS',
    verified_by = coalesce(v_actor::text, v_row.verified_by),
    verified_by_name = coalesce(v_name, v_row.verified_by_name),
    verified_at = coalesce(v_row.verified_at, now()),
    bukti_foto_penerima = v_foto
  where id = p_move_id;

  update public.pending_requests
  set
    status = 'SUCCESS',
    tracking_status = 'SELESAI',
    reserved_qty = 0,
    reviewed_at = now()
  where status = 'SHIPPING'
    and (
      stock_move_id = p_move_id
      or (
        v_resi <> ''
        and stock_move_resi = v_resi
      )
    );

  return jsonb_build_object(
    'ok', true,
    'already_done', false,
    'id', p_move_id,
    'resi', v_resi,
    'status', 'SUCCESS',
    'received_count', v_n,
    'verified_by_name', coalesce(v_name, v_row.verified_by_name)
  );
end;
$$;

revoke all on function public.receive_stock_move(uuid, text, text, text)
  from public, anon;
grant execute on function public.receive_stock_move(uuid, text, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Retur: qty aman + anon dikunci
-- -----------------------------------------------------------------------------
create or replace function public.create_return_stock_move(
  p_dari text,
  p_items jsonb,
  p_kurir_id text default null,
  p_kurir_nama text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dari text := upper(trim(p_dari));
  v_it jsonb;
  v_sku text;
  v_qty int;
  v_n int := 0;
  v_total int := 0;
  v_resi text;
  v_id uuid;
  v_actor uuid;
  v_kurir uuid;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.do_write_rpc_on();
  perform public.assert_toko_in_caller_tenant(v_dari);
  if public.is_pusat_warehouse(v_dari) then
    raise exception 'Retur hanya dari cabang ke Pusat.' using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko(v_dari) then
    raise exception 'Hanya admin toko asal yang boleh retur.'
      using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) is distinct from 'array'
     or p_items = '[]'::jsonb then
    raise exception 'Item retur wajib.' using errcode = '42501';
  end if;

  v_resi := 'RET-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  begin
    v_actor := auth.uid();
  exception when others then
    v_actor := null;
  end;
  begin
    v_kurir := nullif(trim(coalesce(p_kurir_id, '')), '')::uuid;
  exception when others then
    v_kurir := null;
  end;

  for v_it in select value from jsonb_array_elements(p_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := public.stock_move_item_qty(v_it);
    if v_sku is null or v_qty <= 0 then
      continue;
    end if;
    perform public.apply_stock_delta(
      v_dari, v_sku, -v_qty, 'RETURN_OUT',
      'Retur ' || v_resi || ' → PUSAT',
      'stock_move', v_resi,
      v_actor, nullif(trim(coalesce(p_kurir_nama, '')), ''),
      jsonb_build_object('product', v_it),
      false
    );
    v_n := v_n + 1;
    v_total := v_total + v_qty;
  end loop;
  if v_n = 0 then
    raise exception 'Tidak ada item retur valid.' using errcode = '42501';
  end if;

  insert into public.stock_move_history (
    product_name, dari_lokasi, ke_lokasi, jumlah, tipe, status,
    keterangan, kurir_karyawan_id, kurir_nama
  ) values (
    v_resi, v_dari, 'PUSAT', v_total, 'RETUR', 'PENDING',
    p_items::text, v_kurir, nullif(trim(coalesce(p_kurir_nama, '')), '')
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'resi', v_resi,
    'status', 'PENDING',
    'jumlah', v_total
  );
end;
$$;

revoke all on function public.create_return_stock_move(text, jsonb, text, text)
  from public, anon;
grant execute on function public.create_return_stock_move(text, jsonb, text, text)
  to authenticated, service_role;
