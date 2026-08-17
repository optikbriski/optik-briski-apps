-- =============================================================================
-- Owner APK spine: owners profile, toko map, bagi hasil 50/50, payroll monitor,
-- scoped RPCs, audit log. Idempotent.
-- Project: ualqiiprtjysdmtqkpzr
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Karyawan: gaji pokok (expense line for bagi hasil / payroll monitor)
-- -----------------------------------------------------------------------------
alter table public.karyawan
  add column if not exists gaji_pokok bigint not null default 0;

comment on column public.karyawan.gaji_pokok is
  'Gaji pokok bulanan (IDR). Digunakan estimasi beban gaji bagi hasil.';

-- -----------------------------------------------------------------------------
-- 2. Owners (1:1 auth.users) — type utama | toko
-- Auth gate for Owner APK: profiles.role = 'owner' + row di public.owners
-- -----------------------------------------------------------------------------
create table if not exists public.owners (
  id uuid primary key references auth.users (id) on delete cascade,
  owner_type text not null
    check (owner_type in ('utama', 'toko')),
  nama text not null,
  email text not null,
  phone text,
  status text not null default 'aktif'
    check (status in ('aktif', 'nonaktif', 'suspend')),
  kontrak_status text not null default 'aktif'
    check (kontrak_status in ('draft', 'aktif', 'habis', 'terminated')),
  kontrak_mulai date,
  kontrak_selesai date,
  catatan text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists owners_type_idx on public.owners (owner_type);
create index if not exists owners_email_idx on public.owners (lower(email));

-- -----------------------------------------------------------------------------
-- 3. Owner ↔ toko map (+ default split 50/50 per toko)
-- Owner Utama: boleh kosong (lihat semua) ATAU map eksplisit.
-- Owner Toko: wajib ≥1 toko.
-- -----------------------------------------------------------------------------
create table if not exists public.owner_toko_map (
  owner_id uuid not null references public.owners (id) on delete cascade,
  toko_id text not null references public.toko_id (id) on delete cascade,
  pct_owner_utama numeric(5,2) not null default 50.00
    check (pct_owner_utama >= 0 and pct_owner_utama <= 100),
  pct_owner_toko numeric(5,2) not null default 50.00
    check (pct_owner_toko >= 0 and pct_owner_toko <= 100),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (owner_id, toko_id),
  constraint owner_toko_pct_sum_100
    check (round(pct_owner_utama + pct_owner_toko, 2) = 100.00)
);

create index if not exists owner_toko_map_toko_idx on public.owner_toko_map (toko_id);

-- Enforce 1 Owner Toko aktif per toko via trigger
create or replace function public.owner_toko_map_enforce_one_toko_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
  v_other uuid;
begin
  select owner_type into v_type from public.owners where id = new.owner_id;
  if v_type = 'toko' then
    select m.owner_id into v_other
    from public.owner_toko_map m
    join public.owners o on o.id = m.owner_id
    where m.toko_id = new.toko_id
      and o.owner_type = 'toko'
      and o.status = 'aktif'
      and m.owner_id <> new.owner_id
    limit 1;
    if v_other is not null then
      raise exception 'Toko % sudah punya Owner Toko aktif', new.toko_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_owner_toko_map_one on public.owner_toko_map;
create trigger trg_owner_toko_map_one
  before insert or update on public.owner_toko_map
  for each row execute function public.owner_toko_map_enforce_one_toko_owner();

-- -----------------------------------------------------------------------------
-- 4. Bagi hasil period + lines
-- -----------------------------------------------------------------------------
create table if not exists public.bagi_hasil_period (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id) on delete cascade,
  periode_ym text not null
    check (periode_ym ~ '^\d{4}-\d{2}$'),
  status text not null default 'draft'
    check (status in ('draft', 'dikunci', 'dibayar')),
  omzet bigint not null default 0,
  hpp bigint not null default 0,
  gaji bigint not null default 0,
  opex bigint not null default 0,
  potongan_lain bigint not null default 0,
  laba_bersih bigint not null default 0,
  pct_owner_utama numeric(5,2) not null default 50.00,
  pct_owner_toko numeric(5,2) not null default 50.00,
  bagi_owner_utama bigint not null default 0,
  bagi_owner_toko bigint not null default 0,
  computed_at timestamptz,
  locked_at timestamptz,
  paid_at timestamptz,
  computed_by uuid references auth.users (id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (toko_id, periode_ym)
);

create index if not exists bagi_hasil_period_ym_idx
  on public.bagi_hasil_period (periode_ym desc);

create table if not exists public.bagi_hasil_lines (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.bagi_hasil_period (id) on delete cascade,
  line_key text not null,
  label text not null,
  amount bigint not null default 0,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (period_id, line_key)
);

-- -----------------------------------------------------------------------------
-- 5. Owner alerts + audit + utang/saldo stubs
-- -----------------------------------------------------------------------------
create table if not exists public.owner_alerts (
  id uuid primary key default gen_random_uuid(),
  toko_id text references public.toko_id (id) on delete set null,
  severity text not null default 'info'
    check (severity in ('info', 'warning', 'critical')),
  category text not null default 'umum',
  title text not null,
  body text,
  is_read boolean not null default false,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists owner_alerts_created_idx
  on public.owner_alerts (created_at desc);
create index if not exists owner_alerts_toko_idx
  on public.owner_alerts (toko_id, created_at desc);

create table if not exists public.owner_audit_log (
  id bigserial primary key,
  actor_id uuid,
  action text not null,
  entity text,
  entity_id text,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists owner_audit_log_created_idx
  on public.owner_audit_log (created_at desc);

-- Stub saldo pusat ↔ toko (fase berikutnya: settlement penuh)
create table if not exists public.owner_saldo_pusat_toko (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id) on delete cascade,
  saldo_pusat_ke_toko bigint not null default 0,
  saldo_toko_ke_pusat bigint not null default 0,
  notes text,
  updated_at timestamptz not null default now(),
  unique (toko_id)
);

-- -----------------------------------------------------------------------------
-- 6. Helpers: current owner + scoped toko ids
-- -----------------------------------------------------------------------------
create or replace function public.is_owner_role()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) = 'owner'
  );
