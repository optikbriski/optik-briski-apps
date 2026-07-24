-- Poin absensi hanya setelah Admin verifikasi (Valid/Curang).
-- Hapus trigger yang menulis ABSEN_TELAT otomatis saat clock-in
-- (dibuat di 00005 — jangan dipakai lagi).
-- Hapus poin telat yang sudah masuk sebelum verifikasi (pending/mencurigakan).

drop trigger if exists attendance_logs_write_late_poin on public.attendance_logs;
drop function if exists public.trg_attendance_logs_write_late_poin();

-- Bersihkan ABSEN_TELAT untuk absen yang belum Valid/Curang final.
delete from public.poin_logs p
where p.sumber = 'ABSEN_TELAT'
  and p.ref_id like 'absen-telat-%'
  and exists (
    select 1
    from public.attendance_logs l
    join public.attendance_verifications v on v.log_id = l.id
    where p.ref_id = 'absen-telat-' || l.id::text
      and v.status in ('pending_review', 'mencurigakan')
  );

-- Juga hapus ABSEN_TELAT jika verification belum ada / belum final.
delete from public.poin_logs p
where p.sumber = 'ABSEN_TELAT'
  and p.ref_id like 'absen-telat-%'
  and exists (
    select 1
    from public.attendance_logs l
    where p.ref_id = 'absen-telat-' || l.id::text
      and not exists (
        select 1
        from public.attendance_verifications v
        where v.log_id = l.id
          and v.status in ('aman', 'curang')
      )
  );

comment on column public.attendance_logs.late_penalty_points is
  'Metadata penalti telat (dihitung saat masuk). Poin_logs ABSEN_TELAT '
  'baru ditulis saat Admin menandai Valid — bukan saat clock-in.';
