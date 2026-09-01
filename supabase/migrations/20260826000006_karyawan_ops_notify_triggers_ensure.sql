-- Ensure notify triggers + list_karyawan_ids_for_toko (same_store) for FCM dispatch.
-- Safe to re-run if 00005 already applied live.

create or replace function public.list_karyawan_ids_for_toko(p_toko text)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(k.id), '{}'::uuid[])
  from public.karyawan k
  where public.same_store_toko(k.toko_id, p_toko)
    and lower(coalesce(k.status_approval, '')) in ('aktif', 'active', 'approved');
$$;

revoke all on function public.list_karyawan_ids_for_toko(text) from public;
grant execute on function public.list_karyawan_ids_for_toko(text)
  to authenticated, service_role;

-- Re-assert function + triggers (idempotent)
create or replace function public.trg_notify_toko_antrian()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text;
  v_judul text;
  v_isi text;
  v_tipe text := 'INFO';
begin
  if tg_table_name = 'online_orders' then
    v_toko := coalesce(new.toko_id, '');
    if tg_op = 'INSERT' then
      v_judul := 'Order online baru';
      v_isi := left(
        coalesce(nullif(trim(new.customer_name), ''), new.id::text)
          || ' · ' || coalesce(new.status, ''),
        160
      );
    elsif tg_op = 'UPDATE'
         and coalesce(old.status, '') is distinct from coalesce(new.status, '')
         and lower(coalesce(new.status, '')) in ('packing', 'ready') then
      v_judul := 'Pickup online';
      v_isi := left(
        coalesce(nullif(trim(new.customer_name), ''), new.id::text)
          || ' · ' || new.status,
        160
      );
    else
      return new;
    end if;
  elsif tg_table_name = 'member_bookings' then
    v_toko := coalesce(new.toko_id, '');
    if tg_op = 'INSERT' then
      v_judul := 'Booking baru';
      v_isi := left(
        coalesce(new.jenis, 'booking') || ' · ' || coalesce(new.phone_e164, new.id::text),
        160
      );
    elsif tg_op = 'UPDATE'
         and coalesce(old.status, '') is distinct from coalesce(new.status, '')
         and lower(coalesce(new.status, '')) in ('booked', 'checked_in') then
      v_judul := 'Booking update';
      v_isi := left(
        coalesce(new.jenis, 'booking') || ' · ' || coalesce(new.status, ''),
        160
      );
    else
      return new;
    end if;
  elsif tg_table_name = 'lab_jobs' then
    v_toko := coalesce(new.toko_id, '');
    if tg_op = 'INSERT'
       and upper(coalesce(new.status, '')) = 'OPEN' then
      v_judul := 'Job lab baru';
      v_isi := left(
        coalesce(new.no_invoice, '') || ' LAB_JOB:' || new.id::text,
        160
      );
      v_tipe := 'LAB';
    else
      return new;
    end if;
  elsif tg_table_name = 'garansi_klaim_request' then
    v_toko := coalesce(new.toko_id, '');
    if tg_op = 'INSERT' then
      v_judul := 'Klaim garansi baru';
      v_isi := left(
        coalesce(new.no_invoice, new.id::text)
          || ' · ' || coalesce(new.status, 'baru'),
        160
      );
      v_tipe := 'ANTRIAN';
    elsif tg_op = 'UPDATE'
         and coalesce(old.status, '') is distinct from coalesce(new.status, '') then
      v_judul := 'Klaim garansi update';
      v_isi := left(
        coalesce(new.no_invoice, new.id::text)
          || ' · ' || coalesce(new.status, ''),
        160
      );
      v_tipe := 'ANTRIAN';
    else
      return new;
    end if;
  else
    return new;
  end if;

  if nullif(trim(v_toko), '') is null then
    return new;
  end if;

  begin
    perform public.notify_toko_karyawan(v_toko, v_judul, v_isi, v_tipe);
  exception when others then
    null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_online_orders on public.online_orders;
create trigger trg_notify_online_orders
  after insert or update of status on public.online_orders
  for each row execute function public.trg_notify_toko_antrian();

drop trigger if exists trg_notify_member_bookings on public.member_bookings;
create trigger trg_notify_member_bookings
  after insert or update of status on public.member_bookings
  for each row execute function public.trg_notify_toko_antrian();

drop trigger if exists trg_notify_lab_jobs on public.lab_jobs;
create trigger trg_notify_lab_jobs
  after insert on public.lab_jobs
  for each row execute function public.trg_notify_toko_antrian();

drop trigger if exists trg_notify_garansi_klaim_request on public.garansi_klaim_request;
create trigger trg_notify_garansi_klaim_request
  after insert or update of status on public.garansi_klaim_request
  for each row execute function public.trg_notify_toko_antrian();
