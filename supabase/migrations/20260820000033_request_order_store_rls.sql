-- =============================================================================
-- 000033 — Request Order end-to-end.
-- Apply di SQL Editor live SETELAH 000032.
--
-- Celah saat toko jalan (setelah 000029):
-- - admin_toko cabang lolos guard (can_manage toko sendiri)
--   → PATCH PREPARING / SHIPPING tanpa reservasi / tanpa potong stok Pusat
-- - SUCCESS + stock_move_id surat jalan orang yang sudah diterima
-- - REJECTED setelah SHIPPING (stok sudah potong, tidak balik)
-- - sku/qty diganti setelah diproses
-- =============================================================================

create or replace function public.ro_status_ok(p_old text, p_new text)
returns boolean
language sql
immutable
as $$
  select
    case
      when upper(trim(coalesce(p_old, ''))) = upper(trim(coalesce(p_new, '')))
        then true
      when upper(trim(coalesce(p_new, ''))) = 'REJECTED'
        then upper(trim(coalesce(p_old, ''))) in (
          'PENDING', 'SENT_TO_HQ', 'APPROVED', 'PREPARING'
        )
      when upper(trim(coalesce(p_old, ''))) = 'PENDING'
        then upper(trim(coalesce(p_new, ''))) in (
          'SENT_TO_HQ', 'PREPARING', 'APPROVED'
        )
      when upper(trim(coalesce(p_old, ''))) = 'SENT_TO_HQ'
        then upper(trim(coalesce(p_new, ''))) in ('PREPARING', 'APPROVED')
      when upper(trim(coalesce(p_old, ''))) = 'APPROVED'
        then upper(trim(coalesce(p_new, ''))) in ('PREPARING', 'SHIPPING')
      when upper(trim(coalesce(p_old, ''))) = 'PREPARING'
        then upper(trim(coalesce(p_new, ''))) = 'SHIPPING'
      when upper(trim(coalesce(p_old, ''))) = 'SHIPPING'
        then upper(trim(coalesce(p_new, ''))) = 'SUCCESS'
      else false
    end;
$$;

comment on function public.ro_status_ok(text, text) is
  'Mesin status RO. Bukan loncat PENDING→SUCCESS. Bukan tolak setelah jalan.';

revoke all on function public.ro_status_ok(text, text) from public, anon;
grant execute on function public.ro_status_ok(text, text)
  to authenticated, service_role;

create or replace function public.ro_rpc_on()
returns void
language plpgsql
as $$
begin
  perform set_config('app.ro_rpc', '1', true);
  perform public.inventory_rpc_on();
end;
$$;

revoke all on function public.ro_rpc_on() from public, anon, authenticated;
grant execute on function public.ro_rpc_on() to service_role;

create or replace function public.pending_requests_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_new text;
  v_ro boolean;
  v_recv boolean;
begin
  if tg_op = 'DELETE' then
    if not public.can_manage_inventory_for_toko(old.toko_id)
       and not public.can_request_ro_for_toko(old.toko_id) then
      raise exception 'Tidak boleh hapus RO toko lain.' using errcode = '42501';
    end if;
    -- SENT_TO_HQ+ tidak dihapus: cabang bisa hilangkan antrian HQ,
    -- PREPARING meninggalkan reserved_qty yatim.
    if upper(trim(coalesce(old.status, ''))) is distinct from 'PENDING'
       and not public.is_platform_user() then
      raise exception
        'Hanya antrian PENDING yang boleh dihapus. Tolak lewat reject_request_order.'
        using errcode = '42501';
    end if;
    if coalesce(old.reserved_qty, 0) > 0
       and not public.is_platform_user() then
      raise exception 'RO bereservasi tidak boleh dihapus.'
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

  v_ro := current_setting('app.ro_rpc', true) = '1';
  v_recv := current_setting('app.do_receive_rpc', true) = '1';
  v_old := upper(trim(coalesce(old.status, '')));
  v_new := upper(trim(coalesce(new.status, '')));

  if old.toko_id is distinct from new.toko_id then
    raise exception 'toko_id RO tidak boleh dipindah.' using errcode = '42501';
  end if;

  -- Setelah kirim ke Pusat, cabang tidak boleh ganti SKU/qty (inflasi antrian HQ).
  if v_old is distinct from 'PENDING'
     and not v_ro
     and not v_recv
     and (
       coalesce(new.qty_request, 0) is distinct from coalesce(old.qty_request, 0)
       or coalesce(new.sku, '') is distinct from coalesce(old.sku, '')
       or coalesce(new.nama_produk, '') is distinct from coalesce(old.nama_produk, '')
     ) then
    raise exception 'SKU/qty RO terkunci setelah dikirim ke Pusat.'
      using errcode = '42501';
  end if;

  if (
       old.stock_move_id is distinct from new.stock_move_id
       or coalesce(old.stock_move_resi, '')
          is distinct from coalesce(new.stock_move_resi, '')
     )
     and not v_ro
     and not v_recv then
    raise exception 'Surat jalan RO hanya lewat ship_request_order.'
      using errcode = '42501';
  end if;

  if v_old is distinct from v_new then
    if not public.ro_status_ok(v_old, v_new) then
      raise exception 'Status RO tidak boleh loncat / dibuka ulang.'
        using errcode = '42501';
    end if;

    if v_new = 'SENT_TO_HQ' then
      if auth.uid() is not null
         and not public.can_request_ro_for_toko(new.toko_id) then
        raise exception 'Hanya kasir/admin toko ini yang boleh kirim RO ke Pusat.'
          using errcode = '42501';
      end if;
    end if;

    if v_new in ('PREPARING', 'APPROVED', 'SHIPPING', 'REJECTED') then
      if not v_ro
         and auth.uid() is not null then
        raise exception
          'Proses RO Pusat hanya lewat approve/reject/ship_request_order.'
          using errcode = '42501';
      end if;
      if auth.uid() is not null
         and not public.can_manage_inventory_for_toko('PUSAT') then
        raise exception 'Hanya gudang Pusat yang boleh proses RO.'
          using errcode = '42501';
      end if;
    end if;

    if v_new = 'SUCCESS' then
      if not v_recv
         and (
           v_old is distinct from 'SHIPPING'
           or new.stock_move_id is distinct from old.stock_move_id
           or not public.stock_move_is_received(
             old.stock_move_id, old.stock_move_resi
           )
         ) then
        raise exception
          'RO hanya boleh SUCCESS setelah surat jalan RO ini diterima.'
          using errcode = '42501';
      end if;
      if auth.uid() is not null
         and not public.can_receive_stock_for_toko(new.toko_id)
         and not public.can_manage_inventory_for_toko('PUSAT') then
        raise exception 'Hanya admin toko tujuan yang boleh closing RO.'
          using errcode = '42501';
      end if;
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

