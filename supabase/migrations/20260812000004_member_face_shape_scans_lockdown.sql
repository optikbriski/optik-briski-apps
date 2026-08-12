-- =============================================================================
-- Bentuk Member kini referensi panduan (tanpa scan kamera di app).
-- Kunci RLS tabel legacy member_face_shape_scans: tutup akses anon terbuka.
-- Admin pusat tetap bisa kelola / export koreksi untuk pipeline training.
-- =============================================================================

drop policy if exists member_face_shape_scans_insert on public.member_face_shape_scans;
drop policy if exists member_face_shape_scans_select on public.member_face_shape_scans;
drop policy if exists member_face_shape_scans_update on public.member_face_shape_scans;

-- Pastikan policy admin tetap ada (idempotent).
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

comment on table public.member_face_shape_scans is
  'Legacy scan bentuk wajah (pipeline training). App Member saat ini tidak menulis ke sini; akses hanya admin pusat.';
