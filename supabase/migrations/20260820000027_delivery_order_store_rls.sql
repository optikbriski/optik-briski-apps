-- =============================================================================
-- 000027 — Delivery Order end-to-end.
-- Apply di SQL Editor live SETELAH 000026.
--
-- Celah saat toko jalan (setelah 000026):
-- - PREPARING → PENDING (cabang) lalu SUCCESS + TRANSFER_IN
--   → stok cabang dobel, Pusat belum potong
-- - apply_stock_delta(TRANSFER_IN) tanpa surat jalan
-- - terima stok dulu, baru SUCCESS → scan dobel = stok dobel
-- - TRANSIT → BATAL / DELETE setelah potong Real → stok hantu
-- - INSERT DELIVERY dari cabang / INSERT langsung TRANSIT
-- - RETUR PENDING palsu tanpa RETURN_OUT
-- - apply_stock_transfer bypass surat jalan
-- =============================================================================

create or replace function public.is_pusat_warehouse(p_toko text)
returns boolean
language sql
immutable
as $$
  select upper(trim(coalesce(p_toko, ''))) in ('PUSAT', 'CABANG-PUSAT');
$$;

create or replace function public.do_receive_rpc_on()
returns void
language plpgsql
as $$
begin
  perform set_config('app.do_receive_rpc', '1', true);
  perform public.inventory_rpc_on();
end;
$$;

create or replace function public.do_transit_rpc_on()
returns void
language plpgsql
as $$
begin
  perform set_config('app.do_transit_rpc', '1', true);
  perform public.inventory_rpc_on();
end;
$$;

create or replace function public.do_write_rpc_on()
returns void
language plpgsql
as $$
begin
  perform set_config('app.do_write_rpc', '1', true);
  perform public.inventory_rpc_on();
end;
$$;

revoke all on function public.is_pusat_warehouse(text) from public, anon;
grant execute on function public.is_pusat_warehouse(text)
  to authenticated, service_role;
revoke all on function public.do_receive_rpc_on() from public, anon, authenticated;
grant execute on function public.do_receive_rpc_on() to service_role;
revoke all on function public.do_transit_rpc_on() from public, anon, authenticated;
grant execute on function public.do_transit_rpc_on() to service_role;
revoke all on function public.do_write_rpc_on() from public, anon, authenticated;
grant execute on function public.do_write_rpc_on() to service_role;

