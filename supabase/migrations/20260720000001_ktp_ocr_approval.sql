-- KTP OCR trail + admin approval choices
alter table public.karyawan
  add column if not exists ktp_photo_url text,
  add column if not exists nik_ocr text,
  add column if not exists nama_ocr text,
  add column if not exists alamat_ktp_ocr text,
  add column if not exists alamat_ktp text,
  add column if not exists approval_choices jsonb,
  add column if not exists approved_by uuid,
  add column if not exists approved_by_name text,
  add column if not exists approved_at timestamptz;

comment on column public.karyawan.nik_ocr is 'NIK hasil OCR KTP (jejak asli, tidak diubah karyawan).';
comment on column public.karyawan.nama_ocr is 'Nama hasil OCR KTP.';
comment on column public.karyawan.alamat_ktp_ocr is 'Alamat hasil OCR KTP.';
comment on column public.karyawan.alamat_ktp is 'Alamat KTP versi form (bisa diedit karyawan).';
comment on column public.karyawan.alamat_lengkap is 'Alamat domisili sekarang (boleh beda dari KTP).';
comment on column public.karyawan.approval_choices is
  'Pilihan admin saat approve: {nik,nama,alamat_ktp: ocr|edit, alamat: ocr|edit|both}';
comment on column public.karyawan.approved_by_name is 'Nama admin Pusat yang menyetujui.';

-- Bucket foto KTP
insert into storage.buckets (id, name, public)
values ('ktp_photos', 'ktp_photos', true)
on conflict (id) do nothing;

drop policy if exists "ktp_photos_public_read" on storage.objects;
create policy "ktp_photos_public_read"
  on storage.objects for select
  using (bucket_id = 'ktp_photos');

drop policy if exists "ktp_photos_auth_upload" on storage.objects;
create policy "ktp_photos_auth_upload"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'ktp_photos');

drop policy if exists "ktp_photos_auth_update" on storage.objects;
create policy "ktp_photos_auth_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'ktp_photos');
