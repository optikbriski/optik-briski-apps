-- Audit penerima barang (scan QR karyawan / SMR)
alter table public.stock_move_history
  add column if not exists verified_by text,
  add column if not exists verified_by_name text,
  add column if not exists verified_at timestamptz;

comment on column public.stock_move_history.verified_by is
  'ID karyawan/user yang scan/terima barang.';
comment on column public.stock_move_history.verified_by_name is
  'Nama petugas penerima (denormalized untuk audit).';
comment on column public.stock_move_history.verified_at is
  'Waktu konfirmasi penerimaan (SUCCESS).';

create index if not exists stock_move_verified_at_idx
  on public.stock_move_history (verified_at desc nulls last);
