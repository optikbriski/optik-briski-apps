-- Stok Real / Pending / Total (tersedia)
-- real     = products.stock              (fisik on-hand per toko)
-- pending  = products.reserved_qty       (booking draft DO/RO/POS)
-- total/available = greatest(stock - reserved_qty, 0)

alter table public.products
  add column if not exists reserved_qty integer not null default 0;

alter table public.products
  drop constraint if exists products_reserved_qty_nonneg;
alter table public.products
  add constraint products_reserved_qty_nonneg check (reserved_qty >= 0);

comment on column public.products.stock is
  'Stok REAL (riil) on-hand per toko. Hanya berubah saat transaksi sukses (SALE/TRANSFER/ADJUST/...).';
comment on column public.products.reserved_qty is
  'Stok PENDING (bayangan) outbound: booking draft DO/RO/POS. Bukan stok dijual.';

create or replace function public.product_available_qty(p_stock integer, p_reserved integer)
returns integer
language sql
immutable
as $$
  select greatest(coalesce(p_stock, 0) - coalesce(p_reserved, 0), 0);
$$;

create table if not exists public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  sku text not null,
  toko_id text not null,
  qty integer not null check (qty > 0),
  kind text not null check (kind in ('DO_DRAFT', 'DO_PREPARING', 'RO', 'POS_HOLD')),
  ref_type text not null,
  ref_id text not null,
  status text not null default 'active'
    check (status in ('active', 'released', 'consumed')),
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists stock_reservations_active_sku_toko_idx
  on public.stock_reservations (toko_id, sku)
  where status = 'active';

create unique index if not exists stock_reservations_active_ref_uidx
  on public.stock_reservations (kind, ref_type, ref_id, sku, toko_id)
  where status = 'active';

alter table public.stock_reservations enable row level security;

drop policy if exists stock_reservations_auth_all on public.stock_reservations;
create policy stock_reservations_auth_all on public.stock_reservations
  for all to authenticated
  using (true)
  with check (true);

