-- Pastikan poin telat selalu tercatat (trigger) dan tidak double (unique ref).
-- Valid/Curang tetap via app dengan ref_id unik absen-valid-* / absen-curang-*.

create or replace function public.trg_attendance_logs_write_late_poin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tanggal date;
  v_ref text;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;
  if new.tipe is distinct from 'MASUK' then
    return new;
  end if;
  if new.late_penalty_points is null or new.late_penalty_points >= 0 then
    return new;
  end if;
  if new.karyawan_id is null then
    return new;
  end if;

  v_tanggal := (timezone('Asia/Jakarta', coalesce(new.created_at, now())))::date;
  v_ref := 'absen-telat-' || new.id::text;

  insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
  values (
    new.karyawan_id,
    v_tanggal,
    new.late_penalty_points,
    'ABSEN_TELAT',
    v_ref
  )
  on conflict (karyawan_id, sumber, ref_id) where (ref_id is not null)
  do nothing;

  return new;
end;
$$;

drop trigger if exists attendance_logs_write_late_poin on public.attendance_logs;
create trigger attendance_logs_write_late_poin
  after insert on public.attendance_logs
  for each row
  execute function public.trg_attendance_logs_write_late_poin();

comment on function public.trg_attendance_logs_write_late_poin is
  'Auto-insert poin_logs ABSEN_TELAT saat MASUK punya late_penalty_points. '
  'ON CONFLICT DO NOTHING → tidak double.';

-- Backfill telat yang belum masuk poin_logs
insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
select
  l.karyawan_id,
  (timezone('Asia/Jakarta', l.created_at))::date,
  l.late_penalty_points,
  'ABSEN_TELAT',
  'absen-telat-' || l.id::text
from public.attendance_logs l
where l.tipe = 'MASUK'
  and l.late_penalty_points is not null
  and l.late_penalty_points < 0
  and not exists (
    select 1
    from public.poin_logs p
    where p.karyawan_id = l.karyawan_id
      and p.sumber = 'ABSEN_TELAT'
      and p.ref_id = 'absen-telat-' || l.id::text
  );
