-- Enterprise GL: Chart of Accounts, journals (balanced), fiscal periods.

-- -----------------------------------------------------------------------------
-- 1. Chart of Accounts
-- -----------------------------------------------------------------------------
create table if not exists public.chart_of_accounts (
  kode text primary key,
  nama text not null,
  tipe text not null check (tipe in (
    'ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'COGS', 'EXPENSE'
  )),
  normal_balance text not null check (normal_balance in ('DEBIT', 'CREDIT')),
  parent_kode text references public.chart_of_accounts (kode),
  is_postable boolean not null default true,
  aktif boolean not null default true,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 2. Fiscal periods
-- -----------------------------------------------------------------------------
create table if not exists public.fiscal_periods (
  id uuid primary key default gen_random_uuid(),
  tahun int not null,
  bulan int not null check (bulan between 1 and 12),
  status text not null default 'OPEN' check (status in ('OPEN', 'CLOSED')),
  closed_at timestamptz,
  closed_by text,
  created_at timestamptz not null default now(),
  unique (tahun, bulan)
);

-- -----------------------------------------------------------------------------
-- 3. Journal entries + lines
-- -----------------------------------------------------------------------------
create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  toko_id text references public.toko_id (id),
  tanggal date not null,
  periode_id uuid not null references public.fiscal_periods (id),
  sumber text not null check (sumber in ('POS', 'CLOSING', 'MANUAL', 'SYSTEM', 'REVERSE')),
  referensi_id text,
  memo text,
  status text not null default 'POSTED' check (status in ('POSTED', 'VOID')),
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists journal_entries_sumber_ref_uidx
  on public.journal_entries (sumber, referensi_id)
  where referensi_id is not null
    and btrim(referensi_id) <> ''
    and status = 'POSTED';

create index if not exists journal_entries_toko_tgl_idx
  on public.journal_entries (toko_id, tanggal);

create index if not exists journal_entries_periode_idx
  on public.journal_entries (periode_id);

create table if not exists public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.journal_entries (id) on delete cascade,
  akun_kode text not null references public.chart_of_accounts (kode),
  debit bigint not null default 0 check (debit >= 0),
  kredit bigint not null default 0 check (kredit >= 0),
  memo text,
  created_at timestamptz not null default now(),
  constraint journal_lines_xor_dk check (
    (debit > 0 and kredit = 0) or (kredit > 0 and debit = 0)
  )
);

create index if not exists journal_lines_entry_idx
  on public.journal_lines (entry_id);

create index if not exists journal_lines_akun_idx
  on public.journal_lines (akun_kode);

-- -----------------------------------------------------------------------------
-- 4. Seed COA
-- -----------------------------------------------------------------------------
insert into public.chart_of_accounts
  (kode, nama, tipe, normal_balance, parent_kode, is_postable, aktif)
values
  ('1000', 'Aset', 'ASSET', 'DEBIT', null, false, true),
  ('1100', 'Aset Lancar', 'ASSET', 'DEBIT', '1000', false, true),
  ('1101', 'Kas', 'ASSET', 'DEBIT', '1100', true, true),
  ('1102', 'Bank', 'ASSET', 'DEBIT', '1100', true, true),
  ('1103', 'Piutang Usaha', 'ASSET', 'DEBIT', '1100', true, true),
  ('1201', 'Persediaan', 'ASSET', 'DEBIT', '1100', true, true),
  ('2000', 'Kewajiban', 'LIABILITY', 'CREDIT', null, false, true),
  ('2101', 'Hutang Usaha', 'LIABILITY', 'CREDIT', '2000', true, true),
  ('2102', 'PPN Keluaran', 'LIABILITY', 'CREDIT', '2000', true, true),
  ('3000', 'Ekuitas', 'EQUITY', 'CREDIT', null, false, true),
  ('3101', 'Modal', 'EQUITY', 'CREDIT', '3000', true, true),
  ('4000', 'Pendapatan', 'REVENUE', 'CREDIT', null, false, true),
  ('4100', 'Penjualan', 'REVENUE', 'CREDIT', '4000', true, true),
  ('4102', 'Pendapatan Lain', 'REVENUE', 'CREDIT', '4000', true, true),
  ('5000', 'Beban', 'EXPENSE', 'DEBIT', null, false, true),
  ('5100', 'HPP', 'COGS', 'DEBIT', '5000', true, true),
  ('5200', 'Beban Operasional', 'EXPENSE', 'DEBIT', '5000', true, true),
  ('5201', 'Selisih Kas', 'EXPENSE', 'DEBIT', '5000', true, true)
