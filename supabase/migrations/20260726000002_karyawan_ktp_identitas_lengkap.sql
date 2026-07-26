-- Identitas KTP terurai (hasil OCR / form registrasi).
alter table public.karyawan
  add column if not exists alamat_jalan_ktp text,
  add column if not exists rt_rw text,
  add column if not exists kelurahan_desa text,
  add column if not exists kecamatan_ktp text,
  add column if not exists tempat_lahir text,
  add column if not exists tanggal_lahir text,
  add column if not exists pekerjaan text,
  add column if not exists kewarganegaraan text;

comment on column public.karyawan.alamat_jalan_ktp is 'Jalan/alamat baris KTP (tanpa RT/RW).';
comment on column public.karyawan.rt_rw is 'RT/RW dari KTP.';
comment on column public.karyawan.kelurahan_desa is 'Kelurahan/Desa dari KTP.';
comment on column public.karyawan.kecamatan_ktp is 'Kecamatan dari KTP.';
comment on column public.karyawan.tempat_lahir is 'Tempat lahir dari KTP.';
comment on column public.karyawan.tanggal_lahir is 'Tanggal lahir dari KTP (teks).';
comment on column public.karyawan.pekerjaan is 'Pekerjaan dari KTP.';
comment on column public.karyawan.kewarganegaraan is 'Kewarganegaraan dari KTP.';
