-- Samakan poin absensi Admin → poin_logs (yang dibaca APK Karyawan).
-- Jalankan ulang di SQL Editor setelah menandai Valid / Curang.
--
-- Aturan:
--   Valid + ontime → +20 sumber ABSEN (ref absen-valid-{verification_id})
--   Valid + telat  → hanya ABSEN_TELAT (ref absen-telat-{log_id}), tanpa +20
--   Curang         → −200 sumber ABSEN (ref absen-curang-{verification_id})

-- 1a) Valid ontime: isi poin_awarded = 20 jika kosong
update public.attendance_verifications v
set poin_awarded = 20
from public.attendance_logs l
where v.log_id = l.id
  and v.status = 'aman'
  and (v.poin_awarded is null or v.poin_awarded = 0)
  and (
    l.late_penalty_points is null
    or l.late_penalty_points >= 0
  );

-- Valid ontime tanpa log (fallback lama)
update public.attendance_verifications v
set poin_awarded = 20
where v.status = 'aman'
  and (v.poin_awarded is null or v.poin_awarded = 0)
  and (
    v.log_id is null
    or not exists (
      select 1
      from public.attendance_logs l
      where l.id = v.log_id
        and l.late_penalty_points is not null
        and l.late_penalty_points < 0
    )
  );

-- 1b) Valid telat: poin_awarded = penalti (bukan +20)
update public.attendance_verifications v
set poin_awarded = l.late_penalty_points
from public.attendance_logs l
where v.log_id = l.id
  and v.status = 'aman'
  and l.late_penalty_points is not null
  and l.late_penalty_points < 0
  and (
    v.poin_awarded is null
    or v.poin_awarded = 0
    or v.poin_awarded = 20
  );

-- 1c) Curang: −200
update public.attendance_verifications
set poin_awarded = -200
where status = 'curang'
  and (poin_awarded is null or poin_awarded = 0);

-- 1d) Hapus +20 ABSEN yang salah untuk Valid telat
delete from public.poin_logs p
using public.attendance_verifications v
join public.attendance_logs l on l.id = v.log_id
where p.karyawan_id = v.karyawan_id
  and p.sumber = 'ABSEN'
  and p.ref_id = 'absen-valid-' || v.id::text
  and v.status = 'aman'
  and l.late_penalty_points is not null
  and l.late_penalty_points < 0;

-- 2a) Backfill ABSEN ontime (+20) + curang (−200)
insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
select
  v.karyawan_id,
  coalesce(
    (v.reviewed_at at time zone 'Asia/Jakarta')::date,
    (v.created_at at time zone 'Asia/Jakarta')::date
  ) as tanggal,
  v.poin_awarded,
  'ABSEN',
  case
    when v.status = 'curang' then 'absen-curang-' || v.id::text
    else 'absen-valid-' || v.id::text
  end as ref_id
from public.attendance_verifications v
left join public.attendance_logs l on l.id = v.log_id
where v.status in ('aman', 'curang')
  and v.poin_awarded is not null
  and v.poin_awarded <> 0
  and (
    v.status = 'curang'
    or l.id is null
    or l.late_penalty_points is null
    or l.late_penalty_points >= 0
  )
  and not exists (
    select 1
    from public.poin_logs p
    where p.karyawan_id = v.karyawan_id
      and p.sumber = 'ABSEN'
      and p.ref_id = case
        when v.status = 'curang' then 'absen-curang-' || v.id::text
        else 'absen-valid-' || v.id::text
      end
  );

-- 2b) Backfill ABSEN_TELAT untuk Valid yang telat
insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
select
  v.karyawan_id,
  coalesce(
    (v.reviewed_at at time zone 'Asia/Jakarta')::date,
    (v.created_at at time zone 'Asia/Jakarta')::date
  ) as tanggal,
  l.late_penalty_points,
  'ABSEN_TELAT',
  'absen-telat-' || l.id::text as ref_id
from public.attendance_verifications v
join public.attendance_logs l on l.id = v.log_id
where v.status = 'aman'
  and l.late_penalty_points is not null
  and l.late_penalty_points < 0
  and not exists (
    select 1
    from public.poin_logs p
    where p.karyawan_id = v.karyawan_id
      and p.sumber = 'ABSEN_TELAT'
      and p.ref_id = 'absen-telat-' || l.id::text
  );

-- 3) Cek hasil
select
  v.id,
  k.nama,
  v.status,
  v.poin_awarded,
  l.late_penalty_points,
  v.reviewed_at,
  exists (
    select 1
    from public.poin_logs p
    where p.karyawan_id = v.karyawan_id
      and p.sumber = 'ABSEN'
      and p.ref_id = case
        when v.status = 'curang' then 'absen-curang-' || v.id::text
        else 'absen-valid-' || v.id::text
      end
  ) as ada_absen,
  exists (
    select 1
    from public.poin_logs p
    where p.karyawan_id = v.karyawan_id
      and p.sumber = 'ABSEN_TELAT'
      and p.ref_id = 'absen-telat-' || l.id::text
  ) as ada_telat
from public.attendance_verifications v
left join public.karyawan k on k.id = v.karyawan_id
left join public.attendance_logs l on l.id = v.log_id
where v.status in ('aman', 'curang')
order by v.reviewed_at desc nulls last
limit 30;

select
  k.nama,
  p.tanggal,
  p.poin,
  p.sumber,
  p.ref_id
from public.poin_logs p
join public.karyawan k on k.id = p.karyawan_id
where p.sumber in ('ABSEN', 'ABSEN_TELAT')
order by p.created_at desc
limit 30;
