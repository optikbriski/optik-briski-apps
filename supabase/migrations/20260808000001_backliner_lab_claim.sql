-- =============================================================================
-- Backliner lab claim queue: job per invoice fulfillment + notif + poin LAB
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tabel lab_jobs
-- ---------------------------------------------------------------------------
create table if not exists public.lab_jobs (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  toko_id text references public.toko_id (id),
  no_invoice text not null,
  status text not null default 'OPEN'
    check (status in ('OPEN', 'CLAIMED', 'DONE', 'CANCELLED')),
  claimed_by uuid references public.karyawan (id) on delete set null,
  claimed_at timestamptz,
  unit_qty integer not null default 1 check (unit_qty > 0),
  created_at timestamptz not null default now(),
  unique (sale_id)
);

create index if not exists lab_jobs_toko_status_idx
  on public.lab_jobs (toko_id, status, created_at desc);

create index if not exists lab_jobs_claimed_by_idx
  on public.lab_jobs (claimed_by, status);

comment on table public.lab_jobs is
  'Antrian job lab Backliner: first-claim-wins → pembuat_kacamata; poin saat READY.';

alter table public.lab_jobs enable row level security;

drop policy if exists lab_jobs_auth_all on public.lab_jobs;
create policy lab_jobs_auth_all on public.lab_jobs
  for all to authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- 2. Helper: jalur Back (selaras officeLayerOf di Flutter)
-- ---------------------------------------------------------------------------
create or replace function public.is_back_office_jabatan(p_jabatan text)
returns boolean
language sql
immutable
as $$
  select case
    when j in ('backliner', 'admin', 'owner') then true
    when j like '%kepala%' then true
    when j like '%lab%' then true
    when j like '%teknisi%' then true
    when j like '%gudang%' then true
    when j like '%back%' then true
    when j like '%warehouse%' then true
    when j like '%inventori%' or j like '%inventory%' then true
    when j like '%office%' then true
    else false
  end
  from (select lower(trim(coalesce(p_jabatan, ''))) as j) s;
$$;

-- ---------------------------------------------------------------------------
-- 3. Backliner on-duty di toko (aktif + bukan libur + shift OPEN)
-- ---------------------------------------------------------------------------
create or replace function public.list_on_duty_backliners(p_toko_id text)
returns table (karyawan_id uuid, nama text)
language sql
stable
security definer
set search_path = public
as $$
  select k.id, k.nama
  from public.karyawan k
  join public.attendance_shifts s
    on s.karyawan_id = k.id
   and s.status = 'OPEN'
  where upper(trim(coalesce(k.toko_id, ''))) = upper(trim(coalesce(p_toko_id, '')))
    and lower(trim(coalesce(k.status_approval, ''))) in ('aktif', 'active', 'approved')
    and public.is_back_office_jabatan(k.jabatan)
    and not exists (
      select 1
      from public.jadwal_kerja j
      where j.karyawan_id = k.id
        and j.tanggal = (timezone('Asia/Jakarta', now()))::date
        and j.is_libur is true
    );
$$;

