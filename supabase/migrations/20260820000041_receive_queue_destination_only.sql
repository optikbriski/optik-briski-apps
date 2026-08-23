-- =============================================================================
-- 000041 — Verifikasi terima: antrian lengkap + hanya toko tujuan.
-- Apply di SQL Editor live SETELAH 000040.
--
-- Celah saat toko terima barang:
-- - UI antrian .limit(100) menyembunyikan TRANSIT lama
-- - can_receive = can_manage → admin_pusat bisa TRANSFER_IN ke cabang dari HQ
-- =============================================================================

create or replace function public.can_receive_stock_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(auth.role(), '') is distinct from 'anon'
    and public.toko_belongs_to_current_tenant(p_toko)
    and not public.is_owner_role()
    and (
      (
        public.current_profile_role() = 'admin_toko'
        and public.same_store_toko(public.current_profile_toko_id(), p_toko)
      )
      or (
        public.is_pusat_warehouse(p_toko)
        and public.current_profile_role() in ('admin_pusat', 'super_admin')
      )
    );
$$;

comment on function public.can_receive_stock_for_toko(text) is
  'Terima stok hanya toko tujuan. admin_toko cabang sendiri; pusat hanya gudang Pusat (retur). Bukan owner. Bukan anon.';

revoke all on function public.can_receive_stock_for_toko(text)
  from public, anon;
grant execute on function public.can_receive_stock_for_toko(text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Antrian TRANSIT/PENDING ke toko ini — tanpa potong 100 baris
-- -----------------------------------------------------------------------------
create or replace function public.list_incoming_receive_queue(p_toko text)
returns setof public.stock_move_history
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if v_toko is null then
    raise exception 'Toko tujuan wajib.' using errcode = '42501';
  end if;
  if not public.can_receive_stock_for_toko(v_toko) then
    raise exception 'Tidak berhak antrian terima toko ini.'
      using errcode = '42501';
  end if;

  return query
  select m.*
  from public.stock_move_history m
  where public.can_view_stock_move_history(m.dari_lokasi, m.ke_lokasi)
    and public.same_store_toko(m.ke_lokasi, v_toko)
    and upper(trim(coalesce(m.status, ''))) in ('TRANSIT', 'PENDING')
  order by m.created_at desc;
end;
$$;

comment on function public.list_incoming_receive_queue(text) is
  'Antrian terima TRANSIT/PENDING ke toko tujuan. Tidak potong 100 baris. Bukan anon.';

revoke all on function public.list_incoming_receive_queue(text)
  from public, anon;
grant execute on function public.list_incoming_receive_queue(text)
  to authenticated, service_role;

create or replace function public.count_incoming_receive_queue(p_toko text)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
  v_n int := 0;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if v_toko is null or not public.can_receive_stock_for_toko(v_toko) then
    return 0;
  end if;

  select count(*)::int into v_n
  from public.stock_move_history m
  where public.can_view_stock_move_history(m.dari_lokasi, m.ke_lokasi)
    and public.same_store_toko(m.ke_lokasi, v_toko)
    and upper(trim(coalesce(m.status, ''))) in ('TRANSIT', 'PENDING');
  return coalesce(v_n, 0);
end;
$$;

comment on function public.count_incoming_receive_queue(text) is
  'Jumlah paket menunggu terima di toko tujuan. Bukan anon.';

revoke all on function public.count_incoming_receive_queue(text)
  from public, anon;
grant execute on function public.count_incoming_receive_queue(text)
  to authenticated, service_role;