on conflict (kode) do update set
  nama = excluded.nama,
  tipe = excluded.tipe,
  normal_balance = excluded.normal_balance,
  parent_kode = excluded.parent_kode,
  is_postable = excluded.is_postable,
  aktif = excluded.aktif;

-- -----------------------------------------------------------------------------
-- 5. Seed fiscal periods (current year + next year, OPEN)
-- -----------------------------------------------------------------------------
insert into public.fiscal_periods (tahun, bulan, status)
select y.tahun, m.bulan, 'OPEN'
from generate_series(
  extract(year from now())::int,
  extract(year from now())::int + 1
) as y(tahun)
cross join generate_series(1, 12) as m(bulan)
on conflict (tahun, bulan) do nothing;

-- -----------------------------------------------------------------------------
-- 6. Helpers
-- -----------------------------------------------------------------------------
create or replace function public._gl_ensure_period(p_tanggal date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_tahun int := extract(year from p_tanggal)::int;
  v_bulan int := extract(month from p_tanggal)::int;
begin
  select id into v_id
  from public.fiscal_periods
  where tahun = v_tahun and bulan = v_bulan;

  if v_id is null then
    insert into public.fiscal_periods (tahun, bulan, status)
    values (v_tahun, v_bulan, 'OPEN')
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. RPC: post balanced journal (idempotent by sumber+referensi_id)
-- -----------------------------------------------------------------------------
create or replace function public.post_journal_balanced(
  p_toko_id text,
  p_tanggal date,
  p_sumber text,
  p_referensi_id text,
  p_memo text,
  p_lines jsonb,
  p_created_by text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_periode_id uuid;
  v_status text;
  v_entry_id uuid;
  v_sum_d bigint := 0;
  v_sum_k bigint := 0;
  v_line jsonb;
  v_akun text;
  v_debit bigint;
  v_kredit bigint;
  v_line_memo text;
begin
  if p_toko_id is null or btrim(p_toko_id) = '' then
    raise exception 'toko_id wajib diisi';
  end if;
  if p_tanggal is null then
    raise exception 'tanggal wajib diisi';
  end if;
  if p_sumber is null or p_sumber not in ('POS', 'CLOSING', 'MANUAL', 'SYSTEM', 'REVERSE') then
    raise exception 'sumber tidak valid: %', p_sumber;
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'minimal 2 baris jurnal';
  end if;

  -- Idempotent: return existing POSTED entry
  if p_referensi_id is not null and btrim(p_referensi_id) <> '' then
    select id into v_entry_id
    from public.journal_entries
    where sumber = p_sumber
      and referensi_id = p_referensi_id
      and status = 'POSTED'
    limit 1;
    if v_entry_id is not null then
      return v_entry_id;
    end if;
  end if;

  v_periode_id := public._gl_ensure_period(p_tanggal);
  select status into v_status from public.fiscal_periods where id = v_periode_id;
  if v_status = 'CLOSED' then
    raise exception 'Periode %-% sudah ditutup',
      extract(year from p_tanggal)::int,
      extract(month from p_tanggal)::int;
  end if;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_akun := coalesce(v_line->>'akun_kode', '');
    v_debit := coalesce((v_line->>'debit')::bigint, 0);
    v_kredit := coalesce((v_line->>'kredit')::bigint, 0);

    if v_akun = '' then
      raise exception 'akun_kode wajib diisi';
    end if;
    if not exists (
      select 1 from public.chart_of_accounts
      where kode = v_akun and aktif and is_postable
    ) then
      raise exception 'Akun % tidak postable / tidak aktif', v_akun;
    end if;
    if v_debit < 0 or v_kredit < 0 then
      raise exception 'debit/kredit tidak boleh negatif';
    end if;
    if not ((v_debit > 0 and v_kredit = 0) or (v_kredit > 0 and v_debit = 0)) then
      raise exception 'Setiap baris harus murni debit atau kredit';
    end if;
    v_sum_d := v_sum_d + v_debit;
    v_sum_k := v_sum_k + v_kredit;
  end loop;

  if v_sum_d = 0 or v_sum_d <> v_sum_k then
    raise exception 'Jurnal tidak berimbang: debit=% kredit=%', v_sum_d, v_sum_k;
  end if;

  insert into public.journal_entries (
    toko_id, tanggal, periode_id, sumber, referensi_id, memo, status, created_by
  ) values (
    upper(p_toko_id), p_tanggal, v_periode_id, p_sumber,
    nullif(btrim(coalesce(p_referensi_id, '')), ''),
    p_memo, 'POSTED', p_created_by
  ) returning id into v_entry_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_akun := v_line->>'akun_kode';
    v_debit := coalesce((v_line->>'debit')::bigint, 0);
    v_kredit := coalesce((v_line->>'kredit')::bigint, 0);
    v_line_memo := v_line->>'memo';
    insert into public.journal_lines (entry_id, akun_kode, debit, kredit, memo)
    values (v_entry_id, v_akun, v_debit, v_kredit, v_line_memo);
  end loop;

  return v_entry_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. RPC: void journal (reverse + mark VOID)
-- -----------------------------------------------------------------------------
create or replace function public.void_journal_entry(
  p_entry_id uuid,
  p_created_by text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_je public.journal_entries%rowtype;
  v_lines jsonb := '[]'::jsonb;
  v_reverse_id uuid;
  v_ref text;
begin
  select * into v_je from public.journal_entries where id = p_entry_id;
  if not found then
    raise exception 'Jurnal tidak ditemukan';
  end if;
  if v_je.status = 'VOID' then
    raise exception 'Jurnal sudah di-void';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'akun_kode', jl.akun_kode,
      'debit', jl.kredit,
      'kredit', jl.debit,
      'memo', coalesce(jl.memo, 'Void')
    )
  ), '[]'::jsonb)
  into v_lines
  from public.journal_lines jl
  where jl.entry_id = p_entry_id;

  v_ref := 'VOID-' || p_entry_id::text;
  v_reverse_id := public.post_journal_balanced(
    v_je.toko_id,
    current_date,
    'REVERSE',
    v_ref,
    'Void: ' || coalesce(v_je.memo, p_entry_id::text),
    v_lines,
    p_created_by
  );

  update public.journal_entries
  set status = 'VOID', updated_at = now()
  where id = p_entry_id;

  return v_reverse_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. RPC: close fiscal period
