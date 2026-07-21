-- Field KTP lengkap: TTL, gol. darah, agama, status perkawinan + jejak OCR
alter table public.karyawan
  add column if not exists tempat_tgl_lahir text,
  add column if not exists tempat_tgl_lahir_ocr text,
  add column if not exists golongan_darah text,
  add column if not exists golongan_darah_ocr text,
  add column if not exists agama text,
  add column if not exists agama_ocr text,
  add column if not exists status_perkawinan text,
  add column if not exists status_perkawinan_ocr text,
  add column if not exists gender_ocr text;

comment on column public.karyawan.tempat_tgl_lahir is
  'Tempat & tanggal lahir sesuai KTP (bisa diedit karyawan).';
comment on column public.karyawan.tempat_tgl_lahir_ocr is
  'Tempat/tgl lahir hasil OCR (jejak asli).';
comment on column public.karyawan.golongan_darah is 'Golongan darah dari KTP.';
comment on column public.karyawan.golongan_darah_ocr is 'Gol. darah hasil OCR.';
comment on column public.karyawan.agama is 'Agama dari KTP.';
comment on column public.karyawan.agama_ocr is 'Agama hasil OCR.';
comment on column public.karyawan.status_perkawinan is 'Status perkawinan dari KTP.';
comment on column public.karyawan.status_perkawinan_ocr is
  'Status perkawinan hasil OCR.';
comment on column public.karyawan.gender_ocr is
  'Jenis kelamin hasil OCR (LAKI-LAKI / PEREMPUAN).';
comment on column public.karyawan.alamat_ktp is
  'Alamat KTP lengkap (jalan, RT/RW, kel/desa, kecamatan) — bisa diedit.';
