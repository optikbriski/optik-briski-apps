-- =============================================================================
-- 000031 — Cek kebocoran stok end-to-end.
-- Apply di SQL Editor live SETELAH 000030.
--
-- Celah saat toko jalan (setelah 000026/000030):
-- - recognize_stock_variance kunci produk tanpa tenant_id
--   → SKU + PUSAT merek lain bisa ke-lock / jejak tercampur
-- - actor_id/nama dari HP
-- - alasan cukup non-kosong (1 huruf)
-- - auth.uid() null melewati can_manage
-- - UI cek kebocoran / catat selisih tanpa gate toko
-- =============================================================================

create or replace function public.can_audit_stock_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_inventory_for_toko(p_toko);
$$;

comment on function public.can_audit_stock_for_toko(text) is
  'Buka cek kebocoran + catat selisih: sama dengan hak mutasi stok toko itu.';

revoke all on function public.can_audit_stock_for_toko(text)
  from public, anon;
grant execute on function public.can_audit_stock_for_toko(text)
  to authenticated, service_role;

create or replace function public.recognize_stock_variance(
  p_toko text,
  p_sku text,
  p_alasan_text text,
  p_actor_id uuid default null,
  p_actor_nama text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_sku text := trim(p_sku);
  v_alasan text := trim(coalesce(p_alasan_text, ''));
  v_row public.products;
  v_ledger_sum integer := 0;
  v_delta integer;
  v_ledger_id uuid;
  v_tenant uuid;
  v_jwt text;
  v_actor uuid;
  v_nama text;
  v_stock integer;
begin
  v_jwt := coalesce(auth.jwt() ->> 'role', '');
  v_actor := auth.uid();
  if v_actor is null and v_jwt is distinct from 'service_role' then
    raise exception 'Login dulu.' using errcode = '42501';
  end if;

  v_tenant := public.assert_toko_in_caller_tenant(v_toko);
  if v_actor is not null
     and not public.can_audit_stock_for_toko(v_toko) then
    raise exception 'Hanya admin toko/cabang ini yang boleh catat selisih stok.'
      using errcode = '42501';
  end if;
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  if length(v_alasan) < 3 then
    raise exception 'Alasan rekognisi minimal 3 karakter.';
  end if;

  select * into v_row
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = upper(v_sku)
    and upper(trim(toko_id)) = v_toko
  for update;
  if not found then
    raise exception 'Produk % tidak ada di %', v_sku, v_toko;
  end if;

  v_stock := coalesce(v_row.stock, 0);

  select coalesce(sum(l.qty_delta), 0) into v_ledger_sum
  from public.product_stock_ledger l
  where l.product_id = v_row.id
     or (
       l.product_id is null
       and upper(trim(l.sku)) = upper(trim(v_row.sku))
       and upper(trim(l.toko_id)) = v_toko
     );

  v_delta := v_stock - v_ledger_sum;
  if v_delta = 0 then
    return jsonb_build_object(
      'ok', true,
      'changed', false,
      'message', 'Sudah sinkron',
      'sku', v_row.sku,
      'toko_id', v_toko,
      'stock', v_stock,
      'ledger_sum', v_ledger_sum
    );
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

  insert into public.product_stock_ledger (
    sku, toko_id, product_id, qty_delta, stock_before, stock_after,
    reason, alasan_text, ref_type, ref_id, actor_id, actor_nama, meta
  ) values (
    v_row.sku, v_toko, v_row.id, v_delta,
    v_stock, v_stock,
    'ADJUST',
    'Rekognisi selisih kebocoran (stok tidak diubah): ' || v_alasan,
    'integrity_fix',
    'INT-' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint,
    v_actor, v_nama,
    jsonb_build_object(
      'recognize_only', true,
      'stock', v_stock,
      'ledger_before', v_ledger_sum,
      'delta', v_delta
    )
  )
  returning id into v_ledger_id;

  return jsonb_build_object(
    'ok', true,
    'changed', true,
    'ledger_id', v_ledger_id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'stock', v_stock,
    'stock_before', v_stock,
    'stock_after', v_stock,
    'ledger_before', v_ledger_sum,
    'ledger_after', v_ledger_sum + v_delta,
    'qty_delta', v_delta
  );
end;
$$;

comment on function public.recognize_stock_variance(text, text, text, uuid, text) is
  'Lengkapi jejak kebocoran. Stok rak tidak diubah. Bukan merek lain. Bukan cabang orang.';

revoke all on function public.recognize_stock_variance(text, text, text, uuid, text)
  from public, anon;
grant execute on function public.recognize_stock_variance(text, text, text, uuid, text)
  to authenticated, service_role;
