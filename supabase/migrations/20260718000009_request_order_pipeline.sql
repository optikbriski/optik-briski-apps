-- Request Order pipeline: Approve → Preparing → Shipping → Success + reservasi stok

alter table public.pending_requests
  add column if not exists reserved_qty integer not null default 0,
  add column if not exists stock_move_id uuid,
  add column if not exists stock_move_resi text,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references auth.users (id) on delete set null;

comment on column public.pending_requests.reserved_qty is
  'Qty direservasi di Pusat saat APPROVED/PREPARING; 0 setelah SHIPPING/REJECTED.';
comment on column public.pending_requests.stock_move_id is
  'FK soft ke stock_move_history.id saat SHIPPING.';
comment on column public.pending_requests.stock_move_resi is
  'Nomor resi DO yang dibuat saat Shipping.';

create index if not exists pending_requests_status_sku_idx
  on public.pending_requests (status, sku);

create index if not exists pending_requests_reserve_idx
  on public.pending_requests (status, reserved_qty)
  where reserved_qty > 0;

create index if not exists pending_requests_stock_move_idx
  on public.pending_requests (stock_move_id)
  where stock_move_id is not null;
