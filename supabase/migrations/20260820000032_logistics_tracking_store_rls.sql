-- =============================================================================
-- 000032 — Tracking logistics end-to-end.
-- Apply di SQL Editor live SETELAH 000031.
--
-- Celah saat toko jalan (setelah 000028):
-- - REST PATCH kurir_karyawan_id / kurir_nama saat TRANSIT/PENDING
--   → nama kurir palsu, ID karyawan merek/cabang lain
-- - tidak cek karyawan aktif + shift OPEN
-- - cabang tujuan masih lihat tombol ganti kurir (gagal di RLS, UI longgar)
-- =============================================================================

create or replace function public.assign_kurir_rpc_on()
returns void
language plpgsql
as $$
begin
  perform set_config('app.assign_kurir_rpc', '1', true);
end;
$$;

comment on function public.assign_kurir_rpc_on() is
  'GUC internal. Hanya assign_stock_move_kurir yang boleh nyalakan.';

revoke all on function public.assign_kurir_rpc_on()
  from public, anon, authenticated;
grant execute on function public.assign_kurir_rpc_on() to service_role;

create or replace function public.assign_stock_move_kurir(
  p_move_id uuid,
  p_karyawan_id text default null,
  p_nama text default null
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
  v_jwt text;
  v_kid uuid;
  v_nama text;
  v_k public.karyawan;
  v_raw text := nullif(trim(coalesce(p_karyawan_id, '')), '');
begin
  perform public.assign_kurir_rpc_on();
  v_jwt := coalesce(auth.jwt() ->> 'role', '');
  if auth.uid() is null and v_jwt is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;

  select * into v_row
  from public.stock_move_history
  where id = p_move_id
  for update;
  if not found then
    raise exception 'Surat jalan tidak ditemukan.' using errcode = '42501';
  end if;

  v_dari := upper(trim(coalesce(v_row.dari_lokasi, '')));
  v_st := upper(trim(coalesce(v_row.status, '')));
  perform public.assert_toko_in_caller_tenant(v_dari);
  perform public.assert_toko_in_caller_tenant(v_row.ke_lokasi);

  if v_st not in ('PREPARING', 'WAITING', 'QUEUED', 'TRANSIT', 'PENDING') then
    raise exception 'Kurir terkunci setelah surat jalan selesai.'
      using errcode = '42501';
  end if;
  if auth.uid() is not null
     and not public.can_manage_inventory_for_toko(v_dari) then
    raise exception 'Hanya gudang asal yang boleh set kurir.'
      using errcode = '42501';
  end if;

  if v_raw is null then
    update public.stock_move_history
    set kurir_karyawan_id = null,
        kurir_nama = null
    where id = v_row.id;
    return jsonb_build_object(
      'ok', true,
      'cleared', true,
      'id', v_row.id,
      'status', v_st
    );
  end if;

  if v_raw !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'ID kurir tidak valid.';
  end if;
  v_kid := v_raw::uuid;

  select * into v_k
  from public.karyawan
  where id = v_kid
    and tenant_id is not distinct from public.current_tenant_id()
  for share;
  if not found then
    raise exception 'Karyawan kurir tidak ada di usaha ini.'
      using errcode = '42501';
  end if;
  if upper(trim(coalesce(v_k.status_approval, '')))
       not in ('AKTIF', 'APPROVED') then
    raise exception 'Kurir harus karyawan aktif.';
  end if;
  if auth.uid() is not null
     and not public.is_pusat_logistics_operator()
     and not public.same_store_toko(
       v_k.toko_id, public.current_profile_toko_id()
     ) then
    raise exception 'Admin toko hanya boleh pilih kurir toko sendiri.'
      using errcode = '42501';
  end if;
  if not public.pos_duty_ok(v_kid, v_k.toko_id) then
    raise exception 'Kurir harus sedang bertugas (sudah absen masuk).'
      using errcode = '42501';
  end if;

  v_nama := nullif(trim(coalesce(v_k.nama, p_nama, '')), '');
  if v_nama is null then
    raise exception 'Nama kurir wajib.';
  end if;

  update public.stock_move_history
  set kurir_karyawan_id = v_kid,
      kurir_nama = v_nama
  where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'cleared', false,
    'id', v_row.id,
    'status', v_st,
    'kurir_karyawan_id', v_kid,
    'kurir_nama', v_nama
  );
end;
$$;

comment on function public.assign_stock_move_kurir(uuid, text, text) is
  'Set/hapus kurir surat jalan. Bukan REST. Bukan cabang tujuan. Bukan merek lain.';

