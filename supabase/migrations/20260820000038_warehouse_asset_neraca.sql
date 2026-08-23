-- =============================================================================
-- 000038 — Neraca kapitalisasi aset gudang (stok × modal / jual).
-- Apply di SQL Editor live SETELAH 000037.
--
-- Celah saat toko buka Inventory:
-- - Select products tanpa page → potong 1000 baris, aset kurang
-- - int.tryParse `150000.0` / stok double → modal & volume 0
-- - Cabang bisa lihat SKU tenant lain di query longgar
-- =============================================================================

create or replace function public.warehouse_asset_neraca(p_toko text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
  v_role text := public.current_profile_role();
  v_mine text := upper(trim(coalesce(public.current_profile_toko_id(), '')));
  v_aset bigint := 0;
  v_omzet bigint := 0;
  v_vol bigint := 0;
  v_all boolean;
begin
  if auth.uid() is null or coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized';
  end if;

  if v_toko is not null
     and v_toko not in ('PUSAT', 'CABANG-PUSAT')
     and not public.toko_belongs_to_current_tenant(v_toko) then
    raise exception 'Toko di luar tenant';
  end if;

  v_all := v_toko is null or v_toko in ('PUSAT', 'CABANG-PUSAT');
  if not v_all
     and v_mine not in ('PUSAT', 'CABANG-PUSAT')
     and v_role not in ('owner', 'superadmin', 'super_admin', 'admin_pusat')
     and v_mine <> v_toko then
    raise exception 'Tidak berhak aset gudang toko ini';
  end if;

  select
    coalesce(sum(
      greatest(coalesce(p.stock, 0), 0)::bigint
      * coalesce(p.harga_modal, 0)
    ), 0),
    coalesce(sum(
      greatest(coalesce(p.stock, 0), 0)::bigint
      * coalesce(p.harga_jual, p.harga, 0)
    ), 0),
    coalesce(sum(greatest(coalesce(p.stock, 0), 0)), 0)
  into v_aset, v_omzet, v_vol
  from public.products p
  where p.tenant_id is not distinct from public.current_tenant_id()
    and greatest(coalesce(p.stock, 0), 0) > 0
    and (
      v_all
      or upper(trim(coalesce(p.toko_id, ''))) = v_toko
    );

  return jsonb_build_object(
    'aset_pokok', v_aset,
    'potensi_omzet', v_omzet,
    'proyeksi_margin', v_omzet - v_aset,
    'volume', v_vol
  );
end;
$$;

comment on function public.warehouse_asset_neraca(text) is
  'Aset gudang = stok fisik × harga_modal; potensi = stok × harga_jual/harga. Bukan anon.';

revoke all on function public.warehouse_asset_neraca(text) from public, anon;
grant execute on function public.warehouse_asset_neraca(text) to authenticated;