$$;

create or replace function public.is_admin_pusat_or_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
  );
$$;

-- Provision / write pusat: admin_pusat, super_admin, atau Owner Utama saja
create or replace function public.is_owner_provisioner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    left join public.owners o on o.id = p.id
    where p.id = auth.uid()
      and (
        lower(coalesce(p.role, '')) in ('admin_pusat', 'super_admin')
        or (
          lower(coalesce(p.role, '')) = 'owner'
          and coalesce(o.owner_type, 'utama') = 'utama'
        )
      )
  );
$$;

create or replace function public.owner_current()
returns public.owners
language sql
stable
security definer
set search_path = public
as $$
  select o.*
  from public.owners o
  where o.id = auth.uid()
    and o.status = 'aktif'
  limit 1;
$$;

create or replace function public.owner_accessible_toko_ids()
returns setof text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner public.owners%rowtype;
begin
  if not public.is_owner_role() then
    return;
  end if;

  select * into v_owner from public.owner_current();
  if v_owner.id is null then
    return;
  end if;

  if v_owner.owner_type = 'utama' then
    -- Semua cabang kecuali label PUSAT murni opsional tetap ikut (Owner Utama lihat semua)
    return query
      select t.id from public.toko_id t
      order by t.id;
    return;
  end if;

  return query
    select m.toko_id
    from public.owner_toko_map m
    where m.owner_id = v_owner.id
    order by m.toko_id;
end;
$$;

create or replace function public.owner_can_access_toko(p_toko_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.owner_accessible_toko_ids() t
    where t = p_toko_id
  );
$$;

