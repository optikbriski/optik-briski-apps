-- =============================================================================
-- 000029 — Verifikasi terima barang end-to-end.
-- Apply di SQL Editor live SETELAH 000028.
--
-- Celah saat toko jalan (setelah 000027/000028):
-- - pending_requests bisa SUCCESS via REST meski surat jalan masih TRANSIT
--   → RO/sales READY tanpa TRANSFER_IN
-- - receive_stock_move terima tanpa foto + verified_by dari HP
-- =============================================================================

create or replace function public.stock_move_is_received(
  p_move_id uuid,
  p_resi text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.stock_move_history m
    where upper(trim(coalesce(m.status, ''))) = 'SUCCESS'
      and public.toko_belongs_to_current_tenant(m.ke_lokasi)
      and (
        (p_move_id is not null and m.id = p_move_id)
        or (
          nullif(trim(coalesce(p_resi, '')), '') is not null
          and m.product_name = trim(p_resi)
        )
      )
  );
$$;

comment on function public.stock_move_is_received(uuid, text) is
  'RO SUCCESS hanya jika surat jalan terkait sudah diterima.';

revoke all on function public.stock_move_is_received(uuid, text)
  from public, anon;
grant execute on function public.stock_move_is_received(uuid, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Terima: foto wajib + verified_by = auth.uid()
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

-- -----------------------------------------------------------------------------
-- RO SUCCESS hanya setelah surat jalan diterima
-- -----------------------------------------------------------------------------
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
      if v_new <> 'SUCCESS' then
        if not public.can_manage_inventory_for_toko('PUSAT') then
          raise exception 'Hanya gudang Pusat yang boleh proses RO.'
            using errcode = '42501';
        end if;
      end if;
    end if;
    if v_new = 'SUCCESS' then
      if current_setting('app.do_receive_rpc', true) is distinct from '1'
         and not public.stock_move_is_received(
           new.stock_move_id, new.stock_move_resi
         ) then
        raise exception
          'RO hanya boleh SUCCESS setelah surat jalan diterima.'
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