-- -----------------------------------------------------------------------------
-- Item JSON di keterangan (boleh ada prefix teks sebelum [)
-- -----------------------------------------------------------------------------
create or replace function public.stock_move_items_json(p_ket text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_pos int;
  v_json jsonb;
begin
  if p_ket is null or trim(p_ket) = '' then
    return '[]'::jsonb;
  end if;
  v_pos := position('[' in p_ket);
  if v_pos = 0 then
    return '[]'::jsonb;
  end if;
  begin
    v_json := substring(p_ket from v_pos)::jsonb;
  exception when others then
    return '[]'::jsonb;
  end;
  if jsonb_typeof(v_json) is distinct from 'array' then
    return '[]'::jsonb;
  end if;
  return v_json;
end;
$$;

revoke all on function public.stock_move_items_json(text) from public, anon;
grant execute on function public.stock_move_items_json(text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Mesin status: jangan PREPARING → PENDING. BATAL hanya sebelum kirim.
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
        and upper(trim(coalesce(p_old, ''))) in (
          'PREPARING', 'WAITING', 'QUEUED'
        )
        then true
      when upper(trim(coalesce(p_old, ''))) in ('SUCCESS', 'BATAL', 'REJECTED')
        then false
      when upper(trim(coalesce(p_old, ''))) = 'QUEUED'
        and upper(trim(coalesce(p_new, ''))) in ('PREPARING', 'WAITING')
        then true
      when upper(trim(coalesce(p_old, ''))) = 'WAITING'
        and upper(trim(coalesce(p_new, ''))) = 'PREPARING'
        then true
      when upper(trim(coalesce(p_old, ''))) in ('PREPARING', 'WAITING')
        and upper(trim(coalesce(p_new, ''))) = 'TRANSIT'
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
  v_tipe text;
  v_new_st text;
  v_old_st text;
begin
  if tg_op = 'DELETE' then
    if not public.can_manage_inventory_for_toko(old.dari_lokasi)
       and not public.is_platform_user() then
      raise exception 'Hanya admin gudang asal yang boleh hapus surat jalan.'
        using errcode = '42501';
    end if;
    v_old_st := upper(trim(coalesce(old.status, '')));
    if v_old_st in ('SUCCESS', 'TRANSIT', 'PENDING') then
      raise exception
        'Surat jalan yang sudah jalan/selesai tidak boleh dihapus.'
        using errcode = '42501';
    end if;
    perform public.release_reservation(
      'DO_PREPARING', 'stock_move', old.id::text, null, old.dari_lokasi
    );
    return old;
  end if;

  v_dari := upper(trim(coalesce(new.dari_lokasi, '')));
  v_ke := upper(trim(coalesce(new.ke_lokasi, '')));
  v_tipe := upper(trim(coalesce(new.tipe, 'DELIVERY')));
  v_new_st := upper(trim(coalesce(new.status, '')));
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
    if v_new_st in ('SUCCESS', 'TRANSIT') then
      raise exception
        'Tidak boleh insert surat jalan langsung TRANSIT/SUCCESS.'
        using errcode = '42501';
    end if;
    if v_tipe in ('DELIVERY', 'REQUEST')
       and not public.is_pusat_warehouse(v_dari) then
      raise exception 'DO/RO hanya boleh berangkat dari gudang Pusat.'
        using errcode = '42501';
    end if;
    if v_tipe = 'RETUR' and not public.is_pusat_warehouse(v_ke) then
      raise exception 'Retur hanya ke gudang Pusat.' using errcode = '42501';
    end if;
    if v_new_st = 'PENDING' then
      if v_tipe is distinct from 'RETUR'
         or current_setting('app.do_write_rpc', true) is distinct from '1' then
        raise exception
          'PENDING hanya untuk retur lewat create_return_stock_move.'
          using errcode = '42501';
      end if;
    elsif v_new_st not in ('PREPARING', 'WAITING', 'QUEUED') then
      raise exception 'Status surat jalan baru tidak valid: %', v_new_st
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

  v_old_st := upper(trim(coalesce(old.status, '')));
  if not public.stock_move_status_ok(old.status, new.status) then
    raise exception
      'Status surat jalan tidak boleh lompat / dibuka ulang.'
      using errcode = '42501';
  end if;

  if v_new_st in ('TRANSIT', 'PENDING', 'SUCCESS')
     and (
       coalesce(old.keterangan, '') is distinct from coalesce(new.keterangan, '')
       or coalesce(old.jumlah, 0) is distinct from coalesce(new.jumlah, 0)
     ) then
    raise exception 'Item surat jalan terkunci setelah dikirim.'
      using errcode = '42501';
  end if;

  if v_new_st = 'TRANSIT' and v_old_st is distinct from 'TRANSIT' then
    if current_setting('app.do_transit_rpc', true) is distinct from '1' then
      raise exception 'Kirim TRANSIT hanya lewat mark_stock_move_transit.'
        using errcode = '42501';
    end if;
    if auth.uid() is not null
       and not public.can_manage_inventory_for_toko(v_dari) then
      raise exception 'Cabang tujuan tidak boleh jemput / potong stok Pusat.'
        using errcode = '42501';
    end if;
  end if;

  if v_new_st = 'SUCCESS' and v_old_st is distinct from 'SUCCESS' then
    if current_setting('app.do_receive_rpc', true) is distinct from '1' then
      raise exception 'Terima barang hanya lewat receive_stock_move.'
        using errcode = '42501';
    end if;
    if auth.uid() is not null
       and not public.can_receive_stock_for_toko(v_ke) then
      raise exception 'Hanya admin toko tujuan yang boleh terima barang.'
        using errcode = '42501';
    end if;
  end if;

  if v_new_st in ('BATAL', 'REJECTED') and v_old_st is distinct from v_new_st then
    perform public.release_reservation(
      'DO_PREPARING', 'stock_move', old.id::text, null, v_dari
    );
  end if;

  if v_old_st in ('TRANSIT', 'PENDING', 'SUCCESS')
     and current_setting('app.do_receive_rpc', true) is distinct from '1'
     and current_setting('app.do_transit_rpc', true) is distinct from '1'
     and (
       coalesce(old.verified_by, '') is distinct from coalesce(new.verified_by, '')
       or coalesce(old.verified_by_name, '')
          is distinct from coalesce(new.verified_by_name, '')
       or old.verified_at is distinct from new.verified_at
     ) then
    raise exception 'Verifikasi terima hanya lewat receive_stock_move.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_stock_move_history_guard on public.stock_move_history;
create trigger trg_stock_move_history_guard
  before insert or update or delete on public.stock_move_history
  for each row
  execute function public.stock_move_history_guard();

-- -----------------------------------------------------------------------------
-- TRANSFER_IN / RETURN_IN hanya dari receive_stock_move
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
  if p_reason in ('TRANSFER_IN', 'RETURN_IN')
     and current_setting('app.do_receive_rpc', true) is distinct from '1'
     and v_jwt is distinct from 'service_role' then
    raise exception
      'Terima stok hanya lewat surat jalan (receive_stock_move).'
      using errcode = '42501';
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
-- TRANSIT: potong stok + status dalam satu transaksi
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
    v_ro_id := substring(coalesce(v_row.keterangan, '') from 'RequestOrder#([0-9a-fA-F-]{8,})');
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

-- -----------------------------------------------------------------------------
-- Terima: TRANSFER_IN + SUCCESS atomik + idempotent
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
begin
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

  v_reason := case
    when v_tipe = 'RETUR' or v_resi ilike 'RET-%' then 'RETURN_IN'
    else 'TRANSFER_IN'
  end;
  v_items := public.stock_move_items_json(v_row.keterangan);
  if v_items = '[]'::jsonb then
    raise exception 'Paket tanpa detail SKU tidak bisa diterima.'
      using errcode = '42501';
  end if;

  begin
    v_actor := nullif(trim(coalesce(p_verified_by, '')), '')::uuid;
  exception when others then
    v_actor := auth.uid();
  end;
  v_name := nullif(trim(coalesce(p_verified_by_name, '')), '');

  for v_it in select value from jsonb_array_elements(v_items)
  loop
    v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
    v_qty := coalesce(nullif(v_it->>'qty', '')::int, 0);
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
    verified_by = coalesce(nullif(trim(coalesce(p_verified_by, '')), ''), v_row.verified_by),
    verified_by_name = coalesce(v_name, v_row.verified_by_name),
    verified_at = coalesce(v_row.verified_at, now()),
    bukti_foto_penerima = coalesce(
      nullif(trim(coalesce(p_bukti_foto_penerima, '')), ''),
      v_row.bukti_foto_penerima
    )
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

-- -----------------------------------------------------------------------------
-- Retur cabang → Pusat: RETURN_OUT + PENDING atomik
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
    v_qty := coalesce(nullif(v_it->>'qty', '')::int, 0);
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

revoke all on function public.mark_stock_move_transit(uuid, text, text, text)
  from public, anon;
grant execute on function public.mark_stock_move_transit(uuid, text, text, text)
  to authenticated, service_role;
revoke all on function public.receive_stock_move(uuid, text, text, text)
  from public, anon;
grant execute on function public.receive_stock_move(uuid, text, text, text)
  to authenticated, service_role;
revoke all on function public.create_return_stock_move(text, jsonb, text, text)
  from public, anon;
grant execute on function public.create_return_stock_move(text, jsonb, text, text)
  to authenticated, service_role;

comment on function public.mark_stock_move_transit(uuid, text, text, text) is
  'PREPARING→TRANSIT + potong Real. Idempotent. Bukan REST PATCH.';
comment on function public.receive_stock_move(uuid, text, text, text) is
  'TRANSIT/PENDING→SUCCESS + TRANSFER_IN. Idempotent. Bukan REST PATCH.';
comment on function public.create_return_stock_move(text, jsonb, text, text) is
  'Retur cabang: RETURN_OUT + surat PENDING atomik.';

-- Transfer bebas = bypass DO
revoke all on function public.apply_stock_transfer(
  text, text, text, integer, text, text, text, text, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.apply_stock_transfer(
  text, text, text, integer, text, text, text, text, text, uuid, text, jsonb
) to service_role;

revoke all on function public.apply_stock_move(text, text, text, integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.apply_stock_move(text, text, text, integer, jsonb)
  to service_role;

-- -----------------------------------------------------------------------------
-- SELECT: hanya toko yang tersentuh / operator Pusat. Bukan semua cabang tenant.
-- -----------------------------------------------------------------------------
drop policy if exists stock_move_history_select on public.stock_move_history;
create policy stock_move_history_select on public.stock_move_history
  for select to authenticated
  using (
    (
      public.toko_belongs_to_current_tenant(dari_lokasi)
      or public.toko_belongs_to_current_tenant(ke_lokasi)
    )
    and (
      public.is_platform_user()
      or public.can_manage_inventory_for_toko('PUSAT')
      or public.same_store_toko(public.current_profile_toko_id(), dari_lokasi)
      or public.same_store_toko(public.current_profile_toko_id(), ke_lokasi)
    )
  );
