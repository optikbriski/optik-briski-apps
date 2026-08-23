-- =============================================================================
-- 000042 — Stok rusak: riwayat satu toko + nilai modal.
-- Apply di SQL Editor live SETELAH 000041.
--
-- Celah saat toko catat rusak:
-- - int.tryParse qty_delta / stock_after JSON `8.0` / `-2.0` jadi 0 di UI
-- - riwayat REST longgar; belum ada pintu list WRITE_OFF per toko
-- - nilai buku (qty × harga_modal) tidak kembali dari RPC
-- =============================================================================

create or replace function public.write_off_stock(
  p_toko text,
  p_sku text,
  p_qty integer,
  p_alasan text,
  p_actor_nama text default null,
  p_ref_id text default null,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_sku text := trim(p_sku);
  v_alasan text := trim(coalesce(p_alasan, ''));
  v_actor uuid;
  v_nama text;
  v_ref text;
  v_jwt text;
  v_out jsonb;
  v_modal bigint := 0;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  perform public.write_off_rpc_on();
  v_jwt := coalesce(auth.jwt() ->> 'role', '');
  v_actor := auth.uid();
  if v_actor is null and v_jwt is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Qty rusak harus lebih dari 0.';
  end if;
  if length(v_alasan) < 3 then
    raise exception 'Alasan write-off minimal 3 karakter.';
  end if;
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib untuk write-off.';
  end if;
  perform public.assert_toko_in_caller_tenant(v_toko);
  if v_actor is not null
     and not public.can_manage_inventory_for_toko(v_toko) then
    raise exception 'Hanya admin toko/cabang ini yang boleh catat stok rusak.'
      using errcode = '42501';
  end if;

  if v_actor is not null then
    select nullif(trim(coalesce(nama, email, '')), '')
      into v_nama
    from public.profiles
    where id = v_actor;
  end if;
  v_nama := coalesce(
    nullif(trim(coalesce(p_actor_nama, '')), ''),
    v_nama,
    ''
  );

  v_ref := nullif(trim(coalesce(p_ref_id, '')), '');
  if v_ref is null then
    v_ref := 'WO-' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
  end if;

  select greatest(coalesce(p.harga_modal, 0), 0)::bigint
    into v_modal
  from public.products p
  where upper(trim(p.toko_id)) = v_toko
    and upper(trim(p.sku)) = upper(trim(v_sku))
  limit 1;

  v_out := public.apply_stock_delta(
    v_toko,
    v_sku,
    -p_qty,
    'WRITE_OFF',
    v_alasan,
    'write_off',
    v_ref,
    v_actor,
    v_nama,
    coalesce(p_meta, '{}'::jsonb)
      || jsonb_build_object(
        'harga_modal', v_modal,
        'nilai_modal', p_qty::bigint * coalesce(v_modal, 0)
      ),
    false
  );

  return coalesce(v_out, '{}'::jsonb) || jsonb_build_object(
    'nilai_modal', p_qty::bigint * coalesce(v_modal, 0),
    'harga_modal', coalesce(v_modal, 0)
  );
end;
$$;

comment on function public.write_off_stock(text, text, integer, text, text, text, jsonb) is
  'Potong stok rusak. Qty selalu negatif. Nilai = qty × harga_modal. Bukan anon.';

revoke all on function public.write_off_stock(
  text, text, integer, text, text, text, jsonb
) from public, anon;
grant execute on function public.write_off_stock(
  text, text, integer, text, text, text, jsonb
) to authenticated, service_role;

create or replace function public.list_write_off_ledger(
  p_toko text,
  p_limit integer default 20
)
returns setof public.product_stock_ledger
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
  v_lim int := least(100, greatest(1, coalesce(p_limit, 20)));
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if v_toko is null then
    raise exception 'Toko wajib.' using errcode = '42501';
  end if;
  if not public.can_view_product_stock_ledger(v_toko) then
    raise exception 'Tidak berhak riwayat stok rusak toko ini.'
      using errcode = '42501';
  end if;

  return query
  select l.*
  from public.product_stock_ledger l
  where public.same_store_toko(l.toko_id, v_toko)
    and upper(trim(coalesce(l.reason, ''))) = 'WRITE_OFF'
  order by l.created_at desc
  limit v_lim;
end;
$$;

comment on function public.list_write_off_ledger(text, integer) is
  'Riwayat WRITE_OFF satu toko. Bukan cabang lain. Bukan anon.';

revoke all on function public.list_write_off_ledger(text, integer)
  from public, anon;
grant execute on function public.list_write_off_ledger(text, integer)
  to authenticated, service_role;

revoke all on function public.can_view_product_stock_ledger(text)
  from public, anon;
grant execute on function public.can_view_product_stock_ledger(text)
  to authenticated, service_role;
