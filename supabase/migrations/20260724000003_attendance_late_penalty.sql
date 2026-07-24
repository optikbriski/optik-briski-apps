-- Metadata keterlambatan absen masuk.
-- Poin_logs ABSEN_TELAT ditulis app saat Admin Valid (bukan saat clock-in).
--
-- Aturan penalti (app):
--   Shift pagi (jam_masuk 08:30):
--     08:30:01–09:00:00 → −1 / menit
--     09:00:01+         → −20 tiap 15 menit dari 09:00
--   Shift siang (jam_masuk 13:00):
--     13:00:01+         → −20 tiap 15 menit dari 13:00

alter table public.attendance_logs
  add column if not exists late_seconds integer,
  add column if not exists late_penalty_points integer;

comment on column public.attendance_logs.late_seconds is
  'Detik terlambat vs jam_masuk jadwal (Asia/Jakarta). Null = tidak dihitung.';
comment on column public.attendance_logs.late_penalty_points is
  'Metadata penalti telat (negatif). Poin_logs ABSEN_TELAT baru saat Admin Valid.';
