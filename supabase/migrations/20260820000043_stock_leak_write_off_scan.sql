-- =============================================================================
-- 000043 — Kebocoran stok: WRITE_OFF ikut Σ ledger + scan satu tenant.
-- Apply di SQL Editor live SETELAH 000042.
--
-- Celah saat toko cek kebocoran setelah catat rusak:
-- - Flutter int.tryParse qty_delta `-2.0` / stock `8.0` jadi 0
--   → WRITE_OFF tidak masuk Σ → lapor bocor palsu
-- - REST page 1000 bisa potong ledger
-- - PUSAT vs CABANG-PUSAT jadi dua kunci
-- - recognize_stock_variance belum kunci anon
-- =============================================================================

create or replace function public.can_audit_stock_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(auth.role(), '') is distinct from 'anon'
    and public.can_manage_inventory_for_toko(p_toko);
$$;

comment on function public.can_audit_stock_for_toko(text) is
  'Buka cek kebocoran + catat selisih: sama dengan hak mutasi stok toko itu. Bukan anon.';

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
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
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
    and public.same_store_toko(toko_id, v_toko)
  order by case when upper(trim(toko_id)) = v_toko then 0 else 1 end
  limit 1
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
       and public.same_store_toko(l.toko_id, v_toko)
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
  'Lengkapi jejak kebocoran. Stok rak tidak diubah. WRITE_OFF ikut Σ. Bukan anon.';

revoke all on function public.recognize_stock_variance(text, text, text, uuid, text)
  from public, anon;
grant execute on function public.recognize_stock_variance(text, text, text, uuid, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Scan stok vs Σ ledger (termasuk WRITE_OFF) — tanpa potong 1000 baris REST
-- -----------------------------------------------------------------------------
create or replace function public.stock_leak_scan(p_toko text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko, ''))), '');
  v_all boolean := false;
  v_checked int := 0;
  v_missing int := 0;
  v_wo bigint := 0;
  v_mismatches jsonb := '[]'::jsonb;
  v_stock_by jsonb := '{}'::jsonb;
  v_sold_by jsonb := '{}'::jsonb;
  v_reason jsonb := '{}'::jsonb;
  v_stock_lines jsonb := '[]'::jsonb;
  v_sold_lines jsonb := '[]'::jsonb;
