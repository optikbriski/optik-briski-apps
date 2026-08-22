-- =============================================================================
-- 000028 — Stock Move Report end-to-end.
-- Apply di SQL Editor live SETELAH 000027.
--
-- Celah saat toko jalan (setelah 000027):
-- - UPDATE policy masih kasih cabang tujuan: PATCH keterangan saat PREPARING
--   → terima qty palsu (Pusat sudah potong reservasi asli)
-- - Cabang tujuan bisa BATAL-kan DO Pusat yang masih disiapkan
-- - SELECT pakai can_manage_inventory_for_toko('PUSAT')
--   → admin_toko di PUSAT + owner diperlakukan seperti hub semua cabang
-- - kurir / bukti foto masih bisa di-PATCH setelah SUCCESS
-- =============================================================================

create or replace function public.is_pusat_logistics_operator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_platform_user()
    or public.current_profile_role() in ('admin_pusat', 'super_admin');
$$;

comment on function public.is_pusat_logistics_operator() is
  'Hub laporan mutasi semua cabang. Bukan owner etalase. Bukan admin_toko di PUSAT.';

create or replace function public.can_view_stock_move_history(
  p_dari text,
  p_ke text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      public.toko_belongs_to_current_tenant(p_dari)
      or public.toko_belongs_to_current_tenant(p_ke)
    )
    and (
      public.is_pusat_logistics_operator()
      or (
        not public.is_owner_role()
        and (
          public.same_store_toko(public.current_profile_toko_id(), p_dari)
          or public.same_store_toko(public.current_profile_toko_id(), p_ke)
        )
      )
    );
$$;

comment on function public.can_view_stock_move_history(text, text) is
  'Lihat surat jalan: operator pusat semua tenant; admin_toko hanya toko sendiri.';

revoke all on function public.is_pusat_logistics_operator() from public, anon;
grant execute on function public.is_pusat_logistics_operator()
  to authenticated, service_role;
revoke all on function public.can_view_stock_move_history(text, text)
  from public, anon;
grant execute on function public.can_view_stock_move_history(text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Guard: item hanya gudang asal; foto/kurir/verifikasi terkunci
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

  if v_old_st in ('SUCCESS', 'BATAL', 'REJECTED')
     and current_setting('app.do_receive_rpc', true) is distinct from '1'
     and (
       old.kurir_karyawan_id is distinct from new.kurir_karyawan_id
       or coalesce(old.kurir_nama, '') is distinct from coalesce(new.kurir_nama, '')
     ) then
    raise exception 'Kurir terkunci setelah surat jalan selesai.'
      using errcode = '42501';
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

drop trigger if exists trg_stock_move_history_guard on public.stock_move_history;
create trigger trg_stock_move_history_guard
  before insert or update or delete on public.stock_move_history
  for each row
  execute function public.stock_move_history_guard();

-- -----------------------------------------------------------------------------
-- RLS: cabang tujuan tidak REST-write; terima hanya RPC
-- -----------------------------------------------------------------------------
drop policy if exists stock_move_history_select on public.stock_move_history;
create policy stock_move_history_select on public.stock_move_history
  for select to authenticated
  using (public.can_view_stock_move_history(dari_lokasi, ke_lokasi));

drop policy if exists stock_move_history_update on public.stock_move_history;
create policy stock_move_history_update on public.stock_move_history
  for update to authenticated
  using (
    public.can_manage_inventory_for_toko(dari_lokasi)
    or current_setting('app.do_receive_rpc', true) = '1'
    or current_setting('app.do_transit_rpc', true) = '1'
    or current_setting('app.do_write_rpc', true) = '1'
  )
  with check (
    public.can_manage_inventory_for_toko(dari_lokasi)
    or current_setting('app.do_receive_rpc', true) = '1'
    or current_setting('app.do_transit_rpc', true) = '1'
    or current_setting('app.do_write_rpc', true) = '1'
  );
