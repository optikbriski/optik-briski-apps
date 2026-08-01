-- =============================================================================
-- Klaim member: buat tabel pengajuan (jika belum ada) + foto + jadwal kunjungan
-- Aman dijalankan ulang (IF NOT EXISTS / DROP POLICY IF EXISTS).
-- =============================================================================

create extension if not exists pgcrypto;

-- Prasyarat ringan: members (untuk FK opsional)
create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null unique,
  phone_raw text,
  nama text,
  email text,
  alamat text,
  font_scale numeric not null default 1.0,
  locale text not null default 'id',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Tabel pengajuan klaim dari Member APK
create table if not exists public.garansi_klaim_request (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.members(id) on delete set null,
  phone_e164 text not null,
  -- Tanpa FK ketat ke garansi_kartu agar migrasi tidak gagal
  -- jika tabel kartu belum ada di project ini.
  kartu_id uuid not null,
  sale_id uuid,
  toko_id text not null,
  alasan text not null,
  foto_url text,
  jadwal_kunjungan timestamptz,
  status text not null default 'diajukan'
    check (status in ('diajukan', 'diproses_toko', 'selesai', 'dibatalkan')),
  created_at timestamptz not null default now()
);

-- Kalau tabel sudah ada dari migrasi lama (tanpa jadwal)
alter table public.garansi_klaim_request
  add column if not exists foto_url text;

alter table public.garansi_klaim_request
  add column if not exists jadwal_kunjungan timestamptz;

comment on column public.garansi_klaim_request.jadwal_kunjungan is
  'Rencana hari/tanggal/jam member datang ke toko untuk klaim.';

create index if not exists garansi_klaim_request_phone_idx
  on public.garansi_klaim_request (phone_e164, created_at desc);

alter table public.garansi_klaim_request enable row level security;

drop policy if exists garansi_klaim_req_anon_all on public.garansi_klaim_request;
create policy garansi_klaim_req_anon_all on public.garansi_klaim_request
  for all to anon, authenticated using (true) with check (true);

-- Opsional: pasang FK ke garansi_kartu jika tabelnya sudah ada
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'garansi_kartu'
  ) and not exists (
    select 1 from pg_constraint
    where conname = 'garansi_klaim_request_kartu_id_fkey'
  ) then
    alter table public.garansi_klaim_request
      add constraint garansi_klaim_request_kartu_id_fkey
      foreign key (kartu_id) references public.garansi_kartu(id);
  end if;
exception when others then
  -- Abaikan jika data lama tidak cocok FK
  raise notice 'Skip FK kartu_id: %', sqlerrm;
end $$;

-- Bucket foto klaim (member app = anon)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'member-claim-photos',
  'member-claim-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists public_read_member_claim_photos on storage.objects;
create policy public_read_member_claim_photos
  on storage.objects for select
  using (bucket_id = 'member-claim-photos');

drop policy if exists anon_insert_member_claim_photos on storage.objects;
create policy anon_insert_member_claim_photos
  on storage.objects for insert
  to anon, authenticated
  with check (bucket_id = 'member-claim-photos');

drop policy if exists anon_update_member_claim_photos on storage.objects;
create policy anon_update_member_claim_photos
  on storage.objects for update
  to anon, authenticated
  using (bucket_id = 'member-claim-photos')
  with check (bucket_id = 'member-claim-photos');