create or replace function public.owner_write_audit(
  p_action text,
  p_entity text default null,
  p_entity_id text default null,
  p_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.owner_audit_log (actor_id, action, entity, entity_id, detail)
  values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_detail, '{}'::jsonb));
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. RLS
-- -----------------------------------------------------------------------------
alter table public.owners enable row level security;
alter table public.owner_toko_map enable row level security;
alter table public.bagi_hasil_period enable row level security;
alter table public.bagi_hasil_lines enable row level security;
alter table public.owner_alerts enable row level security;
alter table public.owner_audit_log enable row level security;
alter table public.owner_saldo_pusat_toko enable row level security;

drop policy if exists owners_self_select on public.owners;
create policy owners_self_select on public.owners
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_admin_pusat_or_owner()
  );

drop policy if exists owners_admin_write on public.owners;
create policy owners_admin_write on public.owners
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists owner_toko_map_select on public.owner_toko_map;
create policy owner_toko_map_select on public.owner_toko_map
  for select to authenticated
  using (
    owner_id = auth.uid()
    or public.is_admin_pusat_or_owner()
  );

drop policy if exists owner_toko_map_admin_write on public.owner_toko_map;
create policy owner_toko_map_admin_write on public.owner_toko_map
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists bagi_hasil_period_select on public.bagi_hasil_period;
create policy bagi_hasil_period_select on public.bagi_hasil_period
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.owner_can_access_toko(toko_id)
  );

drop policy if exists bagi_hasil_period_admin_write on public.bagi_hasil_period;
create policy bagi_hasil_period_admin_write on public.bagi_hasil_period
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists bagi_hasil_lines_select on public.bagi_hasil_lines;
create policy bagi_hasil_lines_select on public.bagi_hasil_lines
  for select to authenticated
  using (
    exists (
      select 1 from public.bagi_hasil_period p
      where p.id = period_id
        and (
          public.is_admin_pusat_or_owner()
          or public.owner_can_access_toko(p.toko_id)
        )
    )
  );

drop policy if exists bagi_hasil_lines_admin_write on public.bagi_hasil_lines;
create policy bagi_hasil_lines_admin_write on public.bagi_hasil_lines
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists owner_alerts_select on public.owner_alerts;
create policy owner_alerts_select on public.owner_alerts
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or toko_id is null
    or public.owner_can_access_toko(toko_id)
  );

drop policy if exists owner_alerts_update_read on public.owner_alerts;
create policy owner_alerts_update_read on public.owner_alerts
  for update to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or toko_id is null
    or public.owner_can_access_toko(toko_id)
  )
  with check (true);

drop policy if exists owner_alerts_admin_insert on public.owner_alerts;
create policy owner_alerts_admin_insert on public.owner_alerts
  for insert to authenticated
  with check (public.is_owner_provisioner());

drop policy if exists owner_audit_admin_select on public.owner_audit_log;
create policy owner_audit_admin_select on public.owner_audit_log
  for select to authenticated
  using (public.is_owner_provisioner() or actor_id = auth.uid());

drop policy if exists owner_saldo_select on public.owner_saldo_pusat_toko;
create policy owner_saldo_select on public.owner_saldo_pusat_toko
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.owner_can_access_toko(toko_id)
  );

drop policy if exists owner_saldo_admin_write on public.owner_saldo_pusat_toko;
create policy owner_saldo_admin_write on public.owner_saldo_pusat_toko
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

-- -----------------------------------------------------------------------------
-- 8. RPCs — profile / cabang / ringkasan / payroll / approvals / alerts
-- -----------------------------------------------------------------------------
create or replace function public.owner_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner public.owners%rowtype;
  v_profile public.profiles%rowtype;
  v_toko text[];
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;

  select * into v_profile from public.profiles where id = auth.uid();
  if v_profile.id is null or lower(coalesce(v_profile.role, '')) <> 'owner' then
    raise exception 'Bukan akun Owner';
  end if;

  select * into v_owner from public.owners where id = auth.uid();
  if v_owner.id is null then
    raise exception 'Owner profile belum diprovision';
  end if;

  select coalesce(array_agg(t order by t), '{}')
    into v_toko
  from public.owner_accessible_toko_ids() t;

  return jsonb_build_object(
    'id', v_owner.id,
    'owner_type', v_owner.owner_type,
    'nama', v_owner.nama,
    'email', v_owner.email,
    'phone', v_owner.phone,
    'status', v_owner.status,
    'kontrak_status', v_owner.kontrak_status,
    'kontrak_mulai', v_owner.kontrak_mulai,
    'kontrak_selesai', v_owner.kontrak_selesai,
    'profile_toko_id', v_profile.toko_id,
    'toko_ids', to_jsonb(v_toko)
  );