begin
  if coalesce(auth.role(), '') = 'anon' then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if v_toko is not null then
    perform public.assert_toko_in_caller_tenant(v_toko);
    if not public.can_audit_stock_for_toko(v_toko) then
      raise exception 'Tidak berhak cek kebocoran toko ini.'
        using errcode = '42501';
    end if;
  elsif public.is_pusat_logistics_operator()
     or public.current_profile_role() in ('admin_pusat', 'super_admin') then
    v_all := true;
  else
    v_toko := nullif(
      upper(trim(coalesce(public.current_profile_toko_id(), ''))),
      ''
    );
    if v_toko is null then
      raise exception 'Toko wajib.' using errcode = '42501';
    end if;
    if not public.can_audit_stock_for_toko(v_toko) then
      raise exception 'Tidak berhak cek kebocoran toko ini.'
        using errcode = '42501';
    end if;
  end if;

  select
    count(*)::int,
    count(*) filter (
      where nullif(btrim(coalesce(p.sku, '')), '') is null
         or upper(btrim(p.sku)) like 'NOSKU-%'
    )::int
  into v_checked, v_missing
  from public.products p
  where p.tenant_id is not distinct from public.current_tenant_id()
    and (
      v_all
      or public.same_store_toko(p.toko_id, v_toko)
    );

  select coalesce(sum(abs(coalesce(l.qty_delta, 0))), 0)
    into v_wo
  from public.product_stock_ledger l
  where public.toko_belongs_to_current_tenant(l.toko_id)
    and upper(btrim(coalesce(l.reason, ''))) = 'WRITE_OFF'
    and (
      v_all
      or public.same_store_toko(l.toko_id, v_toko)
    );

  with ledger_reason as (
    select
      upper(btrim(l.sku)) as sku_k,
      case
        when public.is_pusat_warehouse(l.toko_id) then 'PUSAT'
        else upper(btrim(l.toko_id))
      end as toko_k,
      upper(btrim(coalesce(l.reason, 'UNKNOWN'))) as reason,
      sum(coalesce(l.qty_delta, 0))::bigint as qty
    from public.product_stock_ledger l
    where public.toko_belongs_to_current_tenant(l.toko_id)
      and nullif(btrim(coalesce(l.sku, '')), '') is not null
      and (
        v_all
        or public.same_store_toko(l.toko_id, v_toko)
      )
    group by 1, 2, 3
  ),
  ledger_sku as (
    select
      sku_k,
      toko_k,
      sum(qty) as ledger_sum,
      jsonb_object_agg(reason, qty) as by_reason
    from ledger_reason
    group by 1, 2
  )
  select coalesce(jsonb_agg(row_data), '[]'::jsonb)
    into v_mismatches
  from (
    select jsonb_build_object(
      'sku', p.sku,
      'toko_id', case
        when public.is_pusat_warehouse(p.toko_id) then 'PUSAT'
        else upper(btrim(p.toko_id))
      end,
      'nama', p.nama,
      'product_id', p.id,
      'stock', coalesce(p.stock, 0),
      'ledger_sum', coalesce(a.ledger_sum, 0),
      'delta', coalesce(p.stock, 0) - coalesce(a.ledger_sum, 0),
      'ledger_by_reason', coalesce(a.by_reason, '{}'::jsonb)
    ) as row_data
    from public.products p
    left join ledger_sku a
      on a.sku_k = upper(btrim(p.sku))
     and a.toko_k = case
       when public.is_pusat_warehouse(p.toko_id) then 'PUSAT'
       else upper(btrim(p.toko_id))
     end
    where p.tenant_id is not distinct from public.current_tenant_id()
      and (
        v_all
        or public.same_store_toko(p.toko_id, v_toko)
      )
      and nullif(btrim(coalesce(p.sku, '')), '') is not null
      and upper(btrim(p.sku)) not like 'NOSKU-%'
      and nullif(btrim(coalesce(p.toko_id, '')), '') is not null
      and upper(btrim(p.toko_id)) is distinct from 'NULL'
      and coalesce(p.stock, 0) is distinct from coalesce(a.ledger_sum, 0)
    order by abs(coalesce(p.stock, 0) - coalesce(a.ledger_sum, 0)) desc
    limit 200
  ) x;

  select coalesce(jsonb_object_agg(toko_k, qty), '{}'::jsonb)
    into v_stock_by
  from (
    select
      case
        when public.is_pusat_warehouse(p.toko_id) then 'PUSAT'
        else upper(btrim(p.toko_id))
      end as toko_k,
      sum(greatest(coalesce(p.stock, 0), 0))::bigint as qty
    from public.products p
    where p.tenant_id is not distinct from public.current_tenant_id()
      and (
        v_all
        or public.same_store_toko(p.toko_id, v_toko)
      )
    group by 1
  ) s;

  select coalesce(jsonb_object_agg(reason, qty), '{}'::jsonb)
    into v_reason
  from (
    select
      upper(btrim(coalesce(l.reason, 'UNKNOWN'))) as reason,
      sum(coalesce(l.qty_delta, 0))::bigint as qty
    from public.product_stock_ledger l
    where public.toko_belongs_to_current_tenant(l.toko_id)
      and (
        v_all
        or public.same_store_toko(l.toko_id, v_toko)
      )
    group by 1
  ) r;

  select coalesce(jsonb_object_agg(toko_k, qty), '{}'::jsonb)
    into v_sold_by
  from (
    select
      case
        when public.is_pusat_warehouse(l.toko_id) then 'PUSAT'
        else upper(btrim(l.toko_id))
      end as toko_k,
      sum(abs(coalesce(l.qty_delta, 0)))::bigint as qty
    from public.product_stock_ledger l
    where public.toko_belongs_to_current_tenant(l.toko_id)
      and upper(btrim(coalesce(l.reason, ''))) = 'SALE'
      and l.created_at >= (timezone('utc', now()) - interval '30 days')
      and (
        v_all
        or public.same_store_toko(l.toko_id, v_toko)
      )
    group by 1
  ) s;

  select coalesce(jsonb_agg(row_data), '[]'::jsonb)
    into v_stock_lines
  from (
    select jsonb_build_object(
      'toko_id', toko_k,
      'sku', sku,
      'nama', nama,
      'qty', qty
    ) as row_data
    from (
      select
        case
          when public.is_pusat_warehouse(p.toko_id) then 'PUSAT'
          else upper(btrim(p.toko_id))
        end as toko_k,
        p.sku,
        p.nama,
        greatest(coalesce(p.stock, 0), 0)::bigint as qty,
        row_number() over (
          partition by case
            when public.is_pusat_warehouse(p.toko_id) then 'PUSAT'
            else upper(btrim(p.toko_id))
          end
          order by greatest(coalesce(p.stock, 0), 0) desc
        ) as rn
      from public.products p
      where p.tenant_id is not distinct from public.current_tenant_id()
        and greatest(coalesce(p.stock, 0), 0) > 0
        and nullif(btrim(coalesce(p.sku, '')), '') is not null
        and upper(btrim(p.sku)) not like 'NOSKU-%'
        and (
          v_all
          or public.same_store_toko(p.toko_id, v_toko)
        )
    ) x
    where rn <= 40
  ) y;

  select coalesce(jsonb_agg(row_data), '[]'::jsonb)
    into v_sold_lines
  from (
    select jsonb_build_object(
      'toko_id', toko_k,
      'sku', sku,
      'nama', sku,
      'qty', qty
    ) as row_data
    from (
      select
        case
          when public.is_pusat_warehouse(l.toko_id) then 'PUSAT'
          else upper(btrim(l.toko_id))
        end as toko_k,
        l.sku,
        sum(abs(coalesce(l.qty_delta, 0)))::bigint as qty,
        row_number() over (
          partition by case
            when public.is_pusat_warehouse(l.toko_id) then 'PUSAT'
            else upper(btrim(l.toko_id))
          end
          order by sum(abs(coalesce(l.qty_delta, 0))) desc
        ) as rn
      from public.product_stock_ledger l
      where public.toko_belongs_to_current_tenant(l.toko_id)
        and upper(btrim(coalesce(l.reason, ''))) = 'SALE'
        and l.created_at >= (timezone('utc', now()) - interval '30 days')
        and (
          v_all
          or public.same_store_toko(l.toko_id, v_toko)
        )
      group by 1, 2
    ) x
    where rn <= 40
  ) y;

  return jsonb_build_object(
    'checked', v_checked,
    'missing_sku', v_missing,
    'write_off_qty', v_wo,
    'mismatches', v_mismatches,
    'stock_by_toko', v_stock_by,
    'sold_by_toko', v_sold_by,
    'ledger_by_reason', v_reason,
    'stock_lines', v_stock_lines,
    'sold_lines', v_sold_lines
  );
end;
$$;

comment on function public.stock_leak_scan(text) is
  'Scan stok vs Σ ledger termasuk WRITE_OFF. Bukan potong 1000 REST. Bukan anon.';

revoke all on function public.stock_leak_scan(text) from public, anon;
grant execute on function public.stock_leak_scan(text)
  to authenticated, service_role;
