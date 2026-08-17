-- =============================================================================
-- Owner residuals close: approve/reject, payroll periods, saldo ledger, alerts.
-- Idempotent. Project: ualqiiprtjysdmtqkpzr
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Payroll period + lines (Admin runs/locks; Owner monitors)
-- -----------------------------------------------------------------------------
create table if not exists public.payroll_period (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id) on delete cascade,
  periode_ym text not null
    check (periode_ym ~ '^\d{4}-\d{2}$'),
  status text not null default 'draft'
    check (status in ('draft', 'dikunci', 'dibayar')),
  total_gaji_pokok bigint not null default 0,
  total_tunjangan bigint not null default 0,
  total_potongan bigint not null default 0,
  total_nett bigint not null default 0,
  line_count int not null default 0,
  notes text,
  computed_at timestamptz,
  locked_at timestamptz,
  paid_at timestamptz,
  computed_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (toko_id, periode_ym)
);

create index if not exists payroll_period_ym_idx
  on public.payroll_period (periode_ym desc);

create table if not exists public.payroll_lines (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.payroll_period (id) on delete cascade,
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  nama text not null,
  jabatan text,
  gaji_pokok bigint not null default 0,
  tunjangan bigint not null default 0,
  potongan bigint not null default 0,
  nett bigint not null default 0,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (period_id, karyawan_id)
);

create index if not exists payroll_lines_period_idx
  on public.payroll_lines (period_id);

alter table public.payroll_period enable row level security;
alter table public.payroll_lines enable row level security;

drop policy if exists payroll_period_select on public.payroll_period;
create policy payroll_period_select on public.payroll_period
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.owner_can_access_toko(toko_id)
  );

drop policy if exists payroll_period_admin_write on public.payroll_period;
create policy payroll_period_admin_write on public.payroll_period
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists payroll_lines_select on public.payroll_lines;
create policy payroll_lines_select on public.payroll_lines
  for select to authenticated
  using (
    exists (
      select 1 from public.payroll_period p
      where p.id = period_id
        and (
          public.is_admin_pusat_or_owner()
          or public.owner_can_access_toko(p.toko_id)
        )
    )
  );

drop policy if exists payroll_lines_admin_write on public.payroll_lines;
create policy payroll_lines_admin_write on public.payroll_lines
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

-- -----------------------------------------------------------------------------
-- 2. Saldo ledger (real movements; balances on owner_saldo_pusat_toko)
-- -----------------------------------------------------------------------------
create table if not exists public.owner_saldo_ledger (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id) on delete cascade,
  -- pusat_ke_toko = pusat utang/saldo ke toko (+)
  -- toko_ke_pusat = toko utang/saldo ke pusat (+)
  direction text not null
    check (direction in ('pusat_ke_toko', 'toko_ke_pusat')),
  amount bigint not null check (amount > 0),
  note text,
  ref_type text,
  ref_id text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create index if not exists owner_saldo_ledger_toko_idx
  on public.owner_saldo_ledger (toko_id, created_at desc);

alter table public.owner_saldo_ledger enable row level security;

drop policy if exists owner_saldo_ledger_select on public.owner_saldo_ledger;
create policy owner_saldo_ledger_select on public.owner_saldo_ledger
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.owner_can_access_toko(toko_id)
  );

drop policy if exists owner_saldo_ledger_admin_write on public.owner_saldo_ledger;
create policy owner_saldo_ledger_admin_write on public.owner_saldo_ledger
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

create or replace function public.owner_saldo_apply_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.owner_saldo_pusat_toko as s (
    toko_id, saldo_pusat_ke_toko, saldo_toko_ke_pusat, updated_at
  ) values (
    new.toko_id,
    case when new.direction = 'pusat_ke_toko' then new.amount else 0 end,
    case when new.direction = 'toko_ke_pusat' then new.amount else 0 end,
    now()
  )
  on conflict (toko_id) do update set
    saldo_pusat_ke_toko = s.saldo_pusat_ke_toko
      + case when new.direction = 'pusat_ke_toko' then new.amount else 0 end,
    saldo_toko_ke_pusat = s.saldo_toko_ke_pusat
      + case when new.direction = 'toko_ke_pusat' then new.amount else 0 end,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_owner_saldo_ledger_balance on public.owner_saldo_ledger;
create trigger trg_owner_saldo_ledger_balance
  after insert on public.owner_saldo_ledger
  for each row execute function public.owner_saldo_apply_balance();