end;
$$;

revoke all on function public.owner_my_profile() from public;
grant execute on function public.owner_my_profile() to authenticated;

create or replace function public.owner_list_cabang()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.toko_id), '[]'::jsonb)
  into v_rows
  from (
    select
      t.id as toko_id,
      t.toko_id as nama,
      coalesce(m.pct_owner_utama, 50.00) as pct_owner_utama,
      coalesce(m.pct_owner_toko, 50.00) as pct_owner_toko,
      coalesce(m.is_primary, false) as is_primary,
      coalesce(s.saldo_pusat_ke_toko, 0) as saldo_pusat_ke_toko,
      coalesce(s.saldo_toko_ke_pusat, 0) as saldo_toko_ke_pusat
    from public.toko_id t
    left join public.owner_toko_map m
      on m.toko_id = t.id and m.owner_id = auth.uid()
    left join public.owner_saldo_pusat_toko s on s.toko_id = t.id
    where t.id in (select public.owner_accessible_toko_ids())
  ) x;

  return v_rows;
end;
$$;

revoke all on function public.owner_list_cabang() from public;
grant execute on function public.owner_list_cabang() to authenticated;

create or replace function public.owner_ringkasan(
  p_toko_id text default null,
  p_periode_ym text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ym text := coalesce(nullif(trim(p_periode_ym), ''), to_char(now(), 'YYYY-MM'));
  v_start date;
  v_end date;
  v_toko text[];
  v_omzet bigint := 0;
  v_hpp bigint := 0;
  v_opex bigint := 0;
  v_gaji bigint := 0;
  v_invoice int := 0;
  v_karyawan int := 0;
  v_pending int := 0;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;

  v_start := (v_ym || '-01')::date;
  v_end := (v_start + interval '1 month')::date;

  if p_toko_id is not null and length(trim(p_toko_id)) > 0 then
    if not public.owner_can_access_toko(p_toko_id) then
      raise exception 'Toko di luar scope Owner';
    end if;
    v_toko := array[p_toko_id];
  else
    select coalesce(array_agg(t), '{}') into v_toko
    from public.owner_accessible_toko_ids() t;
  end if;

  select
    coalesce(sum(s.total_harga), 0),
    coalesce(sum(
      (select coalesce(sum(si.qty * coalesce(p.harga_modal, 0)), 0)
       from public.sales_items si
       left join public.products p on p.id = si.product_id
       where si.sale_id = s.id)
    ), 0),
    count(*)::int
  into v_omzet, v_hpp, v_invoice
  from public.sales s
  where s.toko_id = any (v_toko)
    and s.created_at >= v_start
    and s.created_at < v_end
    and coalesce(s.nama_pelanggan, '') not ilike '%Modal Awal%';

  select coalesce(sum(ft.nominal), 0) into v_opex
  from public.finance_transactions ft
  where ft.toko_id = any (v_toko)
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
    and upper(coalesce(ft.status_konfirmasi, '')) in ('APPROVED', 'OK', 'CONFIRMED', 'DISETUJUI');

  -- Estimasi gaji: sum gaji_pokok karyawan Aktif di toko scope (bulan penuh)
  select coalesce(sum(k.gaji_pokok), 0), count(*)::int
  into v_gaji, v_karyawan
  from public.karyawan k
  where k.toko_id = any (v_toko)
    and k.status_approval = 'Aktif';

  select count(*)::int into v_pending
  from public.karyawan k
  where k.toko_id = any (v_toko)
    and k.status_approval in ('Pending', 'Menunggu OTP', 'Menunggu Persetujuan');

  return jsonb_build_object(
    'periode_ym', v_ym,
    'toko_ids', to_jsonb(v_toko),
    'omzet', v_omzet,
    'hpp', v_hpp,
    'opex', v_opex,
    'gaji', v_gaji,
    'laba_bersih_est', v_omzet - v_hpp - v_opex - v_gaji,
    'invoice_count', v_invoice,
    'karyawan_aktif', v_karyawan,
    'karyawan_pending', v_pending,
    'bagi_utama_est', round((v_omzet - v_hpp - v_opex - v_gaji) * 0.5),
    'bagi_toko_est', round((v_omzet - v_hpp - v_opex - v_gaji) * 0.5)
  );
end;
$$;

revoke all on function public.owner_ringkasan(text, text) from public;
grant execute on function public.owner_ringkasan(text, text) to authenticated;

create or replace function public.owner_list_tim(p_toko_id text default null)
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
      raise exception 'Toko di luar scope Owner';
    end if;
    v_toko := array[p_toko_id];
  else
    select coalesce(array_agg(t), '{}') into v_toko
    from public.owner_accessible_toko_ids() t;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.toko_id, x.nama), '[]'::jsonb)
  into v_rows
  from (
    select
      k.id,
      k.nama,
      k.jabatan,
      k.toko_id,
      k.status_approval,
      coalesce(k.gaji_pokok, 0) as gaji_pokok,
      k.email,
      k.wa
    from public.karyawan k
    where k.toko_id = any (v_toko)
      and k.status_approval in (
        'Aktif', 'Pending', 'Menunggu OTP', 'Menunggu Persetujuan'
      )
  ) x;

  return v_rows;
