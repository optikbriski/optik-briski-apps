-- =============================================================================
-- Update APK in-app: bucket Storage + tabel versi_app siap pakai
-- Jalankan di Supabase → SQL Editor (project Optik B Riski Apps)
-- =============================================================================

-- 1) Pastikan kolom versi_app lengkap
create table if not exists public.versi_app (
  id uuid primary key default gen_random_uuid(),
  versi_terbaru text,
  url_download text,
  created_at timestamptz not null default now()
);

alter table public.versi_app
  add column if not exists force_update boolean not null default false,
  add column if not exists catatan_rilis text,
  add column if not exists app_flavor text not null default 'karyawan';

alter table public.versi_app enable row level security;

drop policy if exists versi_app_anon_select on public.versi_app;
create policy versi_app_anon_select on public.versi_app
  for select to anon using (true);

drop policy if exists versi_app_authenticated_select on public.versi_app;
create policy versi_app_authenticated_select on public.versi_app
  for select to authenticated using (true);

-- Admin (authenticated) boleh insert/update baris versi (publish update)
drop policy if exists versi_app_authenticated_write on public.versi_app;
create policy versi_app_authenticated_write on public.versi_app
  for all to authenticated
  using (true)
  with check (true);

-- 2) Bucket public untuk file APK
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'app-releases',
  'app-releases',
  true,
  157286400, -- 150 MB
  array[
    'application/vnd.android.package-archive',
    'application/octet-stream',
    'application/zip'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 3) Policy Storage: siapa saja boleh DOWNLOAD (public read)
drop policy if exists "app_releases_public_read" on storage.objects;
create policy "app_releases_public_read"
  on storage.objects for select
  using (bucket_id = 'app-releases');

-- Upload/update/hapus: user yang login (admin)
drop policy if exists "app_releases_auth_insert" on storage.objects;
create policy "app_releases_auth_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'app-releases');

drop policy if exists "app_releases_auth_update" on storage.objects;
create policy "app_releases_auth_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'app-releases');

drop policy if exists "app_releases_auth_delete" on storage.objects;
create policy "app_releases_auth_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'app-releases');

-- 4) Seed / update baris versi Karyawan 1.2.6
--    Ganti URL jika project beda. Upload APK dulu ke bucket app-releases.
insert into public.versi_app (
  versi_terbaru,
  url_download,
  force_update,
  catatan_rilis,
  app_flavor
)
select
  '1.2.6',
  'https://ualqiiprtjysdmtqkpzr.supabase.co/storage/v1/object/public/app-releases/optik-karyawan-1.2.6.apk',
  false,
  'Scan KTP fisik (grid + auto jepret), upload IKD, detail verifikasi, field KTP lengkap.',
  'karyawan'
where not exists (
  select 1 from public.versi_app
  where app_flavor = 'karyawan' and versi_terbaru = '1.2.6'
);

-- Jika baris 1.2.6 sudah ada, pastikan URL-nya benar:
update public.versi_app
set
  url_download = 'https://ualqiiprtjysdmtqkpzr.supabase.co/storage/v1/object/public/app-releases/optik-karyawan-1.2.6.apk',
  catatan_rilis = 'Scan KTP fisik (grid + auto jepret), upload IKD, detail verifikasi, field KTP lengkap.',
  force_update = false
where app_flavor = 'karyawan'
  and versi_terbaru = '1.2.6';
