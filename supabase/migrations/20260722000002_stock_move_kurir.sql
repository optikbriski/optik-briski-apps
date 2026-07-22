-- =============================================================================
-- Logistics tracking (gratis): kurir per surat jalan DO/RO/Retur
-- =============================================================================

alter table public.stock_move_history
  add column if not exists kurir_karyawan_id uuid,
  add column if not exists kurir_nama text;

comment on column public.stock_move_history.kurir_karyawan_id is
  'Karyawan yang ditugaskan sebagai kurir (opsional).';
comment on column public.stock_move_history.kurir_nama is
  'Nama kurir (denormalized) untuk tampilan tracking Admin.';

create index if not exists stock_move_kurir_idx
  on public.stock_move_history (kurir_karyawan_id)
  where kurir_karyawan_id is not null;

create index if not exists stock_move_open_status_idx
  on public.stock_move_history (status, created_at desc)
  where status in ('WAITING', 'TRANSIT', 'PENDING');
