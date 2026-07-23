-- =============================================================================
-- Verifikasi wajah absensi (Admin): bandingkan capture masuk vs foto terdaftar.
-- Status: pending_review → aman | mencurigakan → (aman | curang)
-- Poin ABSEN + SP (surat peringatan) untuk kecurangan wajah — BUKAN keterlambatan.
-- =============================================================================

-- 1) Antrian / hasil verifikasi face+liveness per shift masuk
create table if not exists public.attendance_verifications (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references public.attendance_shifts (id) on delete cascade,
  log_id uuid references public.attendance_logs (id) on delete set null,
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text not null references public.toko_id (id),
  status text not null default 'pending_review'
    check (status in ('pending_review', 'aman', 'mencurigakan', 'curang')),
  capture_photo_url text,
  enrolled_photo_url text,
  match_score double precision,
  liveness_ok boolean,
  liveness_confidence double precision,
  liveness_provider text,
  notes text,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  poin_awarded integer,
  created_at timestamptz not null default now(),
  unique (shift_id)
);

create index if not exists attendance_verifications_status_created_idx
  on public.attendance_verifications (status, created_at desc);

create index if not exists attendance_verifications_toko_created_idx
  on public.attendance_verifications (toko_id, created_at desc);

create index if not exists attendance_verifications_karyawan_created_idx
  on public.attendance_verifications (karyawan_id, created_at desc);

comment on table public.attendance_verifications is
  'Review Admin: foto capture absen masuk vs face_photo_url terdaftar. '
  'Valid/Aman = poin ABSEN hari itu. Curang = -200 poin + SP1 (bukan terlambat).';

comment on column public.attendance_verifications.status is
  'pending_review | aman | mencurigakan | curang';

-- 2) Surat peringatan minimal (SP1/SP2/SP3)
create table if not exists public.surat_peringatan (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text references public.toko_id (id),
  tingkat integer not null default 1 check (tingkat between 1 and 3),
  alasan text not null,
  sumber text not null default 'ABSEN_CURANG',
  ref_id text,
  issued_by uuid references auth.users (id) on delete set null,
  issued_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists surat_peringatan_karyawan_issued_idx
  on public.surat_peringatan (karyawan_id, issued_at desc);

create unique index if not exists surat_peringatan_unique_ref
  on public.surat_peringatan (karyawan_id, sumber, ref_id)
  where ref_id is not null;

comment on table public.surat_peringatan is
  'Surat peringatan karyawan. SP dari absensi curang (bukan keterlambatan).';

-- 3) RLS
alter table public.attendance_verifications enable row level security;
alter table public.surat_peringatan enable row level security;

revoke all on table public.attendance_verifications from anon, authenticated;
grant select, insert, update on table public.attendance_verifications to authenticated;
grant all on table public.attendance_verifications to service_role;

revoke all on table public.surat_peringatan from anon, authenticated;
grant select, insert on table public.surat_peringatan to authenticated;
grant all on table public.surat_peringatan to service_role;

-- Karyawan: baca verifikasi / SP sendiri
drop policy if exists attendance_verifications_karyawan_select
  on public.attendance_verifications;
create policy attendance_verifications_karyawan_select
  on public.attendance_verifications
  for select to authenticated
  using (
    karyawan_id = auth.uid()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id
        and k.email is not null
        and k.email = (auth.jwt() ->> 'email')
    )
  );

drop policy if exists surat_peringatan_karyawan_select
  on public.surat_peringatan;
create policy surat_peringatan_karyawan_select
  on public.surat_peringatan
  for select to authenticated
  using (
    karyawan_id = auth.uid()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id
        and k.email is not null
        and k.email = (auth.jwt() ->> 'email')
    )
  );

-- Admin: baca / tulis sesuai toko (Pusat = semua)
drop policy if exists attendance_verifications_admin_select
  on public.attendance_verifications;
create policy attendance_verifications_admin_select
  on public.attendance_verifications
  for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat', 'admin_toko', 'super_admin')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = attendance_verifications.toko_id
        )
    )
  );

drop policy if exists attendance_verifications_admin_insert
  on public.attendance_verifications;
create policy attendance_verifications_admin_insert
  on public.attendance_verifications
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat', 'admin_toko', 'super_admin')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = attendance_verifications.toko_id
        )
    )
    or karyawan_id = auth.uid()
  );

drop policy if exists attendance_verifications_admin_update
  on public.attendance_verifications;
create policy attendance_verifications_admin_update
  on public.attendance_verifications
  for update to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat', 'admin_toko', 'super_admin')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = attendance_verifications.toko_id
        )
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat', 'admin_toko', 'super_admin')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = attendance_verifications.toko_id
        )
    )
  );

drop policy if exists surat_peringatan_admin_select
  on public.surat_peringatan;
create policy surat_peringatan_admin_select
  on public.surat_peringatan
  for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat', 'admin_toko', 'super_admin')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = coalesce(surat_peringatan.toko_id, '')
        )
    )
  );

drop policy if exists surat_peringatan_admin_insert
  on public.surat_peringatan;
create policy surat_peringatan_admin_insert
  on public.surat_peringatan
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat', 'admin_toko', 'super_admin')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = coalesce(surat_peringatan.toko_id, '')
        )
    )
  );

-- Izinkan insert verifikasi dari clock-in (authenticated yang membuat shift)
-- Policy insert di atas sudah cover admin; tambah policy untuk pelaku absen:
drop policy if exists attendance_verifications_actor_insert
  on public.attendance_verifications;
create policy attendance_verifications_actor_insert
  on public.attendance_verifications
  for insert to authenticated
  with check (
    karyawan_id = auth.uid()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id
        and k.email is not null
        and k.email = (auth.jwt() ->> 'email')
    )
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          coalesce(p.role, '') in ('owner', 'admin_pusat', 'admin_toko', 'super_admin')
          or coalesce(p.toko_id, '') in ('PUSAT', 'CABANG-PUSAT')
          or coalesce(p.toko_id, '') = attendance_verifications.toko_id
        )
    )
  );
