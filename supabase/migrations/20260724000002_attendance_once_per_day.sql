-- Batasi absensi: 1× MASUK + 1× PULANG per karyawan per tanggal Asia/Jakarta.
-- ENROLL tidak dibatasi.

-- 1) Hapus duplikat (simpan yang paling awal per hari)
delete from public.attendance_logs a
using public.attendance_logs b
where a.tipe in ('MASUK', 'PULANG')
  and b.tipe = a.tipe
  and a.karyawan_id = b.karyawan_id
  and (a.created_at at time zone 'Asia/Jakarta')::date
    = (b.created_at at time zone 'Asia/Jakarta')::date
  and (
    a.created_at > b.created_at
    or (a.created_at = b.created_at and a.id > b.id)
  );

-- 2) Unique: satu tipe absen (MASUK/PULANG) per karyawan per hari Jakarta
create unique index if not exists attendance_logs_one_per_day_tipe_idx
  on public.attendance_logs (
    karyawan_id,
    ((created_at at time zone 'Asia/Jakarta')::date),
    tipe
  )
  where tipe in ('MASUK', 'PULANG');

comment on index public.attendance_logs_one_per_day_tipe_idx is
  'Maksimal 1 MASUK dan 1 PULANG per karyawan per tanggal Asia/Jakarta.';
