-- Fitur karyawan nyata: jadwal, poin, SOP, pengaduan, notifikasi

-- 1. Jadwal kerja (roster mingguan)
create table if not exists public.jadwal_kerja (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text references public.toko_id (id),
  tanggal date not null,
  jam_masuk time,
  jam_pulang time,
  is_libur boolean not null default false,
  catatan text,
  created_at timestamptz not null default now(),
  unique (karyawan_id, tanggal)
);

create index if not exists jadwal_kerja_karyawan_tanggal_idx
  on public.jadwal_kerja (karyawan_id, tanggal);

-- 2. Poin logs
create table if not exists public.poin_logs (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  tanggal date not null default (timezone('Asia/Jakarta', now()))::date,
  poin integer not null default 0,
  sumber text not null, -- SOP | ABSEN | BONUS
  ref_id text,
  created_at timestamptz not null default now()
);

create unique index if not exists poin_logs_unique_ref
  on public.poin_logs (karyawan_id, sumber, ref_id)
  where ref_id is not null;

create index if not exists poin_logs_karyawan_tanggal_idx
  on public.poin_logs (karyawan_id, tanggal);

-- 3. SOP templates + completions
create table if not exists public.sop_templates (
  id uuid primary key default gen_random_uuid(),
  jabatan text, -- null = semua jabatan
  judul text not null,
  tipe text not null default 'CHECK', -- FOTO | SCAN | INPUT | CHECK
  poin integer not null default 10,
  urutan integer not null default 0,
  aktif boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.sop_completions (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  template_id uuid not null references public.sop_templates (id) on delete cascade,
  tanggal date not null default (timezone('Asia/Jakarta', now()))::date,
  bukti_text text,
  bukti_url text,
  poin_claimed integer not null default 0,
  created_at timestamptz not null default now(),
  unique (karyawan_id, template_id, tanggal)
);

create index if not exists sop_completions_karyawan_tanggal_idx
  on public.sop_completions (karyawan_id, tanggal);

-- 4. Pengaduan
create table if not exists public.pengaduan (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text references public.toko_id (id),
  kategori text not null,
  isi text not null,
  foto_url text,
  status text not null default 'OPEN', -- OPEN | DONE
  created_at timestamptz not null default now()
);

create index if not exists pengaduan_karyawan_created_idx
  on public.pengaduan (karyawan_id, created_at desc);

-- 5. Notifikasi in-app
create table if not exists public.notifikasi (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  judul text not null,
  isi text,
  tipe text not null default 'INFO', -- SOP | SHIFT | ADMIN | INFO
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifikasi_user_created_idx
  on public.notifikasi (user_id, created_at desc);

-- RLS
alter table public.jadwal_kerja enable row level security;
alter table public.poin_logs enable row level security;
alter table public.sop_templates enable row level security;
alter table public.sop_completions enable row level security;
alter table public.pengaduan enable row level security;
alter table public.notifikasi enable row level security;

drop policy if exists jadwal_kerja_auth_all on public.jadwal_kerja;
create policy jadwal_kerja_auth_all on public.jadwal_kerja
  for all to authenticated using (true) with check (true);

drop policy if exists poin_logs_auth_all on public.poin_logs;
create policy poin_logs_auth_all on public.poin_logs
  for all to authenticated using (true) with check (true);

drop policy if exists sop_templates_auth_all on public.sop_templates;
create policy sop_templates_auth_all on public.sop_templates
  for all to authenticated using (true) with check (true);

drop policy if exists sop_completions_auth_all on public.sop_completions;
create policy sop_completions_auth_all on public.sop_completions
  for all to authenticated using (true) with check (true);

drop policy if exists pengaduan_auth_all on public.pengaduan;
create policy pengaduan_auth_all on public.pengaduan
  for all to authenticated using (true) with check (true);

drop policy if exists notifikasi_auth_own on public.notifikasi;
create policy notifikasi_auth_own on public.notifikasi
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Storage bucket pengaduan
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('pengaduan_photos', 'pengaduan_photos', true, 3145728, array['image/jpeg','image/png'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if exists (select 1 from storage.buckets where id = 'pengaduan_photos') then
    drop policy if exists public_read_pengaduan_photos on storage.objects;
    create policy public_read_pengaduan_photos on storage.objects
      for select using (bucket_id = 'pengaduan_photos');

    drop policy if exists auth_insert_pengaduan_photos on storage.objects;
    create policy auth_insert_pengaduan_photos on storage.objects
      for insert to authenticated with check (bucket_id = 'pengaduan_photos');

    drop policy if exists auth_update_pengaduan_photos on storage.objects;
    create policy auth_update_pengaduan_photos on storage.objects
      for update to authenticated
      using (bucket_id = 'pengaduan_photos')
      with check (bucket_id = 'pengaduan_photos');

    drop policy if exists auth_delete_pengaduan_photos on storage.objects;
    create policy auth_delete_pengaduan_photos on storage.objects
      for delete to authenticated using (bucket_id = 'pengaduan_photos');
  end if;
end $$;

-- Seed SOP templates (idempotent by judul+jabatan)
insert into public.sop_templates (jabatan, judul, tipe, poin, urutan)
select v.jabatan, v.judul, v.tipe, v.poin, v.urutan
from (values
  ('Kasir', 'Cek kebersihan area kasir', 'FOTO', 10, 1),
  ('Kasir', 'Hitung modal kas awal', 'INPUT', 10, 2),
  ('Kasir', 'Foto display etalase depan', 'FOTO', 10, 3),
  ('Kasir', 'Scan penerimaan barang (jika ada)', 'SCAN', 5, 4),
  ('RO', 'Siapkan alat RO & kalibrasi', 'FOTO', 10, 1),
  ('RO', 'Dokumentasi ruang periksa', 'FOTO', 10, 2),
  ('RO', 'Cek stok lensa trial', 'FOTO', 10, 3),
  ('RO', 'Scan penerimaan lensa', 'SCAN', 5, 4),
  ('Optometrist (RO)', 'Siapkan alat RO & kalibrasi', 'FOTO', 10, 1),
  ('Optometrist (RO)', 'Dokumentasi ruang periksa', 'FOTO', 10, 2),
  ('Kepala Toko', 'Briefing tim pagi', 'FOTO', 10, 1),
  ('Kepala Toko', 'Cek stok kritis', 'FOTO', 10, 2),
  ('Kepala Toko', 'Scan penerimaan gudang', 'SCAN', 5, 3),
  ('Kepala Toko', 'Catat target harian', 'INPUT', 10, 4),
  (null, 'Rapikan area kerja', 'FOTO', 10, 1),
  (null, 'Foto kondisi toko pagi', 'FOTO', 10, 2)
) as v(jabatan, judul, tipe, poin, urutan)
where not exists (
  select 1 from public.sop_templates t
  where t.judul = v.judul
    and coalesce(t.jabatan, '') = coalesce(v.jabatan, '')
);