-- -----------------------------------------------------------------------------
create or replace function public.close_fiscal_period(
  p_tahun int,
  p_bulan int,
  p_closed_by text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_bulan < 1 or p_bulan > 12 then
    raise exception 'Bulan tidak valid';
  end if;

  update public.fiscal_periods
  set status = 'CLOSED',
      closed_at = now(),
      closed_by = p_closed_by
  where tahun = p_tahun and bulan = p_bulan
  returning id into v_id;

  if v_id is null then
    insert into public.fiscal_periods (tahun, bulan, status, closed_at, closed_by)
    values (p_tahun, p_bulan, 'CLOSED', now(), p_closed_by)
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

create or replace function public.reopen_fiscal_period(
  p_tahun int,
  p_bulan int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  update public.fiscal_periods
  set status = 'OPEN', closed_at = null, closed_by = null
  where tahun = p_tahun and bulan = p_bulan
  returning id into v_id;

  if v_id is null then
    raise exception 'Periode tidak ditemukan';
  end if;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. RLS
-- -----------------------------------------------------------------------------
alter table public.chart_of_accounts enable row level security;
alter table public.fiscal_periods enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

drop policy if exists chart_of_accounts_auth_all on public.chart_of_accounts;
create policy chart_of_accounts_auth_all on public.chart_of_accounts
  for all to authenticated using (true) with check (true);

drop policy if exists fiscal_periods_auth_select on public.fiscal_periods;
create policy fiscal_periods_auth_select on public.fiscal_periods
  for select to authenticated using (true);

drop policy if exists journal_entries_auth_select on public.journal_entries;
create policy journal_entries_auth_select on public.journal_entries
  for select to authenticated using (true);

drop policy if exists journal_lines_auth_select on public.journal_lines;
create policy journal_lines_auth_select on public.journal_lines
  for select to authenticated using (true);

-- Writes go through security definer RPCs
grant execute on function public.post_journal_balanced(text, date, text, text, text, jsonb, text)
  to authenticated;
grant execute on function public.void_journal_entry(uuid, text) to authenticated;
grant execute on function public.close_fiscal_period(int, int, text) to authenticated;
grant execute on function public.reopen_fiscal_period(int, int) to authenticated;
