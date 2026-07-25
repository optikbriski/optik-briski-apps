-- Foto bukti saat scan QR jalan (QUEUED/PREPARING → TRANSIT)
alter table public.stock_move_history
  add column if not exists bukti_foto_kurir text;

comment on column public.stock_move_history.bukti_foto_kurir is
  'Foto barang oleh kurir/driver saat scan QR perjalanan → TRANSIT.';