-- Recompute products.reserved_qty from active reservations
create or replace function public.recompute_product_reserved_qty(
  p_toko text,
  p_sku text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_sku text := trim(p_sku);
  v_sum integer;
begin
  select coalesce(sum(qty), 0)::integer into v_sum
  from public.stock_reservations
  where status = 'active'
    and upper(trim(toko_id)) = v_toko
    and upper(trim(sku)) = upper(trim(v_sku));

  update public.products
  set reserved_qty = v_sum
  where upper(trim(toko_id)) = v_toko
    and upper(trim(sku)) = upper(trim(v_sku));

  return v_sum;
end;
$$;

create or replace function public.reserve_stock(
  p_toko text,
  p_sku text,
  p_qty integer,
  p_kind text,
  p_ref_type text,
  p_ref_id text,
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
  v_row public.products;
  v_available integer;
  v_res public.stock_reservations;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'qty reservasi harus > 0';
  end if;
  if p_kind not in ('DO_DRAFT', 'DO_PREPARING', 'RO', 'POS_HOLD') then
    raise exception 'kind tidak valid: %', p_kind;
  end if;

  select * into v_row
  from public.products
  where upper(trim(sku)) = upper(trim(v_sku))
    and upper(trim(toko_id)) = v_toko
  for update;

  if not found then
    raise exception 'Produk % tidak ada di %', v_sku, v_toko;
  end if;

  -- Upsert-ish: if active reservation for same ref+sku exists, replace qty
  update public.stock_reservations
  set status = 'released', updated_at = now()
  where status = 'active'
    and kind = p_kind
    and ref_type = p_ref_type
    and ref_id = p_ref_id
    and upper(trim(sku)) = upper(trim(v_sku))
    and upper(trim(toko_id)) = v_toko;

  perform public.recompute_product_reserved_qty(v_toko, v_sku);

  select * into v_row
  from public.products
  where id = v_row.id
  for update;

  v_available := public.product_available_qty(v_row.stock, v_row.reserved_qty);
  if v_available < p_qty then
    raise exception
      'Stok tersedia tidak cukup di % untuk SKU % (real %, pending %, tersedia %, minta %)',
      v_toko, v_sku, v_row.stock, v_row.reserved_qty, v_available, p_qty;
  end if;

  insert into public.stock_reservations (
    sku, toko_id, qty, kind, ref_type, ref_id, status, meta
  ) values (
    v_row.sku, v_toko, p_qty, p_kind, p_ref_type, p_ref_id, 'active',
    coalesce(p_meta, '{}'::jsonb)
  )
  returning * into v_res;

  perform public.recompute_product_reserved_qty(v_toko, v_sku);

  select stock, reserved_qty into v_row.stock, v_row.reserved_qty
  from public.products where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'reservation_id', v_res.id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'qty', p_qty,
    'real_stock', v_row.stock,
    'pending_stock', v_row.reserved_qty,
    'available_qty', public.product_available_qty(v_row.stock, v_row.reserved_qty)
  );
end;
$$;

create or replace function public.release_reservation(
  p_kind text,
  p_ref_type text,
  p_ref_id text,
  p_sku text default null,
  p_toko text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select *
    from public.stock_reservations
    where status = 'active'
      and kind = p_kind
      and ref_type = p_ref_type
      and ref_id = p_ref_id
      and (p_sku is null or upper(trim(sku)) = upper(trim(p_sku)))
      and (p_toko is null or upper(trim(toko_id)) = upper(trim(p_toko)))
    for update
  loop
    update public.stock_reservations
    set status = 'released', updated_at = now()
    where id = r.id;
    perform public.recompute_product_reserved_qty(r.toko_id, r.sku);
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'released', v_count);
end;
$$;

-- Consume active reservations for a ref and TRANSFER_OUT real stock (to TRANSIT).
create or replace function public.consume_reservation_and_transfer_out(
  p_kind text,
  p_ref_type text,
  p_ref_id text,
  p_toko text,
  p_alasan_text text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_ledger_ref_type text default null,
  p_ledger_ref_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_out jsonb;
  v_results jsonb := '[]'::jsonb;
  v_toko text := upper(trim(p_toko));
begin
  for r in
    select *
    from public.stock_reservations
    where status = 'active'
      and kind = p_kind
      and ref_type = p_ref_type
      and ref_id = p_ref_id
      and upper(trim(toko_id)) = v_toko
    for update
  loop
    update public.stock_reservations
    set status = 'consumed', updated_at = now()
    where id = r.id;

    perform public.recompute_product_reserved_qty(r.toko_id, r.sku);

    v_out := public.apply_stock_delta(
      r.toko_id,
      r.sku,
      -r.qty,
      'TRANSFER_OUT',
      coalesce(p_alasan_text, 'Consume reservation → TRANSIT'),
      coalesce(p_ledger_ref_type, p_ref_type),
      coalesce(p_ledger_ref_id, p_ref_id),
      p_actor_id,
      p_actor_nama,
      jsonb_build_object('reservation_id', r.id, 'kind', p_kind),
      false
    );
    v_results := v_results || jsonb_build_array(v_out);
  end loop;

  return jsonb_build_object('ok', true, 'items', v_results);
end;
$$;

-- SALE / outbound must respect available (real - pending)
create or replace function public.apply_stock_delta(
  p_toko text,
  p_sku text,
  p_qty_delta integer,
  p_reason text,
  p_alasan_text text default null,
  p_ref_type text default null,
  p_ref_id text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_meta jsonb default '{}'::jsonb,
  p_allow_create boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_sku text := trim(p_sku);
  v_row public.products;
  v_before integer;
  v_after integer;
  v_ledger_id uuid;
  v_available integer;
begin
  if p_qty_delta is null or p_qty_delta = 0 then
    raise exception 'qty_delta tidak boleh 0';
  end if;
  if p_reason not in (
    'OPENING','TRANSFER_OUT','TRANSFER_IN','RETURN_OUT','RETURN_IN',
    'SALE','WRITE_OFF','ADJUST'
  ) then
    raise exception 'reason tidak valid: %', p_reason;
  end if;
  if p_reason in ('WRITE_OFF','ADJUST')
     and (p_alasan_text is null or trim(p_alasan_text) = '') then
    raise exception 'alasan_text wajib untuk %', p_reason;
  end if;

  if p_allow_create then
    v_row := public.ensure_product_at_toko(v_sku, v_toko, coalesce(p_meta->'product', '{}'::jsonb));
  else
    select * into v_row
    from public.products
    where upper(trim(sku)) = upper(trim(v_sku))
      and upper(trim(toko_id)) = v_toko
    for update;
    if not found then
      raise exception 'Produk % tidak ada di %', v_sku, v_toko;
    end if;
  end if;

  select * into v_row
  from public.products
  where id = v_row.id
  for update;

  v_before := coalesce(v_row.stock, 0);
  v_after := v_before + p_qty_delta;
  if v_after < 0 then
    raise exception 'Stok real tidak cukup di % untuk SKU % (real %, delta %)',
      v_toko, v_sku, v_before, p_qty_delta;
  end if;

  -- Penurunan stok (kecuali ADJUST opname) tidak boleh menembus pending booking
  if p_qty_delta < 0 and p_reason in ('SALE', 'TRANSFER_OUT', 'WRITE_OFF', 'RETURN_OUT') then
    v_available := public.product_available_qty(v_before, v_row.reserved_qty);
    if abs(p_qty_delta) > v_available then
      raise exception
        'Stok tersedia tidak cukup di % untuk SKU % (real %, pending %, tersedia %, minta %)',
        v_toko, v_sku, v_before, v_row.reserved_qty, v_available, abs(p_qty_delta);
    end if;
  end if;

  if v_after < coalesce(v_row.reserved_qty, 0) and p_reason = 'ADJUST' and p_qty_delta < 0 then
    raise exception
      'Revisi stok tidak boleh di bawah pending booking (real target %, pending %)',
      v_after, v_row.reserved_qty;
  end if;

  update public.products
  set stock = v_after
  where id = v_row.id;

  insert into public.product_stock_ledger (
    sku, toko_id, product_id, qty_delta, stock_before, stock_after,
    reason, alasan_text, ref_type, ref_id, actor_id, actor_nama, meta
  ) values (
    v_row.sku, v_toko, v_row.id, p_qty_delta, v_before, v_after,
    p_reason, p_alasan_text, p_ref_type, p_ref_id, p_actor_id, p_actor_nama,
    coalesce(p_meta, '{}'::jsonb)
  )
  returning id into v_ledger_id;

  return jsonb_build_object(
    'ok', true,
    'ledger_id', v_ledger_id,
    'product_id', v_row.id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'stock_before', v_before,
    'stock_after', v_after,
    'qty_delta', p_qty_delta,
    'reason', p_reason,
    'pending_stock', coalesce(v_row.reserved_qty, 0),
    'available_qty', public.product_available_qty(v_after, v_row.reserved_qty)
  );
end;
$$;

grant execute on function public.product_available_qty(integer, integer) to authenticated;
grant execute on function public.recompute_product_reserved_qty(text, text) to authenticated;
grant execute on function public.reserve_stock(text, text, integer, text, text, text, jsonb) to authenticated;
grant execute on function public.release_reservation(text, text, text, text, text) to authenticated;
grant execute on function public.consume_reservation_and_transfer_out(text, text, text, text, text, uuid, text, text, text) to authenticated;

-- Backfill: open DO drafts that already hard-cut PUSAT → restore real + create pending
do $$
declare
  d record;
  itm jsonb;
  v_sku text;
  v_qty integer;
begin
  for d in select id, items from public.draft_pengiriman
  loop
    begin
      for itm in select * from jsonb_array_elements(d.items::jsonb)
      loop
        v_sku := coalesce(nullif(trim(itm->>'sku'), ''), nullif(trim(itm->>'barcode'), ''));
        v_qty := coalesce((itm->>'qty')::integer, 0);
        if v_sku is null or v_qty <= 0 then
          continue;
        end if;

        -- Restore real that was cut at draft time
        begin
          perform public.apply_stock_delta(
            'PUSAT', v_sku, v_qty, 'ADJUST',
            'Backfill riil←bayangan: restore cut draft DO',
            'draft', d.id::text, null, 'system',
            jsonb_build_object('backfill', true), false
          );
        exception when others then
          null; -- skip if product missing
        end;

        begin
          perform public.reserve_stock(
            'PUSAT', v_sku, v_qty, 'DO_DRAFT', 'draft', d.id::text,
            jsonb_build_object('backfill', true)
          );
        exception when others then
          null;
        end;
      end loop;
    exception when others then
      null;
    end;
  end loop;
end;
$$;

-- Backfill: open PREPARING stock moves — restore real + DO_PREPARING reservation
do $$
declare
  m record;
  itm jsonb;
  v_sku text;
  v_qty integer;
  raw text;
  arr jsonb;
begin
  for m in
    select id, keterangan
    from public.stock_move_history
    where upper(trim(status)) in ('PREPARING', 'WAITING')
      and upper(trim(coalesce(dari_lokasi, 'PUSAT'))) = 'PUSAT'
  loop
    raw := m.keterangan;
    begin
      arr := raw::jsonb;
      if jsonb_typeof(arr) <> 'array' then
        -- RO style: "... | [{...}]"
        if position('[' in raw) > 0 then
          arr := substring(raw from position('[' in raw))::jsonb;
        else
          continue;
        end if;
      end if;
    exception when others then
      continue;
    end;

    for itm in select * from jsonb_array_elements(arr)
    loop
      v_sku := coalesce(nullif(trim(itm->>'sku'), ''), nullif(trim(itm->>'barcode'), ''));
      v_qty := coalesce((itm->>'qty')::integer, 0);
      if v_sku is null or v_qty <= 0 then
        continue;
      end if;
      begin
        perform public.apply_stock_delta(
          'PUSAT', v_sku, v_qty, 'ADJUST',
          'Backfill riil←bayangan: restore cut PREPARING DO',
          'stock_move', m.id::text, null, 'system',
          jsonb_build_object('backfill', true), false
        );
      exception when others then null;
      end;
      begin
        perform public.reserve_stock(
          'PUSAT', v_sku, v_qty, 'DO_PREPARING', 'stock_move', m.id::text,
          jsonb_build_object('backfill', true)
        );
      exception when others then null;
      end;
    end loop;
  end loop;
end;
$$;

-- Sync existing RO pending_requests.reserved_qty into central reservations
do $$
declare
  r record;
  v_sku text;
begin
  for r in
    select id, sku, nama_produk, reserved_qty
    from public.pending_requests
    where reserved_qty > 0
      and upper(trim(status)) in ('APPROVED', 'PREPARING')
  loop
    v_sku := nullif(trim(r.sku), '');
    if v_sku is null then
      select sku into v_sku
      from public.products
      where upper(trim(toko_id)) = 'PUSAT'
        and lower(trim(nama)) = lower(trim(r.nama_produk))
      limit 1;
    end if;
    if v_sku is null then
      continue;
    end if;
    begin
      perform public.reserve_stock(
        'PUSAT', v_sku, r.reserved_qty, 'RO', 'pending_request', r.id::text,
        jsonb_build_object('backfill', true)
      );
    exception when others then null;
    end;
  end loop;
end;
$$;