end;
$$;

revoke all on function public.owner_list_tim(text) from public;
grant execute on function public.owner_list_tim(text) to authenticated;

create or replace function public.owner_payroll_monitor(p_toko_id text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text[];
  v_rows jsonb;
  v_total bigint := 0;
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

  select coalesce(jsonb_agg(to_jsonb(x) order by x.toko_id, x.nama), '[]'::jsonb),
         coalesce(sum(x.gaji_pokok), 0)
  into v_rows, v_total
  from (
    select
      k.id,
      k.nama,
      k.jabatan,
      k.toko_id,
      coalesce(k.gaji_pokok, 0) as gaji_pokok
    from public.karyawan k
    where k.toko_id = any (v_toko)
      and k.status_approval = 'Aktif'
  ) x;

  return jsonb_build_object(
    'lines', coalesce(v_rows, '[]'::jsonb),
    'total_gaji_pokok', v_total,
    'note', 'Estimasi dari gaji_pokok karyawan aktif (bukan payroll period penuh).'
  );
end;
$$;

revoke all on function public.owner_payroll_monitor(text) from public;
grant execute on function public.owner_payroll_monitor(text) to authenticated;

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
      j.status,
      j.created_at,
      k.nama as karyawan_nama
    from public.jadwal_pengajuan j
    left join public.karyawan k on k.id = j.karyawan_id
    where j.toko_id = any (v_toko)
      and upper(coalesce(j.status, '')) = 'PENDING'
    limit 100
  ) x;

  return jsonb_build_object(
    'karyawan_pending', coalesce(v_karyawan, '[]'::jsonb),
    'jadwal_pending', coalesce(v_jadwal, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.owner_list_persetujuan() from public;
grant execute on function public.owner_list_persetujuan() to authenticated;

create or replace function public.owner_list_alerts(p_limit int default 50)
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

  select coalesce(array_agg(t), '{}') into v_toko
  from public.owner_accessible_toko_ids() t;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into v_rows
  from (
    select a.*
    from public.owner_alerts a
    where a.toko_id is null or a.toko_id = any (v_toko)
    order by a.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) x;

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

revoke all on function public.owner_list_alerts(int) from public;
grant execute on function public.owner_list_alerts(int) to authenticated;

create or replace function public.owner_mark_alert_read(p_alert_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;

  update public.owner_alerts a
  set is_read = true
  where a.id = p_alert_id
    and (a.toko_id is null or public.owner_can_access_toko(a.toko_id));

  return found;
end;
$$;

revoke all on function public.owner_mark_alert_read(uuid) from public;
grant execute on function public.owner_mark_alert_read(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. Bagi hasil compute / list / lock (server-side 50/50)
-- -----------------------------------------------------------------------------
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
  v_row public.bagi_hasil_period%rowtype;
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

  -- Prefer % dari map Owner Toko aktif; fallback 50/50
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

  select coalesce(sum(k.gaji_pokok), 0) into v_gaji
  from public.karyawan k
  where k.toko_id = p_toko_id
    and k.status_approval = 'Aktif';

  v_laba := v_omzet - v_hpp - v_opex - v_gaji;
  v_bagi_u := round(v_laba * (v_pct_u / 100.0));
  v_bagi_t := v_laba - v_bagi_u; -- sisa ke toko agar total = laba

  select * into v_row
  from public.bagi_hasil_period
  where toko_id = p_toko_id and periode_ym = v_ym;

  if v_row.id is not null and v_row.status in ('dikunci', 'dibayar') then
    return to_jsonb(v_row) || jsonb_build_object('readonly', true);
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
  returning id into v_period_id;

  delete from public.bagi_hasil_lines where period_id = v_period_id;
  insert into public.bagi_hasil_lines (period_id, line_key, label, amount) values
    (v_period_id, 'omzet', 'Omzet bersih POS', v_omzet),
    (v_period_id, 'hpp', 'HPP / modal', v_hpp),
    (v_period_id, 'gaji', 'Gaji karyawan (estimasi)', v_gaji),
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

  select to_jsonb(b.*) into v_row from public.bagi_hasil_period b where b.id = v_period_id;
  return to_jsonb(v_row);
end;
$$;

revoke all on function public.owner_compute_bagi_hasil(text, text, boolean) from public;
grant execute on function public.owner_compute_bagi_hasil(text, text, boolean) to authenticated;

create or replace function public.owner_list_bagi_hasil(p_toko_id text default null)
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
  if not public.is_owner_role() and not public.is_admin_pusat_or_owner() then
    raise exception 'Unauthorized';
  end if;

  if public.is_owner_role() then
    if p_toko_id is not null and length(trim(p_toko_id)) > 0 then
      if not public.owner_can_access_toko(p_toko_id) then
        raise exception 'Toko di luar scope';
      end if;
      v_toko := array[p_toko_id];
    else
      select coalesce(array_agg(t), '{}') into v_toko
      from public.owner_accessible_toko_ids() t;
    end if;
  else
    if p_toko_id is not null then
      v_toko := array[p_toko_id];
    else
      select coalesce(array_agg(t.id), '{}') into v_toko from public.toko_id t;
    end if;
  end if;

  select coalesce(jsonb_agg(to_jsonb(b) order by b.periode_ym desc, b.toko_id), '[]'::jsonb)
  into v_rows
  from public.bagi_hasil_period b
  where b.toko_id = any (v_toko);

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

revoke all on function public.owner_list_bagi_hasil(text) from public;
grant execute on function public.owner_list_bagi_hasil(text) to authenticated;

-- -----------------------------------------------------------------------------
-- 10. Admin provision Owner (attach existing auth user OR create profile after signup)
-- Edge function creates auth user; this RPC attaches owners + profiles + map.
-- -----------------------------------------------------------------------------
create or replace function public.admin_provision_owner(
  p_user_id uuid,
  p_email text,
  p_nama text,
  p_owner_type text,
  p_toko_ids text[] default '{}',
  p_pct_utama numeric default 50,
  p_pct_toko numeric default 50,
  p_phone text default null,
  p_primary_toko text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := lower(trim(p_owner_type));
  v_toko text;
  v_primary text;
  v_pct_u numeric(5,2) := coalesce(p_pct_utama, 50);
  v_pct_t numeric(5,2) := coalesce(p_pct_toko, 50);
begin
  if not public.is_owner_provisioner() then
    raise exception 'Hanya admin pusat / Owner Utama yang boleh provision Owner';
  end if;

  if v_type not in ('utama', 'toko') then
    raise exception 'owner_type harus utama|toko';
  end if;

  if round(v_pct_u + v_pct_t, 2) <> 100.00 then
    raise exception 'pct harus jumlah 100';
  end if;

  if v_type = 'toko' and (p_toko_ids is null or cardinality(p_toko_ids) < 1) then
    raise exception 'Owner Toko wajib punya minimal 1 toko';
  end if;

  insert into public.profiles (id, email, role, toko_id, updated_at)
  values (
    p_user_id,
    lower(trim(p_email)),
    'owner',
    case
      when v_type = 'utama' then 'PUSAT'
      else coalesce(nullif(p_primary_toko, ''), p_toko_ids[1])
    end,
    now()
  )
  on conflict (id) do update set
    email = excluded.email,
    role = 'owner',
    toko_id = excluded.toko_id,
    updated_at = now();

  insert into public.owners (
    id, owner_type, nama, email, phone, status, kontrak_status, updated_at
  ) values (
    p_user_id, v_type, trim(p_nama), lower(trim(p_email)), p_phone,
    'aktif', 'aktif', now()
  )
  on conflict (id) do update set
    owner_type = excluded.owner_type,
    nama = excluded.nama,
    email = excluded.email,
    phone = excluded.phone,
    status = 'aktif',
    updated_at = now();

  delete from public.owner_toko_map where owner_id = p_user_id;

  if p_toko_ids is not null then
    v_primary := coalesce(nullif(p_primary_toko, ''), p_toko_ids[1]);
    foreach v_toko in array p_toko_ids loop
      insert into public.owner_toko_map (
        owner_id, toko_id, pct_owner_utama, pct_owner_toko, is_primary
      ) values (
        p_user_id, v_toko, v_pct_u, v_pct_t, (v_toko = v_primary)
      )
      on conflict (owner_id, toko_id) do update set
        pct_owner_utama = excluded.pct_owner_utama,
        pct_owner_toko = excluded.pct_owner_toko,
        is_primary = excluded.is_primary;
    end loop;
  end if;

  perform public.owner_write_audit(
    'provision_owner',
    'owners',
    p_user_id::text,
    jsonb_build_object(
      'owner_type', v_type,
      'toko_ids', to_jsonb(p_toko_ids),
      'pct_utama', v_pct_u,
      'pct_toko', v_pct_t
    )
  );

  return jsonb_build_object(
    'ok', true,
    'user_id', p_user_id,
    'owner_type', v_type,
    'email', lower(trim(p_email))
  );
end;
$$;

revoke all on function public.admin_provision_owner(uuid, text, text, text, text[], numeric, numeric, text, text) from public;
grant execute on function public.admin_provision_owner(uuid, text, text, text, text[], numeric, numeric, text, text) to authenticated;

create or replace function public.admin_list_owners()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into v_rows
  from (
    select
      o.*,
      (
        select coalesce(jsonb_agg(m.toko_id order by m.toko_id), '[]'::jsonb)
        from public.owner_toko_map m
        where m.owner_id = o.id
      ) as toko_ids
    from public.owners o
  ) x;

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_owners() from public;
grant execute on function public.admin_list_owners() to authenticated;

-- Optional versi_app row (Owner uses Karyawan APK OTA — flavor karyawan).
-- Kept only as documentation stub; Owner shell does not poll app_flavor=owner.
insert into public.versi_app (
  versi_terbaru, url_download, force_update, catatan_rilis, app_flavor
)
select '1.0.0', '', false, 'Owner shell inside Karyawan APK — use flavor karyawan for OTA', 'owner'
where not exists (
  select 1 from public.versi_app where app_flavor = 'owner'
);

comment on table public.owners is
  'Owner Utama / Owner Toko — auth via profiles.role=owner. Bukan jabatan karyawan. UX di APK Karyawan.';
comment on table public.bagi_hasil_period is
  'Periode bagi hasil bulanan: laba bersih → split default 50/50.';
