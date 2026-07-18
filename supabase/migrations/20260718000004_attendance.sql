-- Absensi: geofence toko + face template + log shift
-- Jalankan di SQL Editor

alter table public.toko_id
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists radius_meters integer not null default 100;

alter table public.karyawan
  add column if not exists face_photo_url text,
  add column if not exists face_template jsonb,
  add column if not exists face_enrolled_at timestamptz;

create table if not exists public.attendance_shifts (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id),
  toko_id text not null references public.toko_id (id),
  masuk_at timestamptz not null default now(),
  pulang_at timestamptz,
  status text not null default 'OPEN',
  created_at timestamptz not null default now()
);

create index if not exists attendance_shifts_karyawan_status_idx
  on public.attendance_shifts (karyawan_id, status);

create table if not exists public.attendance_logs (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid references public.attendance_shifts (id) on delete set null,
  karyawan_id uuid not null references public.karyawan (id),
  toko_id text not null references public.toko_id (id),
  tipe text not null, -- MASUK | PULANG | ENROLL
  photo_url text,
  latitude double precision,
  longitude double precision,
  distance_meters double precision,
  match_score double precision,
  liveness_ok boolean not null default false,
  device_info text,
  created_at timestamptz not null default now()
);

create index if not exists attendance_logs_karyawan_created_idx
  on public.attendance_logs (karyawan_id, created_at desc);

alter table public.attendance_shifts enable row level security;
alter table public.attendance_logs enable row level security;

drop policy if exists attendance_shifts_auth_all on public.attendance_shifts;
create policy attendance_shifts_auth_all on public.attendance_shifts
  for all to authenticated using (true) with check (true);

drop policy if exists attendance_logs_auth_all on public.attendance_logs;
create policy attendance_logs_auth_all on public.attendance_logs
  for all to authenticated using (true) with check (true);

-- Koordinat toko: isi manual di Table Editor → toko_id
-- (latitude, longitude, radius_meters). Tidak di-hardcode di sini.
