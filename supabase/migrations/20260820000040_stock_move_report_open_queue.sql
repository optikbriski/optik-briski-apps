-- =============================================================================
-- 000040 — Stock Move Report: antrian terbuka tidak boleh hilang.
-- Apply di SQL Editor live SETELAH 000039.
--
-- Celah saat toko buka SMR:
-- - REST .limit(400) + 90 hari memotong TRANSIT/PREPARING lama
--   → cabang tidak lihat paket yang harus diterima
-- - EXECUTE PUBLIC pada helper lihat (kalau function di-create ulang)
-- =============================================================================

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
    coalesce(auth.role(), '') is distinct from 'anon'
    and (
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
  'Lihat surat jalan: operator pusat semua tenant; admin_toko hanya toko sendiri. Bukan anon.';

revoke all on function public.can_view_stock_move_history(text, text)
  from public, anon;
grant execute on function public.can_view_stock_move_history(text, text)
  to authenticated, service_role;

revoke all on function public.is_pusat_logistics_operator()
  from public, anon;
grant execute on function public.is_pusat_logistics_operator()
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Antrian terbuka (PREPARING/TRANSIT/…) semua umur + selesai N hari
-- -----------------------------------------------------------------------------
create or replace function public.list_stock_move_report(
  p_toko text default null,
  p_days integer default 90
)
returns setof public.stock_move_history
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
  v_mine text := upper(trim(coalesce(public.current_profile_toko_id(), '')));
  v_days int := least(365, greatest(1, coalesce(p_days, 90)));
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
      raise exception 'Tidak berhak laporan mutasi toko lain'
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
      or m.created_at >= (now() - make_interval(days => v_days))
    )
  order by m.created_at desc;
end;
$$;

comment on function public.list_stock_move_report(text, integer) is
  'SMR: antrian terbuka tidak potong umur; selesai hanya N hari. Bukan anon.';

revoke all on function public.list_stock_move_report(text, integer)
  from public, anon;
grant execute on function public.list_stock_move_report(text, integer)
  to authenticated, service_role;
