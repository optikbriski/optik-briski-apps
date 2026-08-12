-- Pengumuman singkat untuk Home APK Karyawan (+ seed checklist buka/tutup SOP)

create table if not exists public.pengumuman_cabang (
  id uuid primary key default gen_random_uuid(),
  toko_id text,
  judul text not null,
  isi text not null,
  aktif boolean not null default true,
  tampil_sampai timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);

comment on table public.pengumuman_cabang is
  'Banner singkat di Home Karyawan. toko_id null/PUSAT = semua cabang.';

create index if not exists pengumuman_cabang_aktif_idx
  on public.pengumuman_cabang (aktif, created_at desc);

alter table public.pengumuman_cabang enable row level security;

drop policy if exists pengumuman_cabang_auth_select on public.pengumuman_cabang;
create policy pengumuman_cabang_auth_select
  on public.pengumuman_cabang for select
  to authenticated
  using (aktif = true);

drop policy if exists pengumuman_cabang_auth_write on public.pengumuman_cabang;
create policy pengumuman_cabang_auth_write
  on public.pengumuman_cabang for all
  to authenticated
  using (true)
  with check (true);

-- Seed contoh (idempotent)
insert into public.pengumuman_cabang (toko_id, judul, isi, aktif)
select null, 'Briefing pagi',
  'Cek display & kebersihan area sebelum buka. Laporkan kendala ke Kepala Toko.',
  true
where not exists (
  select 1 from public.pengumuman_cabang p where p.judul = 'Briefing pagi'
);

-- Checklist buka/tutup untuk jabatan operasional toko
insert into public.sop_templates (jabatan, judul, tipe, poin, urutan)
select v.jabatan, v.judul, v.tipe, v.poin, v.urutan
from (values
  ('Frontliner', 'Buka toko: cek kebersihan & etalase', 'FOTO', 10, 1),
  ('Frontliner', 'Tutup toko: rapikan area & matikan perangkat', 'FOTO', 10, 90),
  ('Backliner', 'Buka toko: siapkan area kerja belakang', 'FOTO', 10, 1),
  ('Backliner', 'Tutup toko: amankan stok & dokumen', 'FOTO', 10, 90),
  ('Kepala Toko', 'Buka toko: briefing & cek kesiapan tim', 'FOTO', 10, 1),
  ('Kepala Toko', 'Tutup toko: rekap harian & kunci toko', 'FOTO', 10, 90)
) as v(jabatan, judul, tipe, poin, urutan)
where not exists (
  select 1 from public.sop_templates t
  where t.judul = v.judul
    and coalesce(t.jabatan, '') = coalesce(v.jabatan, '')
);
