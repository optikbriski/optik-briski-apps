-- Partial fulfillment: per-line RO / READY / DIAMBIL
-- Aggregate sales.tracking_status tetap dipakai; line adalah sumber kebenaran.

alter table public.sales_items
  add column if not exists needs_fulfillment boolean not null default false,
  add column if not exists fulfillment_status text not null default 'READY',
  add column if not exists diambil_at timestamptz,
  add column if not exists pending_request_id bigint;

comment on column public.sales_items.needs_fulfillment is
  'True jika line butuh RO / custom / stok pending saat checkout.';
comment on column public.sales_items.fulfillment_status is
  'PENDING_RO | READY | DIAMBIL';
comment on column public.sales_items.diambil_at is
  'Waktu serah terima line (partial pickup).';
comment on column public.sales_items.pending_request_id is
  'FK lunak ke pending_requests.id untuk RO terkait.';

alter table public.sales_items
  drop constraint if exists sales_items_fulfillment_status_chk;

alter table public.sales_items
  add constraint sales_items_fulfillment_status_chk
  check (fulfillment_status in ('PENDING_RO', 'READY', 'DIAMBIL'));

create index if not exists sales_items_fulfillment_status_idx
  on public.sales_items (sale_id, fulfillment_status);

create index if not exists sales_items_pending_request_id_idx
  on public.sales_items (pending_request_id)
  where pending_request_id is not null;

alter table public.pending_requests
  add column if not exists sale_id uuid,
  add column if not exists sale_item_id uuid;

comment on column public.pending_requests.sale_id is
  'FK lunak ke sales.id setelah checkout.';
comment on column public.pending_requests.sale_item_id is
  'FK lunak ke sales_items.id untuk partial fulfillment.';

create index if not exists pending_requests_sale_id_idx
  on public.pending_requests (sale_id)
  where sale_id is not null;

create index if not exists pending_requests_sale_item_id_idx
  on public.pending_requests (sale_item_id)
  where sale_item_id is not null;

-- Optional FKs (nullable; jangan gagalkan RO lama tanpa sale)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pending_requests_sale_id_fkey'
  ) then
    alter table public.pending_requests
      add constraint pending_requests_sale_id_fkey
      foreign key (sale_id) references public.sales (id) on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'pending_requests_sale_item_id_fkey'
  ) then
    alter table public.pending_requests
      add constraint pending_requests_sale_item_id_fkey
      foreign key (sale_item_id) references public.sales_items (id) on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'sales_items_pending_request_id_fkey'
  ) then
    alter table public.sales_items
      add constraint sales_items_pending_request_id_fkey
      foreign key (pending_request_id) references public.pending_requests (id)
      on delete set null;
  end if;
end $$;
