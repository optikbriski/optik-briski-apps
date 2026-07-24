-- Riwayat revisi Add Branch / edit distribusi produk per toko (bukan RO/DO).
-- Menyimpan: produk, toko yang diubah, qty, siapa, kapan.

create table if not exists public.product_branch_revision_logs (
  id uuid primary key default gen_random_uuid(),
  product_nama text not null,
  product_sku text,
  product_barcode text,
  tokos text[] not null default '{}',
  qty_per_toko integer not null default 0,
  action text not null default 'add_branch',
  changed_by uuid references auth.users (id),
  changed_by_email text,
  changed_by_nama text,
  changed_by_role text,
  changed_by_toko text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists product_branch_revision_logs_created_idx
  on public.product_branch_revision_logs (created_at desc);
create index if not exists product_branch_revision_logs_nama_idx
  on public.product_branch_revision_logs (product_nama);
create index if not exists product_branch_revision_logs_by_idx
  on public.product_branch_revision_logs (changed_by, created_at desc);

comment on table public.product_branch_revision_logs is
  'Audit revisi Add Branch Product Master: toko, qty, actor, waktu. Bukan mutasi RO/DO.';

alter table public.product_branch_revision_logs enable row level security;

drop policy if exists product_branch_revision_logs_authenticated_all
  on public.product_branch_revision_logs;
create policy product_branch_revision_logs_authenticated_all
  on public.product_branch_revision_logs
  for all
  to authenticated
  using (true)
  with check (true);
