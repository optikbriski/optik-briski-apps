-- =============================================================================
-- Stock sync 100%: SKU canonical, master metadata sync, ledger, atomic RPCs
-- =============================================================================

-- 1) Backfill SKU
update public.products
set sku = nullif(trim(barcode), '')
where (sku is null or trim(sku) = '')
  and barcode is not null
  and trim(barcode) <> ''
  and trim(barcode) <> '-';

update public.products
set sku = 'NOSKU-' || id::text
where sku is null or trim(sku) = '';

-- Resolve duplicate (sku, toko_id): keep oldest, suffix others
with dups as (
  select id,
         sku,
         toko_id,
         row_number() over (partition by upper(trim(sku)), upper(trim(toko_id)) order by created_at asc nulls last, id) as rn
  from public.products
)
update public.products p
set sku = p.sku || '-DUP-' || substr(p.id::text, 1, 8)
from dups d
where p.id = d.id
  and d.rn > 1;

-- 2) Constraints
create unique index if not exists products_sku_toko_unique
  on public.products (upper(trim(sku)), upper(trim(toko_id)));

alter table public.products
  alter column sku set not null;

-- 3) Ledger: every stock change has a reason
create table if not exists public.product_stock_ledger (
  id uuid primary key default gen_random_uuid(),
  sku text not null,
  toko_id text not null references public.toko_id (id),
  product_id uuid references public.products (id) on delete set null,
  qty_delta integer not null,
  stock_before integer not null,
  stock_after integer not null,
  reason text not null,
  alasan_text text,
  ref_type text,
  ref_id text,
  actor_id uuid,
  actor_nama text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint product_stock_ledger_reason_chk check (
    reason in (
      'OPENING',
      'TRANSFER_OUT',
      'TRANSFER_IN',
      'RETURN_OUT',
      'RETURN_IN',
      'SALE',
      'WRITE_OFF',
      'ADJUST'
    )
  ),
  constraint product_stock_ledger_delta_chk check (qty_delta <> 0)
);

create index if not exists product_stock_ledger_sku_toko_idx
  on public.product_stock_ledger (sku, toko_id, created_at desc);
create index if not exists product_stock_ledger_reason_idx
  on public.product_stock_ledger (reason, created_at desc);
create index if not exists product_stock_ledger_ref_idx
  on public.product_stock_ledger (ref_type, ref_id);

comment on table public.product_stock_ledger is
  'Jejak setiap +/- stok: SALE, TRANSFER, RETURN, WRITE_OFF, OPENING, ADJUST.';

alter table public.product_stock_ledger enable row level security;

drop policy if exists product_stock_ledger_authenticated_all
  on public.product_stock_ledger;
create policy product_stock_ledger_authenticated_all
  on public.product_stock_ledger
  for all
  to authenticated
  using (true)
  with check (true);

-- Backfill OPENING so existing non-zero stock has a ledger baseline
insert into public.product_stock_ledger (
  sku, toko_id, product_id, qty_delta, stock_before, stock_after,
  reason, alasan_text, ref_type, meta
)
select
  p.sku,
  p.toko_id,
  p.id,
  p.stock,
  0,
  p.stock,
  'OPENING',
  'Backfill stok existing saat migrasi sync',
  'migration',
  jsonb_build_object('migration', '20260724000012')
from public.products p
where p.stock <> 0
  and not exists (
    select 1 from public.product_stock_ledger l
    where l.product_id = p.id and l.reason = 'OPENING' and l.ref_type = 'migration'
  );

-- 4) Mirror products.stock -> inventory_stocks
create or replace function public.products_mirror_inventory_stocks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.inventory_stocks
    where toko_id = old.toko_id and sku = old.sku;
    return old;
  end if;

  if new.sku is null or trim(new.sku) = '' then
    return new;
  end if;

  insert into public.inventory_stocks (toko_id, sku, stok)
  values (new.toko_id, new.sku, coalesce(new.stock, 0))
  on conflict (toko_id, sku) do update
    set stok = excluded.stok;

  if tg_op = 'UPDATE'
     and old.sku is distinct from new.sku
     and old.sku is not null then
    delete from public.inventory_stocks
    where toko_id = old.toko_id and sku = old.sku;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_products_mirror_inventory on public.products;
