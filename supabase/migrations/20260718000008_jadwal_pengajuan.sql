-- Pengajuan jadwal: ijin / cuti / tukar shift antar karyawan

create table if not exists public.jadwal_pengajuan (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text references public.toko_id (id),
  -- IJIN | CUTI | TUKAR
  tipe text not null check (tipe in ('IJIN', 'CUTI', 'TUKAR')),
  tanggal date not null,
  -- Untuk TUKAR: hari milik partner yang ditukar
  tanggal_tukar date,
  partner_karyawan_id uuid references public.karyawan (id) on delete set null,
  alasan text not null,
  -- PENDING | APPROVED | REJECTED | CANCELLED
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
  reviewer_id uuid references auth.users (id) on delete set null,
  reviewer_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists jadwal_pengajuan_status_idx
  on public.jadwal_pengajuan (status, created_at desc);

create index if not exists jadwal_pengajuan_toko_idx
  on public.jadwal_pengajuan (toko_id, status);

create index if not exists jadwal_pengajuan_karyawan_idx
  on public.jadwal_pengajuan (karyawan_id, created_at desc);

alter table public.jadwal_pengajuan enable row level security;

drop policy if exists jadwal_pengajuan_auth_all on public.jadwal_pengajuan;
create policy jadwal_pengajuan_auth_all on public.jadwal_pengajuan
  for all to authenticated using (true) with check (true);

comment on table public.jadwal_pengajuan is
  'Pengajuan ijin/cuti/tukar jadwal. Approve admin → update jadwal_kerja.';