revoke all on function public.assign_stock_move_kurir(uuid, text, text)
  from public, anon;
grant execute on function public.assign_stock_move_kurir(uuid, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Kurir hanya lewat RPC (assign / transit / retur). Bukan REST PATCH.
-- -----------------------------------------------------------------------------
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
  v_rpc boolean;
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
  v_rpc := current_setting('app.do_receive_rpc', true) = '1'
        or current_setting('app.do_transit_rpc', true) = '1'
        or current_setting('app.do_write_rpc', true) = '1';

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

  if (
       coalesce(old.keterangan, '') is distinct from coalesce(new.keterangan, '')
       or coalesce(old.jumlah, 0) is distinct from coalesce(new.jumlah, 0)
     ) then
    if v_old_st in ('TRANSIT', 'PENDING', 'SUCCESS') then
      raise exception 'Item surat jalan terkunci setelah dikirim.'
        using errcode = '42501';
    end if;
    if auth.uid() is not null
       and not public.can_manage_inventory_for_toko(v_dari)
       and not v_rpc then
      raise exception
        'Hanya gudang asal yang boleh ubah item sebelum kirim.'
        using errcode = '42501';
    end if;
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
    if auth.uid() is not null
       and not public.can_manage_inventory_for_toko(v_dari) then
      raise exception 'Hanya gudang asal yang boleh batalkan surat jalan.'
        using errcode = '42501';
    end if;
    perform public.release_reservation(
      'DO_PREPARING', 'stock_move', old.id::text, null, v_dari
    );
  end if;

  if (
       old.kurir_karyawan_id is distinct from new.kurir_karyawan_id
       or coalesce(old.kurir_nama, '') is distinct from coalesce(new.kurir_nama, '')
     ) then
    if v_old_st in ('SUCCESS', 'BATAL', 'REJECTED')
       and current_setting('app.do_receive_rpc', true) is distinct from '1' then
      raise exception 'Kurir terkunci setelah surat jalan selesai.'
        using errcode = '42501';
    end if;
    if current_setting('app.assign_kurir_rpc', true) is distinct from '1'
       and current_setting('app.do_transit_rpc', true) is distinct from '1'
       and current_setting('app.do_write_rpc', true) is distinct from '1'
       and current_setting('app.do_receive_rpc', true) is distinct from '1' then
      raise exception 'Kurir hanya lewat assign_stock_move_kurir.'
        using errcode = '42501';
    end if;
    if auth.uid() is not null
       and not public.can_manage_inventory_for_toko(v_dari)
       and current_setting('app.do_receive_rpc', true) is distinct from '1' then
      raise exception 'Hanya gudang asal yang boleh set kurir.'
        using errcode = '42501';
    end if;
  end if;

  if coalesce(old.bukti_foto_pengirim, '')
       is distinct from coalesce(new.bukti_foto_pengirim, '')
     and auth.uid() is not null
     and not v_rpc then
    if v_old_st not in ('PREPARING', 'WAITING', 'QUEUED')
       or not public.can_manage_inventory_for_toko(v_dari) then
      raise exception 'Foto packing hanya boleh diisi gudang asal sebelum kirim.'
        using errcode = '42501';
    end if;
  end if;

  if (
       coalesce(old.bukti_foto_penerima, '')
         is distinct from coalesce(new.bukti_foto_penerima, '')
       or coalesce(old.bukti_foto_penerim, '')
         is distinct from coalesce(new.bukti_foto_penerim, '')
     )
     and current_setting('app.do_receive_rpc', true) is distinct from '1' then
    raise exception 'Foto terima hanya lewat receive_stock_move.'
      using errcode = '42501';
  end if;

  if coalesce(old.bukti_foto_kurir, '')
       is distinct from coalesce(new.bukti_foto_kurir, '')
     and current_setting('app.do_transit_rpc', true) is distinct from '1'
     and not v_rpc then
    raise exception 'Foto kurir hanya lewat mark_stock_move_transit.'
      using errcode = '42501';
  end if;

  if (
       coalesce(old.verified_by, '') is distinct from coalesce(new.verified_by, '')
       or coalesce(old.verified_by_name, '')
          is distinct from coalesce(new.verified_by_name, '')
       or old.verified_at is distinct from new.verified_at
     )
     and current_setting('app.do_receive_rpc', true) is distinct from '1' then
    raise exception 'Verifikasi terima hanya lewat receive_stock_move.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;
