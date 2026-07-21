-- Update APK in-app: force update + catatan + flavor
alter table public.versi_app
  add column if not exists force_update boolean not null default false,
  add column if not exists catatan_rilis text,
  add column if not exists app_flavor text not null default 'karyawan';

comment on column public.versi_app.force_update is
  'Jika true, app karyawan wajib update sebelum lanjut.';
comment on column public.versi_app.catatan_rilis is
  'Changelog singkat yang ditampilkan di dialog update.';
comment on column public.versi_app.app_flavor is
  'karyawan | admin | member — filter update per app.';

-- Contoh baris (ganti url setelah upload APK ke Storage):
-- insert into public.versi_app (versi_terbaru, url_download, force_update, catatan_rilis, app_flavor)
-- values ('1.2.2', 'https://XXXX.supabase.co/storage/v1/object/public/app-releases/optik-karyawan-1.2.2.apk', false, 'Scan terima barang + bugfix', 'karyawan');