-- -----------------------------------------------------------------------------
-- Cabang: kirim antrian hari ini ke Pusat
-- -----------------------------------------------------------------------------
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
  where toko_id = v_toko
    and status = 'PENDING'
    and id = any (p_ids);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

comment on function public.send_request_orders_to_hq(text, bigint[]) is
  'Cabang kirim antrian PENDING → SENT_TO_HQ. Bukan approve. Bukan toko orang.';

revoke all on function public.send_request_orders_to_hq(text, bigint[])
  from public, anon;
grant execute on function public.send_request_orders_to_hq(text, bigint[])
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Pusat: reservasi + Disiapkan
-- -----------------------------------------------------------------------------
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
  'Pusat reservasi stok + PREPARING. Bukan REST. Bukan admin cabang.';

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
  'Pusat lepas reservasi + REJECTED. Bukan setelah SHIPPING.';

revoke all on function public.reject_request_order(bigint, text)
  from public, anon;
grant execute on function public.reject_request_order(bigint, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Pusat: surat jalan + TRANSIT + SHIPPING dalam satu pintu
-- -----------------------------------------------------------------------------
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
  'Kirim RO: reservasi → TRANSFER_OUT + surat jalan. Bukan REST. Bukan cabang.';

revoke all on function public.ship_request_order(bigint, text, text)
  from public, anon;
grant execute on function public.ship_request_order(bigint, text, text)
  to authenticated, service_role;

-- RequestOrder#123 (bigserial) harus ketemu, bukan hanya uuid 8+ hex.
create or replace function public.stock_move_ro_id(p_ket text)
returns text
language sql
immutable
as $$
  select nullif(
    substring(coalesce(p_ket, '') from 'RequestOrder#([0-9]+)'),
    ''
  );
$$;

revoke all on function public.stock_move_ro_id(text) from public, anon;
grant execute on function public.stock_move_ro_id(text)
  to authenticated, service_role;

-- Consume reservasi RO#123 (bukan hanya uuid 8+ hex)
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
begin
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

  if v_n = 0 then
    v_items := public.stock_move_items_json(v_row.keterangan);
    if v_items = '[]'::jsonb then
      raise exception 'Surat jalan tanpa item/SKU tidak bisa dikirim.'
        using errcode = '42501';
    end if;
    for v_it in select value from jsonb_array_elements(v_items)
    loop
      v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
      v_qty := coalesce(nullif(v_it->>'qty', '')::int, 0);
      if v_sku is null or v_qty <= 0 then
        continue;
      end if;
      perform public.apply_stock_delta(
        v_dari, v_sku, -v_qty, 'TRANSFER_OUT',
        v_tipe || ' ' || v_resi || ' → TRANSIT (legacy)',
        'stock_move', p_move_id::text,
        v_actor, nullif(trim(coalesce(p_kurir_nama, '')), ''),
        jsonb_build_object('product', v_it),
        false
      );
      v_n := v_n + 1;
    end loop;
    if v_n = 0 then
      raise exception 'Tidak ada item valid untuk dipotong saat TRANSIT.'
        using errcode = '42501';
    end if;
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
    'cut_count', v_n
  );
end;
$$;

revoke all on function public.mark_stock_move_transit(uuid, text, text, text)
  from public, anon;
grant execute on function public.mark_stock_move_transit(uuid, text, text, text)
  to authenticated, service_role;
