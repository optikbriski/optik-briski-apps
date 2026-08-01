-- Seed baris versi Member (update in-app). Upload APK ke bucket app-releases
-- dengan nama: optik-member-X.Y.Z.apk agar auto-sync jalan.

insert into public.versi_app (
  versi_terbaru,
  url_download,
  force_update,
  catatan_rilis,
  app_flavor
)
select
  '1.0.0',
  '',
  false,
  'Placeholder Member — ganti URL setelah upload APK ke Storage app-releases.',
  'member'
where not exists (
  select 1 from public.versi_app where app_flavor = 'member'
);
