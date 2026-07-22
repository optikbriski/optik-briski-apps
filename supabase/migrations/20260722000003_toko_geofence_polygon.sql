-- =============================================================================
-- Geofence area (4 sudut) + audit keluar area saat jam kerja
-- =============================================================================

alter table public.toko_id
  add column if not exists geofence_mode text not null default 'circle',
  add column if not exists geofence_polygon jsonb;

comment on column public.toko_id.geofence_mode is
  'circle | polygon — polygon = tepat 4 sudut di geofence_polygon';
comment on column public.toko_id.geofence_polygon is
  'Array JSON [{lat,lng}, ...] tepat 4 titik (sudut 1→2→3→4).';

alter table public.toko_id
  drop constraint if exists toko_geofence_mode_chk;
alter table public.toko_id
  add constraint toko_geofence_mode_chk
  check (geofence_mode in ('circle', 'polygon'));

create table if not exists public.geofence_exit_logs (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id),
  toko_id text not null references public.toko_id (id),
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now()
);

create index if not exists geofence_exit_logs_toko_at_idx
  on public.geofence_exit_logs (toko_id, created_at desc);
create index if not exists geofence_exit_logs_karyawan_at_idx
  on public.geofence_exit_logs (karyawan_id, created_at desc);

alter table public.geofence_exit_logs enable row level security;

drop policy if exists geofence_exit_logs_authenticated_all on public.geofence_exit_logs;
create policy geofence_exit_logs_authenticated_all
  on public.geofence_exit_logs
  for all to authenticated
  using (true)
  with check (true);