create trigger trg_products_mirror_inventory
  after insert or update of stock, sku, toko_id or delete
  on public.products
  for each row
  execute function public.products_mirror_inventory_stocks();

-- One-shot mirror sync
insert into public.inventory_stocks (toko_id, sku, stok)
select toko_id, sku, coalesce(stock, 0)
from public.products
where sku is not null and trim(sku) <> ''
on conflict (toko_id, sku) do update
  set stok = excluded.stok;

-- 5) Sync master metadata by SKU (skip stock / toko_id / id)
create or replace function public.products_sync_master_by_sku()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;
  if new.sku is null or trim(new.sku) = '' then
    return new;
  end if;

  -- Only when master fields change
  if new.nama is not distinct from old.nama
     and new.harga is not distinct from old.harga
     and new.harga_jual is not distinct from old.harga_jual
     and new.harga_modal is not distinct from old.harga_modal
     and new.kategori is not distinct from old.kategori
     and new.sub_kategori is not distinct from old.sub_kategori
     and new.barcode is not distinct from old.barcode
     and new.warna is not distinct from old.warna
     and new.jenis_lensa is not distinct from old.jenis_lensa
     and new.sph_r is not distinct from old.sph_r
     and new.sph_l is not distinct from old.sph_l
     and new.cyl_r is not distinct from old.cyl_r
     and new.cyl_l is not distinct from old.cyl_l
     and new.add_r is not distinct from old.add_r
     and new.add_l is not distinct from old.add_l
     and new.image_url is not distinct from old.image_url
     and new.foto_url is not distinct from old.foto_url then
    return new;
  end if;

  -- Prevent recursive loops
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  update public.products p
  set
    nama = new.nama,
    harga = new.harga,
    harga_jual = new.harga_jual,
    harga_modal = new.harga_modal,
    kategori = new.kategori,
    sub_kategori = new.sub_kategori,
    barcode = new.barcode,
    warna = new.warna,
    jenis_lensa = new.jenis_lensa,
    sph_r = new.sph_r,
    sph_l = new.sph_l,
    cyl_r = new.cyl_r,
    cyl_l = new.cyl_l,
    add_r = new.add_r,
    add_l = new.add_l,
    image_url = new.image_url,
    foto_url = new.foto_url
  where upper(trim(p.sku)) = upper(trim(new.sku))
    and p.id <> new.id;

  return new;
end;
$$;

drop trigger if exists trg_products_sync_master_by_sku on public.products;
create trigger trg_products_sync_master_by_sku
  after update on public.products
  for each row
  execute function public.products_sync_master_by_sku();

