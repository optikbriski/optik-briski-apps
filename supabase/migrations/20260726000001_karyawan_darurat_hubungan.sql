-- Hubungan kontak darurat (dari registrasi karyawan).
alter table public.karyawan
  add column if not exists darurat_hubungan text;

comment on column public.karyawan.darurat_hubungan is
  'Hubungan kontak darurat: Orang Tua / Saudara / Sahabat / dll.';
