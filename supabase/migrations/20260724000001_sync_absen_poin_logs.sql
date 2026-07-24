-- Samakan poin absensi Admin → poin_logs (yang dibaca APK Karyawan).
-- Jalankan ulang di SQL Editor setelah menandai Valid / Curang.

-- 1) Isti poin_awarded jika status sudah final tapi kolom kosong
update public.attendance_verifications
set poin_awarded = 20
where status = 'aman'
  and (poin_awarded is null or poin_awarded = 0);

update public.attendance_verifications
set poin_awarded = -200
where status = 'curang'
  and (poin_awarded is null or poin_awarded = 0);

-- 2) Backfill poin_logs yang belum ada
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
where v.status in ('aman', 'curang')
  and v.poin_awarded is not null
  and v.poin_awarded <> 0
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

-- 3) Cek hasil (lihat di Results)
select
  v.id,
  k.nama,
  v.status,
  v.poin_awarded,
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
  ) as ada_di_poin_logs
from public.attendance_verifications v
left join public.karyawan k on k.id = v.karyawan_id
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
where p.sumber = 'ABSEN'
order by p.created_at desc
limit 30;