-- 6) Ensure product row exists at toko (copy master fields from PUSAT / any)
create or replace function public.ensure_product_at_toko(
  p_sku text,
  p_toko text,
  p_template jsonb default '{}'::jsonb
)
returns public.products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_toko text := upper(trim(p_toko));
  v_row public.products;
  v_src public.products;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  if v_toko is null or v_toko = '' then
    raise exception 'Toko wajib';
  end if;

  select * into v_row
  from public.products
  where upper(trim(sku)) = v_sku
    and upper(trim(toko_id)) = v_toko
  limit 1;

  if found then
    return v_row;
  end if;

  select * into v_src
  from public.products
  where upper(trim(sku)) = v_sku
  order by case when upper(trim(toko_id)) = 'PUSAT' then 0 else 1 end, created_at
  limit 1;

  if not found then
    insert into public.products (
      nama, harga, harga_jual, harga_modal, kategori, sub_kategori,
      barcode, sku, warna, jenis_lensa, toko_id, stock
    ) values (
      coalesce(p_template->>'nama', v_sku),
      coalesce((p_template->>'harga')::bigint, 0),
      coalesce((p_template->>'harga_jual')::bigint, (p_template->>'harga')::bigint, 0),
      coalesce((p_template->>'harga_modal')::bigint, 0),
      coalesce(p_template->>'kategori', 'Lainnya'),
      p_template->>'sub_kategori',
      coalesce(nullif(p_template->>'barcode', ''), v_sku),
      v_sku,
      p_template->>'warna',
      p_template->>'jenis_lensa',
      v_toko,
      0
    )
    returning * into v_row;
    return v_row;
  end if;

  insert into public.products (
    nama, harga, harga_jual, harga_modal, kategori, sub_kategori,
    barcode, sku, warna, jenis_lensa, sph_r, sph_l, cyl_r, cyl_l, add_r, add_l,
    image_url, foto_url, toko_id, stock
  ) values (
    v_src.nama, v_src.harga, v_src.harga_jual, v_src.harga_modal,
    v_src.kategori, v_src.sub_kategori,
    v_src.barcode, v_src.sku, v_src.warna, v_src.jenis_lensa,
    v_src.sph_r, v_src.sph_l, v_src.cyl_r, v_src.cyl_l, v_src.add_r, v_src.add_l,
    v_src.image_url, v_src.foto_url, v_toko, 0
  )
  returning * into v_row;

  return v_row;
end;
$$;

-- 7) Atomic single-location stock delta + ledger
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
    raise exception 'Stok tidak cukup di % untuk SKU % (stok %, delta %)',
      v_toko, v_sku, v_before, p_qty_delta;
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
    'reason', p_reason
  );
end;
$$;

-- 8) Atomic transfer: -from +to in one transaction
create or replace function public.apply_stock_transfer(
  p_from_toko text,
  p_to_toko text,
  p_sku text,
  p_qty integer,
  p_reason_out text default 'TRANSFER_OUT',
  p_reason_in text default 'TRANSFER_IN',
  p_alasan_text text default null,
  p_ref_type text default null,
  p_ref_id text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_out jsonb;
  v_in jsonb;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'qty transfer harus > 0';
  end if;
  if upper(trim(p_from_toko)) = upper(trim(p_to_toko)) then
    raise exception 'from_toko dan to_toko tidak boleh sama';
  end if;

  v_out := public.apply_stock_delta(
    p_from_toko, p_sku, -p_qty, p_reason_out, p_alasan_text,
    p_ref_type, p_ref_id, p_actor_id, p_actor_nama, p_meta, false
  );
  v_in := public.apply_stock_delta(
    p_to_toko, p_sku, p_qty, p_reason_in, p_alasan_text,
    p_ref_type, p_ref_id, p_actor_id, p_actor_nama, p_meta, true
  );

  return jsonb_build_object('ok', true, 'out', v_out, 'in', v_in, 'qty', p_qty);
end;
$$;

grant execute on function public.ensure_product_at_toko(text, text, jsonb) to authenticated;
grant execute on function public.apply_stock_delta(text, text, integer, text, text, text, text, uuid, text, jsonb, boolean) to authenticated;
grant execute on function public.apply_stock_transfer(text, text, text, integer, text, text, text, text, text, uuid, text, jsonb) to authenticated;

-- Alias name used in plan docs
create or replace function public.apply_stock_move(
  p_from_toko text,
  p_to_toko text,
  p_sku text,
  p_qty integer,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.apply_stock_transfer(
    p_from_toko, p_to_toko, p_sku, p_qty,
    'TRANSFER_OUT', 'TRANSFER_IN',
    p_meta->>'alasan_text',
    coalesce(p_meta->>'ref_type', 'stock_move'),
    p_meta->>'ref_id',
    nullif(p_meta->>'actor_id', '')::uuid,
    p_meta->>'actor_nama',
    p_meta
  );
end;
$$;

grant execute on function public.apply_stock_move(text, text, text, integer, jsonb) to authenticated;
