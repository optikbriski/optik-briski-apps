-- Metadata keterlambatan absen masuk (+ penalti poin di poin_logs sumber ABSEN_TELAT).
-- Aturan app: tiap kelipatan 15 menit terlambat = −20 poin
-- (1d–15m → −20; 15m1s–30m → −40; dst).

alter table public.attendance_logs
  add column if not exists late_seconds integer,
  add column if not exists late_penalty_points integer;

comment on column public.attendance_logs.late_seconds is
  'Detik terlambat vs jam_masuk jadwal (Asia/Jakarta). Null = tidak dihitung.';
comment on column public.attendance_logs.late_penalty_points is
  'Poin penalti telat (negatif). 0 / null = tidak kena.';
