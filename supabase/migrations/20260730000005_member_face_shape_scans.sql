-- =============================================================================
-- Scan bentuk wajah Member — fitur rasio + prediksi + koreksi (untuk training).
-- =============================================================================

create table if not exists public.member_face_shape_scans (
  id uuid primary key default gen_random_uuid(),
  member_id uuid null,
  phone_e164 text null,
  primary_shape text not null,
  primary_pct int not null default 0,
  runner_up_shape text null,
  runner_up_pct int null,
  corrected_shape text null,
  corrected_at timestamptz null,
  features jsonb not null default '{}'::jsonb,
  ranked jsonb not null default '[]'::jsonb,
  engine text not null default 'hybrid',
  source text not null default 'member_app',
  created_at timestamptz not null default now()
);

create index if not exists member_face_shape_scans_member_idx
  on public.member_face_shape_scans (member_id, created_at desc);

create index if not exists member_face_shape_scans_phone_idx
  on public.member_face_shape_scans (phone_e164, created_at desc);

create index if not exists member_face_shape_scans_corrected_idx
  on public.member_face_shape_scans (corrected_shape)
  where corrected_shape is not null;

comment on table public.member_face_shape_scans is
  'Hasil scan bentuk wajah (landmark ratios). corrected_shape dipakai fine-tune model.';

alter table public.member_face_shape_scans enable row level security;

-- Baca/tulis anon untuk Member APK (sama pola booking ringan).
drop policy if exists member_face_shape_scans_insert on public.member_face_shape_scans;
create policy member_face_shape_scans_insert on public.member_face_shape_scans
  for insert to anon, authenticated
  with check (true);

drop policy if exists member_face_shape_scans_select on public.member_face_shape_scans;
create policy member_face_shape_scans_select on public.member_face_shape_scans
  for select to anon, authenticated
  using (true);

drop policy if exists member_face_shape_scans_update on public.member_face_shape_scans;
create policy member_face_shape_scans_update on public.member_face_shape_scans
  for update to anon, authenticated
  using (true)
  with check (true);

-- Admin pusat bisa kelola penuh.
drop policy if exists member_face_shape_scans_admin on public.member_face_shape_scans;
create policy member_face_shape_scans_admin on public.member_face_shape_scans
  for all to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  );

-- Feature flag beranda
update public.member_home_content
set feature_flags = coalesce(feature_flags, '{}'::jsonb) || '{"bentuk_wajah": true}'::jsonb
where id = 'default';