comment on table public.owner_saldo_ledger is
  'Mutasi saldo/utang pusat↔toko. Balance cache di owner_saldo_pusat_toko.';
comment on table public.owner_saldo_pusat_toko is
  'Balance cache pusat↔toko (diupdate dari owner_saldo_ledger).';

-- -----------------------------------------------------------------------------
-- 3. Admin/Owner provisioner: post saldo + create alert + run payroll
-- -----------------------------------------------------------------------------
create or replace function public.admin_post_saldo_movement(
  p_toko_id text,
  p_direction text,
  p_amount bigint,
  p_note text default null,
  p_ref_type text default null,
  p_ref_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dir text := lower(trim(p_direction));
  v_row public.owner_saldo_ledger%rowtype;
  v_bal public.owner_saldo_pusat_toko%rowtype;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Hanya admin pusat / Owner Utama';
  end if;
  if v_dir not in ('pusat_ke_toko', 'toko_ke_pusat') then
    raise exception 'direction harus pusat_ke_toko|toko_ke_pusat';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'amount harus > 0';
  end if;
  if not exists (select 1 from public.toko_id t where t.id = p_toko_id) then
    raise exception 'Toko tidak ditemukan';
  end if;

  insert into public.owner_saldo_ledger (
    toko_id, direction, amount, note, ref_type, ref_id, created_by
  ) values (
    p_toko_id, v_dir, p_amount, nullif(trim(coalesce(p_note, '')), ''),
    p_ref_type, p_ref_id, auth.uid()
  )
  returning * into v_row;

  select * into v_bal from public.owner_saldo_pusat_toko where toko_id = p_toko_id;

  perform public.owner_write_audit(
    'post_saldo_movement',
    'owner_saldo_ledger',
    v_row.id::text,
    jsonb_build_object(
      'toko_id', p_toko_id,
      'direction', v_dir,
      'amount', p_amount
    )
  );

  return jsonb_build_object(
    'ok', true,
    'ledger', to_jsonb(v_row),
    'balance', to_jsonb(v_bal)
  );
end;
$$;

revoke all on function public.admin_post_saldo_movement(text, text, bigint, text, text, text) from public;
grant execute on function public.admin_post_saldo_movement(text, text, bigint, text, text, text) to authenticated;

create or replace function public.admin_create_owner_alert(
  p_title text,
  p_body text default null,
  p_toko_id text default null,
  p_severity text default 'info',
  p_category text default 'umum',
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sev text := lower(coalesce(nullif(trim(p_severity), ''), 'info'));
  v_row public.owner_alerts%rowtype;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Hanya admin pusat / Owner Utama';
  end if;
  if v_sev not in ('info', 'warning', 'critical') then
    v_sev := 'info';
  end if;
  if nullif(trim(p_title), '') is null then
    raise exception 'title wajib';
  end if;
  if p_toko_id is not null and not exists (
    select 1 from public.toko_id t where t.id = p_toko_id
  ) then
    raise exception 'Toko tidak ditemukan';
  end if;

  insert into public.owner_alerts (
    toko_id, severity, category, title, body, meta
  ) values (
    nullif(trim(coalesce(p_toko_id, '')), ''),
    v_sev,
    coalesce(nullif(trim(p_category), ''), 'umum'),
    trim(p_title),
    nullif(trim(coalesce(p_body, '')), ''),
    coalesce(p_meta, '{}'::jsonb)
  )
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

revoke all on function public.admin_create_owner_alert(text, text, text, text, text, jsonb) from public;
grant execute on function public.admin_create_owner_alert(text, text, text, text, text, jsonb) to authenticated;

create or replace function public.admin_run_payroll_period(
  p_toko_id text,
  p_periode_ym text,
  p_lock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ym text := trim(p_periode_ym);
  v_existing public.payroll_period%rowtype;
  v_period_id uuid;
  v_status text;
  v_total_pokok bigint := 0;
  v_total_nett bigint := 0;
  v_count int := 0;
  v_out jsonb;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Hanya admin pusat / Owner Utama yang boleh run payroll';
  end if;
  if v_ym !~ '^\d{4}-\d{2}$' then
    raise exception 'periode_ym harus YYYY-MM';
  end if;
  if not exists (select 1 from public.toko_id t where t.id = p_toko_id) then
    raise exception 'Toko tidak ditemukan';
  end if;

  select * into v_existing
  from public.payroll_period
  where toko_id = p_toko_id and periode_ym = v_ym;

  if v_existing.id is not null and v_existing.status in ('dikunci', 'dibayar') then
    select to_jsonb(p.*) || jsonb_build_object(
      'readonly', true,
      'lines', coalesce((
        select jsonb_agg(to_jsonb(l) order by l.nama)
        from public.payroll_lines l where l.period_id = v_existing.id
      ), '[]'::jsonb)
    )
    into v_out
    from public.payroll_period p where p.id = v_existing.id;
    return v_out;
  end if;

  v_status := case when p_lock then 'dikunci' else 'draft' end;

  insert into public.payroll_period as b (
    toko_id, periode_ym, status,
    total_gaji_pokok, total_tunjangan, total_potongan, total_nett, line_count,
    computed_at, locked_at, computed_by, updated_at
  ) values (
    p_toko_id, v_ym, v_status,
    0, 0, 0, 0, 0,
    now(),
    case when p_lock then now() else null end,
    auth.uid(),
    now()
  )
  on conflict (toko_id, periode_ym) do update set
    status = excluded.status,
    computed_at = excluded.computed_at,
    locked_at = coalesce(b.locked_at, excluded.locked_at),
    computed_by = excluded.computed_by,
    updated_at = now()
  returning b.id into v_period_id;

  delete from public.payroll_lines where period_id = v_period_id;

  insert into public.payroll_lines (
    period_id, karyawan_id, nama, jabatan, gaji_pokok, tunjangan, potongan, nett
  )
  select
    v_period_id,
    k.id,
    coalesce(k.nama, '-'),
    k.jabatan,
    coalesce(k.gaji_pokok, 0),
    0,
    0,
    coalesce(k.gaji_pokok, 0)
  from public.karyawan k
  where k.toko_id = p_toko_id
    and k.status_approval = 'Aktif';

  select
    coalesce(sum(l.gaji_pokok), 0),
    coalesce(sum(l.nett), 0),
    count(*)::int
  into v_total_pokok, v_total_nett, v_count
  from public.payroll_lines l
  where l.period_id = v_period_id;

  update public.payroll_period
  set
    total_gaji_pokok = v_total_pokok,
    total_tunjangan = 0,
    total_potongan = 0,
    total_nett = v_total_nett,
    line_count = v_count,
    updated_at = now()
  where id = v_period_id;

  perform public.owner_write_audit(
    'run_payroll_period',
    'payroll_period',
    v_period_id::text,
    jsonb_build_object('toko_id', p_toko_id, 'periode_ym', v_ym, 'lock', p_lock)
  );

  select to_jsonb(p.*) || jsonb_build_object(
    'lines', coalesce((
      select jsonb_agg(to_jsonb(l) order by l.nama)
      from public.payroll_lines l where l.period_id = p.id
    ), '[]'::jsonb)
  )
  into v_out
  from public.payroll_period p
  where p.id = v_period_id;

  return v_out;
end;
$$;

revoke all on function public.admin_run_payroll_period(text, text, boolean) from public;
grant execute on function public.admin_run_payroll_period(text, text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Owner approve / reject (karyawan + jadwal) — scoped by ownership
-- -----------------------------------------------------------------------------
create or replace function public.owner_decide_karyawan(
  p_karyawan_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_k public.karyawan%rowtype;
  v_status text;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not (public.is_owner_role() or public.is_admin_pusat_or_owner()) then
    raise exception 'Hanya Owner / Admin';
  end if;

  select * into v_k from public.karyawan where id = p_karyawan_id;
  if v_k.id is null then
    raise exception 'Karyawan tidak ditemukan';
  end if;

  if public.is_owner_role() and not public.owner_can_access_toko(v_k.toko_id) then
    raise exception 'Toko di luar scope Owner';
  end if;

  if lower(trim(coalesce(v_k.status_approval, ''))) not in (
    'pending', 'menunggu otp', 'menunggu persetujuan'
  ) then
    raise exception 'Status bukan antrean pending: %', v_k.status_approval;
  end if;

  select coalesce(o.nama, p.email, auth.uid()::text)
  into v_name
  from public.profiles p
  left join public.owners o on o.id = p.id
  where p.id = auth.uid();

  if p_approve then
    v_status := 'Aktif';
    update public.karyawan set
      status_approval = 'Aktif',
      approved_by = auth.uid(),
      approved_by_name = v_name,
      approved_at = now()
    where id = p_karyawan_id;
  else
    v_status := 'Ditolak';
    update public.karyawan set
      status_approval = 'Ditolak',
      approved_by = auth.uid(),
      approved_by_name = v_name,
      approved_at = now()
    where id = p_karyawan_id;
  end if;

  perform public.owner_write_audit(
    case when p_approve then 'approve_karyawan' else 'reject_karyawan' end,
    'karyawan',
    p_karyawan_id::text,
    jsonb_build_object(
      'toko_id', v_k.toko_id,
      'note', p_note,
      'status', v_status
    )
  );

  -- Notify Owner/Admin via alert on scoped toko
  insert into public.owner_alerts (toko_id, severity, category, title, body, meta)
  values (
    v_k.toko_id,
    'info',
    'persetujuan',
    case when p_approve
      then 'Karyawan disetujui: ' || coalesce(v_k.nama, '-')
      else 'Karyawan ditolak: ' || coalesce(v_k.nama, '-')
    end,
    coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Keputusan Owner/Admin'),
    jsonb_build_object('karyawan_id', p_karyawan_id, 'approve', p_approve)
  );

  return jsonb_build_object(
    'ok', true,
    'karyawan_id', p_karyawan_id,
    'status_approval', v_status,
    'toko_id', v_k.toko_id
  );
end;
$$;

revoke all on function public.owner_decide_karyawan(uuid, boolean, text) from public;
grant execute on function public.owner_decide_karyawan(uuid, boolean, text) to authenticated;

create or replace function public.owner_decide_jadwal(
  p_pengajuan_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jadwal_pengajuan%rowtype;
  v_tipe text;
  v_a date;
  v_b date;
  v_jadwal_a public.jadwal_kerja%rowtype;
  v_jadwal_b public.jadwal_kerja%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not (public.is_owner_role() or public.is_admin_pusat_or_owner()) then
    raise exception 'Hanya Owner / Admin';
  end if;

  select * into v_j
  from public.jadwal_pengajuan
  where id = p_pengajuan_id
    and status = 'PENDING';
  if v_j.id is null then
    raise exception 'Pengajuan tidak ditemukan / sudah diproses';
  end if;

  if public.is_owner_role() and not public.owner_can_access_toko(v_j.toko_id) then
    raise exception 'Toko di luar scope Owner';
  end if;

  if not p_approve then
    update public.jadwal_pengajuan set
      status = 'REJECTED',
      reviewer_id = auth.uid(),
      reviewer_note = p_note,
      reviewed_at = now()
    where id = p_pengajuan_id;

    perform public.owner_write_audit(
      'reject_jadwal', 'jadwal_pengajuan', p_pengajuan_id::text,
      jsonb_build_object('toko_id', v_j.toko_id, 'note', p_note)
    );

    return jsonb_build_object(
      'ok', true, 'id', p_pengajuan_id, 'status', 'REJECTED'
    );
  end if;

  v_tipe := upper(trim(coalesce(v_j.tipe, '')));
  v_a := v_j.tanggal;
  v_b := coalesce(v_j.tanggal_tukar, v_j.tanggal);

  if v_tipe in ('IJIN', 'CUTI') then
    insert into public.jadwal_kerja as jk (
      karyawan_id, toko_id, tanggal, jam_masuk, jam_pulang, is_libur, catatan
    ) values (
      v_j.karyawan_id, v_j.toko_id, v_a, null, null, true,
      v_tipe || ' disetujui: ' || coalesce(v_j.alasan, '')
    )
    on conflict (karyawan_id, tanggal) do update set
      toko_id = excluded.toko_id,
      jam_masuk = null,
      jam_pulang = null,
      is_libur = true,
      catatan = excluded.catatan;
  elsif v_tipe = 'TUKAR' then
    if v_j.partner_karyawan_id is null then
      raise exception 'Partner tukar tidak ada';
    end if;
    select * into v_jadwal_a
    from public.jadwal_kerja
    where karyawan_id = v_j.karyawan_id and tanggal = v_a;
    select * into v_jadwal_b
    from public.jadwal_kerja
    where karyawan_id = v_j.partner_karyawan_id and tanggal = v_b;

    insert into public.jadwal_kerja as jk (
      karyawan_id, toko_id, tanggal, jam_masuk, jam_pulang, is_libur, catatan
    ) values (
      v_j.karyawan_id, v_j.toko_id, v_a,
      v_jadwal_b.jam_masuk, v_jadwal_b.jam_pulang,
      coalesce(v_jadwal_b.is_libur, false),
      'Hasil tukar jadwal dengan partner'
    )
    on conflict (karyawan_id, tanggal) do update set
      toko_id = excluded.toko_id,
      jam_masuk = excluded.jam_masuk,
      jam_pulang = excluded.jam_pulang,
      is_libur = excluded.is_libur,
      catatan = excluded.catatan;

    insert into public.jadwal_kerja as jk (
      karyawan_id, toko_id, tanggal, jam_masuk, jam_pulang, is_libur, catatan
    ) values (
      v_j.partner_karyawan_id, v_j.toko_id, v_b,
      v_jadwal_a.jam_masuk, v_jadwal_a.jam_pulang,
      coalesce(v_jadwal_a.is_libur, false),
      'Hasil tukar jadwal dengan partner'
    )
    on conflict (karyawan_id, tanggal) do update set
      toko_id = excluded.toko_id,
      jam_masuk = excluded.jam_masuk,
      jam_pulang = excluded.jam_pulang,
      is_libur = excluded.is_libur,
      catatan = excluded.catatan;
  else
    raise exception 'Tipe pengajuan tidak dikenal: %', v_tipe;
  end if;

  update public.jadwal_pengajuan set
    status = 'APPROVED',
    reviewer_id = auth.uid(),
    reviewer_note = p_note,
    reviewed_at = now()
  where id = p_pengajuan_id;

  perform public.owner_write_audit(
    'approve_jadwal', 'jadwal_pengajuan', p_pengajuan_id::text,
    jsonb_build_object('toko_id', v_j.toko_id, 'tipe', v_tipe, 'note', p_note)
  );

  return jsonb_build_object(
    'ok', true, 'id', p_pengajuan_id, 'status', 'APPROVED', 'tipe', v_tipe
  );
end;
$$;

revoke all on function public.owner_decide_jadwal(uuid, boolean, text) from public;
grant execute on function public.owner_decide_jadwal(uuid, boolean, text) to authenticated;

-- Enrich list persetujuan with finance pending (same scoped toko)
create or replace function public.owner_list_persetujuan()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text[];
  v_karyawan jsonb;
  v_jadwal jsonb;
  v_finance jsonb;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;

  select coalesce(array_agg(t), '{}') into v_toko
  from public.owner_accessible_toko_ids() t;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into v_karyawan
  from (
    select k.id, k.nama, k.jabatan, k.toko_id, k.status_approval, k.created_at
    from public.karyawan k
    where k.toko_id = any (v_toko)
      and k.status_approval in ('Pending', 'Menunggu OTP', 'Menunggu Persetujuan')
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into v_jadwal
  from (
    select
      j.id,
      j.karyawan_id,
      j.toko_id,
      j.tipe,
      j.tanggal,
      j.tanggal_tukar,
      j.alasan,
      j.status,
      j.created_at,
      k.nama as karyawan_nama
    from public.jadwal_pengajuan j
    left join public.karyawan k on k.id = j.karyawan_id
    where j.toko_id = any (v_toko)
      and upper(coalesce(j.status, '')) = 'PENDING'
    limit 100
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.tanggal_transaksi desc), '[]'::jsonb)
  into v_finance
  from (
    select
      ft.id,
      ft.toko_id,
      ft.jenis_transaksi,
      ft.kategori,
      ft.nominal,
      ft.status_konfirmasi,
      ft.tanggal_transaksi,
      ft.deskripsi
    from public.finance_transactions ft
    where ft.toko_id = any (v_toko)
      and upper(coalesce(ft.status_konfirmasi, '')) = 'PENDING'
    limit 100
  ) x;

  return jsonb_build_object(
    'karyawan_pending', coalesce(v_karyawan, '[]'::jsonb),
    'jadwal_pending', coalesce(v_jadwal, '[]'::jsonb),
    'finance_pending', coalesce(v_finance, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.owner_list_persetujuan() from public;
grant execute on function public.owner_list_persetujuan() to authenticated;

-- Finance approve/reject (Owner scoped) — same statuses Admin COA uses
create or replace function public.owner_decide_finance(
  p_tx_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ft public.finance_transactions%rowtype;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not (public.is_owner_role() or public.is_admin_pusat_or_owner()) then
    raise exception 'Hanya Owner / Admin';
  end if;

  select * into v_ft from public.finance_transactions where id = p_tx_id;
  if v_ft.id is null then
    raise exception 'Transaksi tidak ditemukan';
  end if;
  if public.is_owner_role() and not public.owner_can_access_toko(v_ft.toko_id) then
    raise exception 'Toko di luar scope Owner';
  end if;
  if upper(coalesce(v_ft.status_konfirmasi, '')) <> 'PENDING' then
    raise exception 'Status bukan PENDING';
  end if;

  v_status := case when p_approve then 'APPROVED' else 'REJECTED' end;
  update public.finance_transactions
  set status_konfirmasi = v_status
  where id = p_tx_id;

  perform public.owner_write_audit(
    case when p_approve then 'approve_finance' else 'reject_finance' end,
    'finance_transactions',
    p_tx_id::text,
    jsonb_build_object('toko_id', v_ft.toko_id, 'note', p_note, 'status', v_status)
  );

  return jsonb_build_object(
    'ok', true, 'id', p_tx_id, 'status_konfirmasi', v_status
  );
end;
$$;

revoke all on function public.owner_decide_finance(uuid, boolean, text) from public;
grant execute on function public.owner_decide_finance(uuid, boolean, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Owner payroll monitor → real period (fallback estimate if none)
-- -----------------------------------------------------------------------------
create or replace function public.owner_payroll_monitor(p_toko_id text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text[];
  v_ym text := to_char(now(), 'YYYY-MM');
  v_periods jsonb;
  v_lines jsonb;
  v_total bigint := 0;
  v_period_id uuid;
  v_status text;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;

  if p_toko_id is not null and length(trim(p_toko_id)) > 0 then
    if not public.owner_can_access_toko(p_toko_id) then
      raise exception 'Toko di luar scope Owner';
    end if;
    v_toko := array[p_toko_id];
  else
    select coalesce(array_agg(t), '{}') into v_toko
    from public.owner_accessible_toko_ids() t;
  end if;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.periode_ym desc, p.toko_id), '[]'::jsonb)
  into v_periods
  from public.payroll_period p
  where p.toko_id = any (v_toko);

  -- Prefer current month period for primary toko (or first)
  select p.id, p.status, p.total_nett
  into v_period_id, v_status, v_total
  from public.payroll_period p
  where p.toko_id = any (v_toko)
    and p.periode_ym = v_ym
  order by p.updated_at desc
  limit 1;

  if v_period_id is not null then
    select coalesce(jsonb_agg(to_jsonb(l) order by l.nama), '[]'::jsonb)
    into v_lines
    from public.payroll_lines l
    where l.period_id = v_period_id;

    return jsonb_build_object(
      'periode_ym', v_ym,
      'period_id', v_period_id,
      'status', v_status,
      'lines', coalesce(v_lines, '[]'::jsonb),
      'total_gaji_pokok', v_total,
      'total_nett', v_total,
      'periods', coalesce(v_periods, '[]'::jsonb),
      'note', 'Payroll period real (Admin run/lock). Owner monitor saja.'
    );
  end if;

  -- Fallback estimate if Admin belum run period
  select coalesce(jsonb_agg(to_jsonb(x) order by x.toko_id, x.nama), '[]'::jsonb),
         coalesce(sum(x.gaji_pokok), 0)
  into v_lines, v_total
  from (
    select
      k.id as karyawan_id,
      k.nama,
      k.jabatan,
      k.toko_id,
      coalesce(k.gaji_pokok, 0) as gaji_pokok,
      coalesce(k.gaji_pokok, 0) as nett
    from public.karyawan k
    where k.toko_id = any (v_toko)
      and k.status_approval = 'Aktif'
  ) x;

  return jsonb_build_object(
    'periode_ym', v_ym,
    'period_id', null,
    'status', 'belum_dijalankan',
    'lines', coalesce(v_lines, '[]'::jsonb),
    'total_gaji_pokok', v_total,
    'total_nett', v_total,
    'periods', coalesce(v_periods, '[]'::jsonb),
    'note', 'Belum ada payroll_period bulan ini — menampilkan estimasi gaji_pokok. Minta Admin run period.'
  );
end;
$$;

revoke all on function public.owner_payroll_monitor(text) from public;
grant execute on function public.owner_payroll_monitor(text) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Owner saldo ledger list + cabang already joins balances
-- -----------------------------------------------------------------------------
create or replace function public.owner_list_saldo_ledger(
  p_toko_id text default null,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text[];
  v_rows jsonb;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;

  if p_toko_id is not null and length(trim(p_toko_id)) > 0 then
    if not public.owner_can_access_toko(p_toko_id) then
      raise exception 'Toko di luar scope';
    end if;
    v_toko := array[p_toko_id];
  else
    select coalesce(array_agg(t), '{}') into v_toko
    from public.owner_accessible_toko_ids() t;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into v_rows
  from (
    select l.*
    from public.owner_saldo_ledger l
    where l.toko_id = any (v_toko)
    order by l.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) x;

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

revoke all on function public.owner_list_saldo_ledger(text, int) from public;
grant execute on function public.owner_list_saldo_ledger(text, int) to authenticated;

-- Owner Utama may also post saldo for owned scope (utama sees all)
create or replace function public.owner_post_saldo_movement(
  p_toko_id text,
  p_direction text,
  p_amount bigint,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner public.owners%rowtype;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;
  select * into v_owner from public.owner_current();
  if v_owner.id is null then
    raise exception 'Owner tidak aktif';
  end if;
  -- Owner Toko: read-only on saldo write; Owner Utama / Admin provisioner write
  if v_owner.owner_type <> 'utama' and not public.is_owner_provisioner() then
    raise exception 'Hanya Owner Utama / Admin yang boleh post mutasi saldo';
  end if;
  if not public.owner_can_access_toko(p_toko_id) then
    raise exception 'Toko di luar scope';
  end if;
  return public.admin_post_saldo_movement(
    p_toko_id, p_direction, p_amount, p_note, 'owner_ui', null
  );
end;
$$;

revoke all on function public.owner_post_saldo_movement(text, text, bigint, text) from public;
grant execute on function public.owner_post_saldo_movement(text, text, bigint, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Admin update Owner kontrak fields
-- -----------------------------------------------------------------------------
create or replace function public.admin_update_owner_kontrak(
  p_owner_id uuid,
  p_kontrak_status text default null,
  p_kontrak_mulai date default null,
  p_kontrak_selesai date default null,
  p_catatan text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.owners%rowtype;
  v_status text;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Unauthorized';
  end if;

  select * into v_row from public.owners where id = p_owner_id;
  if v_row.id is null then
    raise exception 'Owner tidak ditemukan';
  end if;

  v_status := coalesce(nullif(trim(p_kontrak_status), ''), v_row.kontrak_status);
  if v_status not in ('draft', 'aktif', 'habis', 'terminated') then
    raise exception 'kontrak_status tidak valid';
  end if;

  update public.owners set
    kontrak_status = v_status,
    kontrak_mulai = coalesce(p_kontrak_mulai, kontrak_mulai),
    kontrak_selesai = coalesce(p_kontrak_selesai, kontrak_selesai),
    catatan = coalesce(p_catatan, catatan),
    phone = coalesce(p_phone, phone),
    updated_at = now()
  where id = p_owner_id
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

revoke all on function public.admin_update_owner_kontrak(uuid, text, date, date, text, text) from public;
grant execute on function public.admin_update_owner_kontrak(uuid, text, date, date, text, text) to authenticated;

-- Ensure compute_bagi_hasil return is jsonb (re-assert fix from 00002)
create or replace function public.owner_compute_bagi_hasil(
  p_toko_id text,
  p_periode_ym text,
  p_lock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ym text := trim(p_periode_ym);
  v_start date;
  v_end date;
  v_omzet bigint := 0;
  v_hpp bigint := 0;
  v_opex bigint := 0;
  v_gaji bigint := 0;
  v_laba bigint := 0;
  v_pct_u numeric(5,2) := 50.00;
  v_pct_t numeric(5,2) := 50.00;
  v_bagi_u bigint;
  v_bagi_t bigint;
  v_period_id uuid;
  v_status text;
  v_existing public.bagi_hasil_period%rowtype;
  v_out jsonb;
  v_payroll_gaji bigint;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;

  if not (public.is_admin_pusat_or_owner() or public.owner_can_access_toko(p_toko_id)) then
    raise exception 'Tidak berhak menghitung bagi hasil toko ini';
  end if;

  if v_ym !~ '^\d{4}-\d{2}$' then
    raise exception 'periode_ym harus YYYY-MM';
  end if;

  v_start := (v_ym || '-01')::date;
  v_end := (v_start + interval '1 month')::date;

  select coalesce(m.pct_owner_utama, 50.00), coalesce(m.pct_owner_toko, 50.00)
  into v_pct_u, v_pct_t
  from public.owner_toko_map m
  join public.owners o on o.id = m.owner_id
  where m.toko_id = p_toko_id
    and o.owner_type = 'toko'
    and o.status = 'aktif'
  order by m.created_at
  limit 1;

  if v_pct_u is null then
    v_pct_u := 50.00;
    v_pct_t := 50.00;
  end if;

  select
    coalesce(sum(s.total_harga), 0),
    coalesce(sum(
      (select coalesce(sum(si.qty * coalesce(p.harga_modal, 0)), 0)
       from public.sales_items si
       left join public.products p on p.id = si.product_id
       where si.sale_id = s.id)
    ), 0)
  into v_omzet, v_hpp
  from public.sales s
  where s.toko_id = p_toko_id
    and s.created_at >= v_start
    and s.created_at < v_end
    and coalesce(s.nama_pelanggan, '') not ilike '%Modal Awal%';

  select coalesce(sum(ft.nominal), 0) into v_opex
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
    and upper(coalesce(ft.status_konfirmasi, '')) in ('APPROVED', 'OK', 'CONFIRMED', 'DISETUJUI');

  -- Prefer locked/paid payroll nett for the period; else sum gaji_pokok aktif
  select pp.total_nett into v_payroll_gaji
  from public.payroll_period pp
  where pp.toko_id = p_toko_id
    and pp.periode_ym = v_ym
    and pp.status in ('draft', 'dikunci', 'dibayar')
  order by case pp.status when 'dibayar' then 1 when 'dikunci' then 2 else 3 end
  limit 1;

  if v_payroll_gaji is not null then
    v_gaji := v_payroll_gaji;
  else
    select coalesce(sum(k.gaji_pokok), 0) into v_gaji
    from public.karyawan k
    where k.toko_id = p_toko_id
      and k.status_approval = 'Aktif';
  end if;

  v_laba := v_omzet - v_hpp - v_opex - v_gaji;
  v_bagi_u := round(v_laba * (v_pct_u / 100.0));
  v_bagi_t := v_laba - v_bagi_u;

  select * into v_existing
  from public.bagi_hasil_period
  where toko_id = p_toko_id and periode_ym = v_ym;

  if v_existing.id is not null and v_existing.status in ('dikunci', 'dibayar') then
    return to_jsonb(v_existing) || jsonb_build_object('readonly', true);
  end if;

  v_status := case when p_lock then 'dikunci' else 'draft' end;

  insert into public.bagi_hasil_period as b (
    toko_id, periode_ym, status,
    omzet, hpp, gaji, opex, potongan_lain, laba_bersih,
    pct_owner_utama, pct_owner_toko,
    bagi_owner_utama, bagi_owner_toko,
    computed_at, locked_at, computed_by, updated_at
  ) values (
    p_toko_id, v_ym, v_status,
    v_omzet, v_hpp, v_gaji, v_opex, 0, v_laba,
    v_pct_u, v_pct_t,
    v_bagi_u, v_bagi_t,
    now(),
    case when p_lock then now() else null end,
    auth.uid(),
    now()
  )
  on conflict (toko_id, periode_ym) do update set
    status = excluded.status,
    omzet = excluded.omzet,
    hpp = excluded.hpp,
    gaji = excluded.gaji,
    opex = excluded.opex,
    laba_bersih = excluded.laba_bersih,
    pct_owner_utama = excluded.pct_owner_utama,
    pct_owner_toko = excluded.pct_owner_toko,
    bagi_owner_utama = excluded.bagi_owner_utama,
    bagi_owner_toko = excluded.bagi_owner_toko,
    computed_at = excluded.computed_at,
    locked_at = coalesce(b.locked_at, excluded.locked_at),
    computed_by = excluded.computed_by,
    updated_at = now()
  returning b.id into v_period_id;

  delete from public.bagi_hasil_lines where period_id = v_period_id;
  insert into public.bagi_hasil_lines (period_id, line_key, label, amount) values
    (v_period_id, 'omzet', 'Omzet bersih POS', v_omzet),
    (v_period_id, 'hpp', 'HPP / modal', v_hpp),
    (v_period_id, 'gaji', 'Gaji karyawan', v_gaji),
    (v_period_id, 'opex', 'Opex / pengeluaran', v_opex),
    (v_period_id, 'laba', 'Laba bersih', v_laba),
    (v_period_id, 'bagi_utama', 'Bagi Owner Utama', v_bagi_u),
    (v_period_id, 'bagi_toko', 'Bagi Owner Toko', v_bagi_t);

  perform public.owner_write_audit(
    'compute_bagi_hasil',
    'bagi_hasil_period',
    v_period_id::text,
    jsonb_build_object('toko_id', p_toko_id, 'periode_ym', v_ym, 'lock', p_lock)
  );

  select to_jsonb(b.*) into v_out
  from public.bagi_hasil_period b
  where b.id = v_period_id;

  return v_out;
end;
$$;

revoke all on function public.owner_compute_bagi_hasil(text, text, boolean) from public;
grant execute on function public.owner_compute_bagi_hasil(text, text, boolean) to authenticated;
