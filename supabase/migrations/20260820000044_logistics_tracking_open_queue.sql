-- =============================================================================
-- 000044 — Tracking logistics: antrian terbuka tidak boleh hilang.
-- Apply di SQL Editor live SETELAH 000043.
--
-- Celah saat toko buka Tracking:
-- - REST .limit(120) memotong TRANSIT/QUEUED lama
-- - Flutter status terbuka tanpa QUEUED
-- - assign_stock_move_kurir belum kunci anon
-- =============================================================================

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
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
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
  'Set/hapus kurir surat jalan. Bukan REST. Bukan cabang tujuan. Bukan anon.';

revoke all on function public.assign_stock_move_kurir(uuid, text, text)
  from public, anon;
grant execute on function public.assign_stock_move_kurir(uuid, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Antrian terbuka semua umur + SUCCESS 3 hari (konteks giliran A→B→C)
-- -----------------------------------------------------------------------------
create or replace function public.list_logistics_tracking(p_toko text default null)
returns setof public.stock_move_history
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
  v_mine text := upper(trim(coalesce(public.current_profile_toko_id(), '')));
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if v_toko is not null
     and not public.toko_belongs_to_current_tenant(v_toko)
     and v_toko not in ('PUSAT', 'CABANG-PUSAT') then
    raise exception 'Toko di luar tenant' using errcode = '42501';
  end if;

  if not public.is_pusat_logistics_operator() then
    if v_mine = '' then
      return;
    end if;
    if v_toko is not null and not public.same_store_toko(v_mine, v_toko) then
      raise exception 'Tidak berhak tracking toko lain'
        using errcode = '42501';
    end if;
    v_toko := coalesce(v_toko, v_mine);
  end if;

  return query
  select m.*
  from public.stock_move_history m
  where public.can_view_stock_move_history(m.dari_lokasi, m.ke_lokasi)
    and (
      v_toko is null
      or public.same_store_toko(m.dari_lokasi, v_toko)
      or public.same_store_toko(m.ke_lokasi, v_toko)
    )
    and (
      upper(trim(coalesce(m.status, ''))) in (
        'PREPARING', 'WAITING', 'QUEUED', 'TRANSIT', 'PENDING'
      )
      or (
        upper(trim(coalesce(m.status, ''))) = 'SUCCESS'
        and coalesce(m.verified_at, m.created_at)
              >= (timezone('utc', now()) - interval '3 days')
      )
    )
  order by m.created_at desc;
end;
$$;

comment on function public.list_logistics_tracking(text) is
  'Tracking: antrian terbuka tidak potong umur; SUCCESS 3 hari. Bukan anon.';

revoke all on function public.list_logistics_tracking(text)
  from public, anon;
grant execute on function public.list_logistics_tracking(text)
  to authenticated, service_role;
