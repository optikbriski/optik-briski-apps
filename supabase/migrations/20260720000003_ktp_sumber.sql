-- Sumber identitas: scan KTP fisik vs upload IKD
alter table public.karyawan
  add column if not exists ktp_sumber text;

comment on column public.karyawan.ktp_sumber is
  'fisik = scan kamera KTP; ikd = upload dari app IKD';