revoke all on function public.list_on_duty_backliners(text) from public;
grant execute on function public.list_on_duty_backliners(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Buat lab_job + notifikasi (idempotent per sale)
-- ---------------------------------------------------------------------------
create or replace function public.ensure_lab_job_for_sale(p_sale_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_qty integer;
  v_job_id uuid;
  r record;
begin
  if p_sale_id is null then
    return null;
  end if;

  select * into v_sale from public.sales where id = p_sale_id;
  if not found then
    return null;
  end if;

  select coalesce(sum(greatest(coalesce(si.qty, 1), 1)), 0)::int
    into v_qty
  from public.sales_items si
  where si.sale_id = p_sale_id
    and (
      si.needs_fulfillment is true
      or upper(trim(coalesce(si.fulfillment_status, ''))) = 'PENDING_RO'
    );

  if v_qty <= 0 then
    return null;
  end if;

  insert into public.lab_jobs (sale_id, toko_id, no_invoice, status, unit_qty)
  values (
    p_sale_id,
    v_sale.toko_id,
    coalesce(nullif(trim(v_sale.no_invoice), ''), p_sale_id::text),
    'OPEN',
    v_qty
  )
  on conflict (sale_id) do update
    set unit_qty = excluded.unit_qty,
        no_invoice = excluded.no_invoice,
        toko_id = excluded.toko_id
  where public.lab_jobs.status = 'OPEN'
  returning id into v_job_id;

  if v_job_id is null then
    select id into v_job_id from public.lab_jobs where sale_id = p_sale_id;
    return v_job_id;
  end if;

  -- Notifikasi hanya sekali: bila belom ada notif LAB untuk job ini.
  if not exists (
    select 1 from public.notifikasi n
    where n.tipe = 'LAB'
      and n.isi like '%LAB_JOB:' || v_job_id::text || '%'
  ) then
    for r in
      select karyawan_id, nama
      from public.list_on_duty_backliners(v_sale.toko_id)
    loop
      insert into public.notifikasi (user_id, judul, isi, tipe)
      values (
        r.karyawan_id,
        'Job lab baru',
        format(
          'Invoice %s menunggu dikerjakan. Ketuk Kerjakan di Antrian lab. LAB_JOB:%s',
          coalesce(nullif(trim(v_sale.no_invoice), ''), '-'),
          v_job_id::text
        ),
        'LAB'
      );
    end loop;
  end if;

  -- Sync unit_qty bila job sudah ada
  update public.lab_jobs
     set unit_qty = v_qty
   where id = v_job_id
     and status in ('OPEN', 'CLAIMED');

  return v_job_id;
end;
$$;

revoke all on function public.ensure_lab_job_for_sale(uuid) from public;
grant execute on function public.ensure_lab_job_for_sale(uuid) to authenticated;

create or replace function public.trg_sales_items_ensure_lab_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    if NEW.needs_fulfillment is true
       or upper(trim(coalesce(NEW.fulfillment_status, ''))) = 'PENDING_RO' then
      perform public.ensure_lab_job_for_sale(NEW.sale_id);
    end if;
  elsif TG_OP = 'UPDATE' then
    if (NEW.needs_fulfillment is true
        or upper(trim(coalesce(NEW.fulfillment_status, ''))) = 'PENDING_RO')
       and (
         OLD.needs_fulfillment is distinct from NEW.needs_fulfillment
         or OLD.fulfillment_status is distinct from NEW.fulfillment_status
         or OLD.qty is distinct from NEW.qty
       ) then
      perform public.ensure_lab_job_for_sale(NEW.sale_id);
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists sales_items_ensure_lab_job on public.sales_items;
create trigger sales_items_ensure_lab_job
  after insert or update of needs_fulfillment, fulfillment_status, qty
  on public.sales_items
  for each row
  execute function public.trg_sales_items_ensure_lab_job();

-- ---------------------------------------------------------------------------
-- 5. Claim atomic (first wins) + set pembuat
-- ---------------------------------------------------------------------------
create or replace function public.claim_lab_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_k public.karyawan%rowtype;
  v_job public.lab_jobs%rowtype;
  v_updated public.lab_jobs%rowtype;
begin
  if v_uid is null then
    raise exception 'Login diperlukan';
  end if;

  select * into v_k from public.karyawan where id = v_uid;
  if not found then
    raise exception 'Profil karyawan tidak ditemukan';
  end if;

  if lower(trim(coalesce(v_k.status_approval, ''))) not in ('aktif', 'active', 'approved') then
    raise exception 'Akun karyawan tidak aktif';
  end if;

  if not public.is_back_office_jabatan(v_k.jabatan) then
    raise exception 'Hanya Backliner / back office yang bisa claim job lab';
  end if;

  if exists (
    select 1 from public.jadwal_kerja j
    where j.karyawan_id = v_uid
      and j.tanggal = (timezone('Asia/Jakarta', now()))::date
      and j.is_libur is true
  ) then
    raise exception 'Sedang libur — tidak bisa claim job lab';
  end if;

  if not exists (
    select 1 from public.attendance_shifts s
    where s.karyawan_id = v_uid and s.status = 'OPEN'
  ) then
    raise exception 'Belum absen masuk — tidak bisa claim job lab';
  end if;

  select * into v_job from public.lab_jobs where id = p_job_id for update;
  if not found then
    raise exception 'Job lab tidak ditemukan';
  end if;

  if upper(trim(coalesce(v_job.toko_id, ''))) <> upper(trim(coalesce(v_k.toko_id, ''))) then
    raise exception 'Job lab bukan untuk cabang Anda';
  end if;

  if v_job.status = 'CLAIMED' and v_job.claimed_by = v_uid then
    return jsonb_build_object(
      'ok', true,
      'job_id', v_job.id,
      'status', v_job.status,
      'claimed_by', v_job.claimed_by,
      'nama', v_k.nama,
      'already', true
    );
  end if;

  update public.lab_jobs
     set status = 'CLAIMED',
         claimed_by = v_uid,
         claimed_at = now()
   where id = p_job_id
     and status = 'OPEN'
  returning * into v_updated;

  if not found then
    raise exception 'Job sudah diambil orang lain';
  end if;

  update public.sales
     set pembuat_kacamata_id = v_uid,
         nama_pembuat_kacamata = v_k.nama
   where id = v_updated.sale_id;

  return jsonb_build_object(
    'ok', true,
    'job_id', v_updated.id,
    'sale_id', v_updated.sale_id,
    'no_invoice', v_updated.no_invoice,
    'status', v_updated.status,
    'claimed_by', v_updated.claimed_by,
    'nama', v_k.nama,
    'unit_qty', v_updated.unit_qty,
    'already', false
  );
end;
$$;

revoke all on function public.claim_lab_job(uuid) from public;
grant execute on function public.claim_lab_job(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Poin LAB saat semua line lab READY (+ sync DONE)
-- ---------------------------------------------------------------------------
create or replace function public.try_award_lab_poin(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.lab_jobs%rowtype;
  v_pembuat uuid;
  v_pending integer;
  v_poin integer;
  v_ref text;
begin
  if p_sale_id is null then
    return;
  end if;

  select * into v_job from public.lab_jobs where sale_id = p_sale_id;
  if not found then
    return;
  end if;

  if v_job.status = 'DONE' or v_job.status = 'CANCELLED' then
    return;
  end if;

  select count(*)::int into v_pending
  from public.sales_items si
  where si.sale_id = p_sale_id
    and upper(trim(coalesce(si.fulfillment_status, ''))) = 'PENDING_RO';

  if v_pending > 0 then
    return;
  end if;

  select pembuat_kacamata_id into v_pembuat
  from public.sales
  where id = p_sale_id;

  if v_pembuat is null then
    v_pembuat := v_job.claimed_by;
  end if;

  if v_pembuat is null then
    return;
  end if;

  v_poin := greatest(coalesce(v_job.unit_qty, 1), 1) * 5;
  v_ref := 'lab-' || p_sale_id::text;

  if not exists (
    select 1 from public.poin_logs
    where karyawan_id = v_pembuat and sumber = 'LAB' and ref_id = v_ref
  ) then
    begin
      insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
      values (
        v_pembuat,
        (timezone('Asia/Jakarta', now()))::date,
        v_poin,
        'LAB',
        v_ref
      );
    exception when unique_violation then
      null;
    end;
  end if;

  update public.lab_jobs
     set status = 'DONE',
         claimed_by = coalesce(claimed_by, v_pembuat),
         claimed_at = coalesce(claimed_at, now())
   where id = v_job.id
     and status in ('OPEN', 'CLAIMED');
end;
$$;

revoke all on function public.try_award_lab_poin(uuid) from public;
grant execute on function public.try_award_lab_poin(uuid) to authenticated;

create or replace function public.trg_sales_items_lab_poin_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE'
     and OLD.fulfillment_status is distinct from NEW.fulfillment_status
     and upper(trim(coalesce(NEW.fulfillment_status, ''))) in ('READY', 'DIAMBIL') then
    perform public.try_award_lab_poin(NEW.sale_id);
  end if;
  return NEW;
end;
$$;

drop trigger if exists sales_items_lab_poin_ready on public.sales_items;
create trigger sales_items_lab_poin_ready
  after update of fulfillment_status
  on public.sales_items
  for each row
  execute function public.trg_sales_items_lab_poin_ready();

-- ---------------------------------------------------------------------------
-- 7. Admin set pembuat → sync lab_jobs claim
-- ---------------------------------------------------------------------------
create or replace function public.set_invoice_pembuat(
  p_no_invoice text,
  p_karyawan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nama text;
  v_sale_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Login diperlukan';
  end if;

  select nama into v_nama
  from public.karyawan
  where id = p_karyawan_id
  limit 1;

  if v_nama is null then
    raise exception 'Karyawan tidak ditemukan';
  end if;

  update public.sales
  set
    pembuat_kacamata_id = p_karyawan_id,
    nama_pembuat_kacamata = v_nama
  where no_invoice = trim(p_no_invoice)
  returning id into v_sale_id;

  if v_sale_id is null then
    raise exception 'Invoice tidak ditemukan';
  end if;

  update public.lab_jobs
     set status = case when status = 'DONE' then 'DONE' else 'CLAIMED' end,
         claimed_by = p_karyawan_id,
         claimed_at = coalesce(claimed_at, now())
   where sale_id = v_sale_id
     and status in ('OPEN', 'CLAIMED');

  -- Jika belom ada job tapi ada line lab, buat lalu claim
  perform public.ensure_lab_job_for_sale(v_sale_id);
  update public.lab_jobs
     set status = case when status = 'DONE' then 'DONE' else 'CLAIMED' end,
         claimed_by = p_karyawan_id,
         claimed_at = coalesce(claimed_at, now())
   where sale_id = v_sale_id
     and status in ('OPEN', 'CLAIMED');

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'pembuat_kacamata_id', p_karyawan_id,
    'nama_pembuat_kacamata', v_nama
  );
end;
$$;

revoke all on function public.set_invoice_pembuat(text, uuid) from public;
grant execute on function public.set_invoice_pembuat(text, uuid) to authenticated;
