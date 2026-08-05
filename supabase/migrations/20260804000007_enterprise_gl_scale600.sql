-- Scale hardening for ~600 toko:
-- server-side report RPCs, tighter RLS, indexes, batch backfill,
-- bank recon, budgets, e-Faktur drafts, owner-gated period close.

-- =============================================================================
-- 0. Auth helpers
-- =============================================================================
create or replace function public.gl_current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(
    (select role from public.profiles where id = auth.uid()),
    ''
  ));
$$;

create or replace function public.gl_current_toko()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select upper(coalesce(
    (select toko_id from public.profiles where id = auth.uid()),
    ''
  ));
$$;

create or replace function public.gl_is_owner_or_pusat()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.gl_current_role() in ('owner', 'superadmin')
      or public.gl_current_toko() = 'PUSAT';
$$;

create or replace function public.gl_can_access_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.gl_is_owner_or_pusat()
    or upper(coalesce(p_toko, '')) = public.gl_current_toko()
    or public.gl_current_toko() = '';
$$;

-- =============================================================================
-- 1. Extra indexes for 600-branch volume
-- =============================================================================
create index if not exists journal_entries_status_tgl_idx
  on public.journal_entries (status, tanggal desc);

create index if not exists journal_entries_toko_status_tgl_idx
  on public.journal_entries (toko_id, status, tanggal desc);

create index if not exists journal_lines_akun_entry_idx
  on public.journal_lines (akun_kode, entry_id);

create index if not exists sales_sisa_toko_created_idx
  on public.sales (toko_id, created_at)
  where coalesce(sisa_tagihan, 0) > 0;

create index if not exists finance_hutang_toko_tgl_idx
  on public.finance_transactions (toko_id, tanggal_transaksi)
  where jenis_transaksi = 'HUTANG';

-- =============================================================================
-- 2. Tighten RLS (read scoped; writes stay via security definer RPCs)
-- =============================================================================
drop policy if exists journal_entries_auth_select on public.journal_entries;
create policy journal_entries_auth_select on public.journal_entries
  for select to authenticated
  using (public.gl_can_access_toko(toko_id));

drop policy if exists journal_lines_auth_select on public.journal_lines;
create policy journal_lines_auth_select on public.journal_lines
  for select to authenticated
  using (
    exists (
      select 1 from public.journal_entries je
      where je.id = entry_id
        and public.gl_can_access_toko(je.toko_id)
    )
  );

drop policy if exists fiscal_periods_auth_select on public.fiscal_periods;
create policy fiscal_periods_auth_select on public.fiscal_periods
  for select to authenticated using (true);

drop policy if exists chart_of_accounts_auth_all on public.chart_of_accounts;
create policy chart_of_accounts_auth_select on public.chart_of_accounts
  for select to authenticated using (true);
create policy chart_of_accounts_auth_write on public.chart_of_accounts
  for all to authenticated
  using (public.gl_is_owner_or_pusat())
  with check (public.gl_is_owner_or_pusat());

-- =============================================================================
-- 3. Owner-gated period close / reopen
-- =============================================================================
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
  if not public.gl_is_owner_or_pusat() then
    raise exception 'Hanya owner/pusat yang boleh menutup periode';
  end if;
  if p_bulan < 1 or p_bulan > 12 then
    raise exception 'Bulan tidak valid';
  end if;

  update public.fiscal_periods
  set status = 'CLOSED',
      closed_at = now(),
      closed_by = coalesce(p_closed_by, public.gl_current_role())
  where tahun = p_tahun and bulan = p_bulan
  returning id into v_id;

  if v_id is null then
    insert into public.fiscal_periods (tahun, bulan, status, closed_at, closed_by)
    values (p_tahun, p_bulan, 'CLOSED', now(), coalesce(p_closed_by, public.gl_current_role()))
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
  if not public.gl_is_owner_or_pusat() then
    raise exception 'Hanya owner/pusat yang boleh membuka periode';
  end if;

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

-- =============================================================================
-- 4. Server-side trial balance / reports (no client aggregation)
-- =============================================================================
create or replace function public.gl_trial_balance(
  p_tahun int,
  p_bulan int,
  p_toko_id text default null
)
returns table (
  kode text,
  nama text,
  tipe text,
  normal_balance text,
  debit bigint,
  kredit bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start date := make_date(p_tahun, p_bulan, 1);
  v_end date := (make_date(p_tahun, p_bulan, 1) + interval '1 month - 1 day')::date;
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
begin
  if v_toko is not null and not public.gl_can_access_toko(v_toko) then
    raise exception 'Tidak berhak akses toko %', v_toko;
  end if;
  if v_toko is null and not public.gl_is_owner_or_pusat() then
    v_toko := public.gl_current_toko();
  end if;

  return query
  select
    c.kode,
    c.nama,
    c.tipe,
    c.normal_balance,
    coalesce(sum(jl.debit), 0)::bigint as debit,
    coalesce(sum(jl.kredit), 0)::bigint as kredit
  from public.chart_of_accounts c
  left join public.journal_lines jl on jl.akun_kode = c.kode
  left join public.journal_entries je
    on je.id = jl.entry_id
   and je.status = 'POSTED'
   and je.tanggal between v_start and v_end
   and (v_toko is null or je.toko_id = v_toko)
  where c.is_postable
    and c.aktif
  group by c.kode, c.nama, c.tipe, c.normal_balance
  having coalesce(sum(jl.debit), 0) <> 0 or coalesce(sum(jl.kredit), 0) <> 0
  order by c.kode;
end;
$$;

create or replace function public.gl_consolidate_by_toko(
  p_tahun int,
  p_bulan int
)
returns table (
  toko_id text,
  pendapatan bigint,
  beban bigint,
  laba bigint,
  kas_bank bigint,
  piutang bigint,
  hutang bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start date := make_date(p_tahun, p_bulan, 1);
  v_end date := (make_date(p_tahun, p_bulan, 1) + interval '1 month - 1 day')::date;
begin
  if not public.gl_is_owner_or_pusat() then
    raise exception 'Konsolidasi hanya untuk owner/pusat';
  end if;

  return query
  with lines as (
    select
      je.toko_id,
      jl.akun_kode,
      c.tipe,
      jl.debit,
      jl.kredit
    from public.journal_entries je
    join public.journal_lines jl on jl.entry_id = je.id
    join public.chart_of_accounts c on c.kode = jl.akun_kode
    where je.status = 'POSTED'
      and je.tanggal between v_start and v_end
  )
  select
    l.toko_id,
    coalesce(sum(case when l.tipe = 'REVENUE' then l.kredit - l.debit else 0 end), 0)::bigint,
    coalesce(sum(case when l.tipe in ('COGS', 'EXPENSE') then l.debit - l.kredit else 0 end), 0)::bigint,
    (
      coalesce(sum(case when l.tipe = 'REVENUE' then l.kredit - l.debit else 0 end), 0)
      - coalesce(sum(case when l.tipe in ('COGS', 'EXPENSE') then l.debit - l.kredit else 0 end), 0)
    )::bigint,
    coalesce(sum(case when l.akun_kode in ('1101', '1102') then l.debit - l.kredit else 0 end), 0)::bigint,
    coalesce(sum(case when l.akun_kode = '1103' then l.debit - l.kredit else 0 end), 0)::bigint,
    coalesce(sum(case when l.akun_kode = '2101' then l.kredit - l.debit else 0 end), 0)::bigint
  from lines l
  group by l.toko_id
  order by l.toko_id;
end;
$$;

create or replace function public.gl_aging_piutang(
  p_toko_id text default null,
  p_limit int default 500
)
returns table (
  ref text,
  nama text,
  toko_id text,
  tanggal date,
  umur_hari int,
  nominal bigint,
  bucket text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
begin
  if v_toko is not null and not public.gl_can_access_toko(v_toko) then
    raise exception 'Tidak berhak akses toko %', v_toko;
  end if;
  if v_toko is null and not public.gl_is_owner_or_pusat() then
    v_toko := public.gl_current_toko();
  end if;

  return query
  select
    coalesce(s.no_invoice, '-')::text,
    coalesce(s.nama_pelanggan, 'Pasien')::text,
    coalesce(s.toko_id, '-')::text,
    (s.created_at at time zone 'Asia/Jakarta')::date,
    greatest(0, (current_date - (s.created_at at time zone 'Asia/Jakarta')::date))::int,
    coalesce(s.sisa_tagihan, 0)::bigint,
    case
      when (current_date - (s.created_at at time zone 'Asia/Jakarta')::date) <= 30 then '0-30'
      when (current_date - (s.created_at at time zone 'Asia/Jakarta')::date) <= 60 then '31-60'
      when (current_date - (s.created_at at time zone 'Asia/Jakarta')::date) <= 90 then '61-90'
      else '90+'
    end
  from public.sales s
  where coalesce(s.sisa_tagihan, 0) > 0
    and (v_toko is null or upper(s.toko_id) = v_toko)
  order by s.created_at
  limit greatest(1, least(coalesce(p_limit, 500), 5000));
end;
$$;

create or replace function public.gl_aging_hutang(
  p_toko_id text default null,
  p_limit int default 500
)
returns table (
  ref text,
  nama text,
  toko_id text,
  tanggal date,
  umur_hari int,
  nominal bigint,
  bucket text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
begin
  if v_toko is not null and not public.gl_can_access_toko(v_toko) then
    raise exception 'Tidak berhak akses toko %', v_toko;
  end if;
  if v_toko is null and not public.gl_is_owner_or_pusat() then
    v_toko := public.gl_current_toko();
  end if;

  return query
  select
    coalesce(ft.id::text, '-')::text,
    coalesce(ft.kategori, 'Hutang')::text,
    coalesce(ft.toko_id, '-')::text,
    coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date),
    greatest(
      0,
      current_date - coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date)
    )::int,
    coalesce(ft.nominal, 0)::bigint,
    case
      when current_date - coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date) <= 30 then '0-30'
      when current_date - coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date) <= 60 then '31-60'
      when current_date - coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date) <= 90 then '61-90'
      else '90+'
    end
  from public.finance_transactions ft
  where ft.jenis_transaksi = 'HUTANG'
    and upper(coalesce(ft.status_pembayaran, '')) <> 'LUNAS'
    and upper(coalesce(ft.status_konfirmasi, '')) <> 'PENDING'
    and (v_toko is null or upper(ft.toko_id) = v_toko)
  order by coalesce(ft.tanggal_transaksi, ft.created_at::date)
  limit greatest(1, least(coalesce(p_limit, 500), 5000));
end;
$$;

-- =============================================================================
-- 5. Batched backfill (server-side, chunked) — safe for 600 toko history
-- =============================================================================
create or replace function public.gl_backfill_sales_batch(
  p_toko_id text default null,
  p_limit int default 200,
  p_created_by text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
  r record;
  v_posted int := 0;
  v_skipped int := 0;
  v_failed int := 0;
  v_total int;
  v_sisa bigint;
  v_bayar bigint;
  v_dpp bigint;
  v_ppn bigint;
  v_asset text;
  v_lines jsonb;
  v_gap bigint;
begin
  if not public.gl_is_owner_or_pusat() then
    raise exception 'Backfill hanya owner/pusat';
  end if;

  for r in
    select s.*
    from public.sales s
    where (v_toko is null or upper(s.toko_id) = v_toko)
      and coalesce(s.total_harga, 0) > 0
      and coalesce(s.no_invoice, '') <> ''
      and not exists (
        select 1 from public.journal_entries je
        where je.sumber = 'POS'
          and je.referensi_id = s.no_invoice
          and je.status = 'POSTED'
      )
    order by s.created_at
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
  loop
    begin
      v_total := coalesce(r.total_harga, 0);
      v_sisa := greatest(coalesce(r.sisa_tagihan, 0), 0);
      v_bayar := greatest(v_total - v_sisa, 0);
      v_dpp := round(v_total / 1.11)::bigint;
      v_ppn := v_total - v_dpp;
      v_asset := case
        when upper(coalesce(r.metode_pembayaran, 'CASH')) in ('CASH', 'TUNAI', '') then '1101'
        else '1102'
      end;

      v_lines := '[]'::jsonb;
      if v_bayar > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object(
          'akun_kode', v_asset, 'debit', v_bayar, 'kredit', 0, 'memo', r.no_invoice
        ));
      end if;
      if v_sisa > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object(
          'akun_kode', '1103', 'debit', v_sisa, 'kredit', 0, 'memo', r.no_invoice
        ));
      end if;
      if v_dpp > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object(
          'akun_kode', '4100', 'debit', 0, 'kredit', v_dpp, 'memo', r.no_invoice
        ));
      end if;
      if v_ppn > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object(
          'akun_kode', '2102', 'debit', 0, 'kredit', v_ppn, 'memo', r.no_invoice
        ));
      end if;

      select coalesce(sum((x->>'debit')::bigint),0) - coalesce(sum((x->>'kredit')::bigint),0)
      into v_gap
      from jsonb_array_elements(v_lines) x;

      if v_gap <> 0 then
        v_lines := (
          select jsonb_agg(
            case
              when e->>'akun_kode' = '4100' then
                jsonb_set(e, '{kredit}', to_jsonb(((e->>'kredit')::bigint - v_gap)))
              else e
            end
          )
          from jsonb_array_elements(v_lines) e
        );
      end if;

      if jsonb_array_length(v_lines) >= 2 then
        perform public.post_journal_balanced(
          upper(r.toko_id),
          (r.created_at at time zone 'Asia/Jakarta')::date,
          'POS',
          r.no_invoice,
          'Backfill POS ' || r.no_invoice,
          v_lines,
          p_created_by
        );
        v_posted := v_posted + 1;
      else
        v_skipped := v_skipped + 1;
      end if;
    exception when others then
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'posted', v_posted,
    'skipped', v_skipped,
    'failed', v_failed
  );
end;
$$;

create or replace function public.gl_backfill_finance_batch(
  p_toko_id text default null,
  p_limit int default 200,
  p_created_by text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
  r record;
  v_posted int := 0;
  v_skipped int := 0;
  v_failed int := 0;
  v_ref text;
  v_asset text;
  v_lines jsonb;
  v_jenis text;
  v_nom bigint;
  v_is_close boolean;
begin
  if not public.gl_is_owner_or_pusat() then
    raise exception 'Backfill hanya owner/pusat';
  end if;

  for r in
    select ft.*
    from public.finance_transactions ft
    where (v_toko is null or upper(ft.toko_id) = v_toko)
      and upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
      and coalesce(ft.nominal, 0) > 0
    order by coalesce(ft.tanggal_transaksi, ft.created_at::date)
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
  loop
    begin
      v_ref := coalesce(nullif(btrim(r.referensi_id), ''), 'FT-' || r.id::text);
      v_is_close := upper(v_ref) like 'CLOSE-%'
        or upper(coalesce(r.kategori, '')) like '%PENUTUPAN%'
        or upper(coalesce(r.kategori, '')) like '%CLOSING%';

      -- Skip POS sale refs (handled by sales backfill)
      if not v_is_close and r.referensi_id is not null and btrim(r.referensi_id) <> ''
         and upper(r.referensi_id) not like 'CLOSE-%'
         and upper(r.referensi_id) not like 'FT-%' then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      if exists (
        select 1 from public.journal_entries je
        where je.status = 'POSTED'
          and (
            (v_is_close and je.sumber = 'CLOSING' and je.referensi_id = v_ref)
            or (not v_is_close and je.sumber = 'MANUAL' and je.referensi_id = 'FT-' || r.id::text)
          )
      ) then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_jenis := upper(coalesce(r.jenis_transaksi, ''));
      v_nom := coalesce(r.nominal, 0);
      v_asset := case
        when upper(coalesce(r.metode_pembayaran, 'CASH')) in ('CASH', 'TUNAI', '') then '1101'
        else '1102'
      end;

      if v_is_close then
        if v_jenis in ('PEMASUKAN', 'PIUTANG') then
          v_lines := jsonb_build_array(
            jsonb_build_object('akun_kode','1101','debit',v_nom,'kredit',0,'memo','Closing'),
            jsonb_build_object('akun_kode','5201','debit',0,'kredit',v_nom,'memo','Closing')
          );
        else
          v_lines := jsonb_build_array(
            jsonb_build_object('akun_kode','5201','debit',v_nom,'kredit',0,'memo','Closing'),
            jsonb_build_object('akun_kode','1101','debit',0,'kredit',v_nom,'memo','Closing')
          );
        end if;
        perform public.post_journal_balanced(
          upper(r.toko_id),
          coalesce(r.tanggal_transaksi, (r.created_at at time zone 'Asia/Jakarta')::date),
          'CLOSING', v_ref, coalesce(r.deskripsi, 'Closing'), v_lines, p_created_by
        );
      else
        v_lines := case v_jenis
          when 'PEMASUKAN' then jsonb_build_array(
            jsonb_build_object('akun_kode',v_asset,'debit',v_nom,'kredit',0),
            jsonb_build_object('akun_kode','4102','debit',0,'kredit',v_nom)
          )
          when 'PENGELUARAN' then jsonb_build_array(
            jsonb_build_object('akun_kode','5200','debit',v_nom,'kredit',0),
            jsonb_build_object('akun_kode',v_asset,'debit',0,'kredit',v_nom)
          )
          when 'PIUTANG' then jsonb_build_array(
            jsonb_build_object('akun_kode','1103','debit',v_nom,'kredit',0),
            jsonb_build_object('akun_kode','4102','debit',0,'kredit',v_nom)
          )
          when 'HUTANG' then jsonb_build_array(
            jsonb_build_object('akun_kode','5200','debit',v_nom,'kredit',0),
            jsonb_build_object('akun_kode','2101','debit',0,'kredit',v_nom)
          )
          else null
        end;
        if v_lines is null then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        perform public.post_journal_balanced(
          upper(r.toko_id),
          coalesce(r.tanggal_transaksi, (r.created_at at time zone 'Asia/Jakarta')::date),
          'MANUAL', 'FT-' || r.id::text, coalesce(r.deskripsi, r.kategori), v_lines, p_created_by
        );
      end if;
      v_posted := v_posted + 1;
    exception when others then
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'posted', v_posted,
    'skipped', v_skipped,
    'failed', v_failed
  );
end;
$$;

-- =============================================================================
-- 6. Bank reconciliation
-- =============================================================================
create table if not exists public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id),
  nama text not null,
  bank_name text not null default 'BCA',
  no_rekening text,
  akun_gl text not null default '1102' references public.chart_of_accounts (kode),
  aktif boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists bank_accounts_toko_idx on public.bank_accounts (toko_id);

create table if not exists public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  bank_account_id uuid not null references public.bank_accounts (id) on delete cascade,
  tanggal date not null,
  deskripsi text,
  debit bigint not null default 0 check (debit >= 0),
  kredit bigint not null default 0 check (kredit >= 0),
  matched_journal_entry_id uuid references public.journal_entries (id),
  status text not null default 'OPEN' check (status in ('OPEN', 'MATCHED', 'IGNORED')),
  created_at timestamptz not null default now(),
  constraint bank_stmt_xor check (
    (debit > 0 and kredit = 0) or (kredit > 0 and debit = 0)
  )
);

create index if not exists bank_stmt_account_tgl_idx
  on public.bank_statement_lines (bank_account_id, tanggal desc);
create index if not exists bank_stmt_status_idx
  on public.bank_statement_lines (status);

alter table public.bank_accounts enable row level security;
alter table public.bank_statement_lines enable row level security;

drop policy if exists bank_accounts_auth on public.bank_accounts;
create policy bank_accounts_auth on public.bank_accounts
  for all to authenticated
  using (public.gl_can_access_toko(toko_id))
  with check (public.gl_can_access_toko(toko_id));

drop policy if exists bank_stmt_auth on public.bank_statement_lines;
create policy bank_stmt_auth on public.bank_statement_lines
  for all to authenticated
  using (
    exists (
      select 1 from public.bank_accounts ba
      where ba.id = bank_account_id
        and public.gl_can_access_toko(ba.toko_id)
    )
  )
  with check (
    exists (
      select 1 from public.bank_accounts ba
      where ba.id = bank_account_id
        and public.gl_can_access_toko(ba.toko_id)
    )
  );

create or replace function public.gl_match_bank_line(
  p_line_id uuid,
  p_journal_entry_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text;
begin
  select ba.toko_id into v_toko
  from public.bank_statement_lines bl
  join public.bank_accounts ba on ba.id = bl.bank_account_id
  where bl.id = p_line_id;

  if v_toko is null then
    raise exception 'Baris mutasi tidak ditemukan';
  end if;
  if not public.gl_can_access_toko(v_toko) then
    raise exception 'Tidak berhak';
  end if;

  update public.bank_statement_lines
  set matched_journal_entry_id = p_journal_entry_id,
      status = 'MATCHED'
  where id = p_line_id;
end;
$$;

-- =============================================================================
-- 7. Budgets vs actual
-- =============================================================================
create table if not exists public.gl_budgets (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id),
  tahun int not null,
  bulan int not null check (bulan between 1 and 12),
  akun_kode text not null references public.chart_of_accounts (kode),
  anggaran bigint not null default 0 check (anggaran >= 0),
  created_at timestamptz not null default now(),
  unique (toko_id, tahun, bulan, akun_kode)
);

create index if not exists gl_budgets_period_idx
  on public.gl_budgets (tahun, bulan, toko_id);

alter table public.gl_budgets enable row level security;
drop policy if exists gl_budgets_auth on public.gl_budgets;
create policy gl_budgets_auth on public.gl_budgets
  for all to authenticated
  using (public.gl_can_access_toko(toko_id))
  with check (public.gl_can_access_toko(toko_id));

create or replace function public.gl_budget_vs_actual(
  p_tahun int,
  p_bulan int,
  p_toko_id text default null
)
returns table (
  akun_kode text,
  akun_nama text,
  anggaran bigint,
  aktual bigint,
  selisih bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
  v_start date := make_date(p_tahun, p_bulan, 1);
  v_end date := (make_date(p_tahun, p_bulan, 1) + interval '1 month - 1 day')::date;
begin
  if v_toko is not null and not public.gl_can_access_toko(v_toko) then
    raise exception 'Tidak berhak';
  end if;
  if v_toko is null and not public.gl_is_owner_or_pusat() then
    v_toko := public.gl_current_toko();
  end if;

  return query
  with actual as (
    select jl.akun_kode,
           sum(jl.debit - jl.kredit)::bigint as net
    from public.journal_entries je
    join public.journal_lines jl on jl.entry_id = je.id
    where je.status = 'POSTED'
      and je.tanggal between v_start and v_end
      and (v_toko is null or je.toko_id = v_toko)
    group by jl.akun_kode
  )
  select
    b.akun_kode,
    c.nama,
    b.anggaran,
    coalesce(a.net, 0),
    b.anggaran - coalesce(a.net, 0)
  from public.gl_budgets b
  join public.chart_of_accounts c on c.kode = b.akun_kode
  left join actual a on a.akun_kode = b.akun_kode
  where b.tahun = p_tahun
    and b.bulan = p_bulan
    and (v_toko is null or b.toko_id = v_toko)
  order by b.akun_kode;
end;
$$;

-- =============================================================================
-- 8. e-Faktur drafts (export-ready; DJP upload tetap manual / API terpisah)
-- =============================================================================
create table if not exists public.e_faktur_drafts (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id),
  sale_id uuid,
  no_invoice text,
  tanggal date not null,
  dpp bigint not null default 0,
  ppn bigint not null default 0,
  nama_pembeli text,
  status text not null default 'DRAFT'
    check (status in ('DRAFT', 'READY', 'EXPORTED', 'REPORTED')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists e_faktur_toko_tgl_idx
  on public.e_faktur_drafts (toko_id, tanggal desc);
create unique index if not exists e_faktur_invoice_uidx
  on public.e_faktur_drafts (toko_id, no_invoice)
  where no_invoice is not null;

alter table public.e_faktur_drafts enable row level security;
drop policy if exists e_faktur_auth on public.e_faktur_drafts;
create policy e_faktur_auth on public.e_faktur_drafts
  for all to authenticated
  using (public.gl_can_access_toko(toko_id))
  with check (public.gl_can_access_toko(toko_id));

create or replace function public.gl_build_efaktur_from_sales(
  p_tahun int,
  p_bulan int,
  p_toko_id text default null,
  p_limit int default 300
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
  v_start date := make_date(p_tahun, p_bulan, 1);
  v_end date := (make_date(p_tahun, p_bulan, 1) + interval '1 month - 1 day')::date;
  r record;
  v_created int := 0;
  v_skipped int := 0;
  v_dpp bigint;
  v_ppn bigint;
begin
  if not public.gl_is_owner_or_pusat() and (v_toko is null or not public.gl_can_access_toko(v_toko)) then
    raise exception 'Tidak berhak';
  end if;
  if v_toko is null and not public.gl_is_owner_or_pusat() then
    v_toko := public.gl_current_toko();
  end if;

  for r in
    select s.*
    from public.sales s
    where (s.created_at at time zone 'Asia/Jakarta')::date between v_start and v_end
      and coalesce(s.total_harga, 0) > 0
      and (v_toko is null or upper(s.toko_id) = v_toko)
      and not exists (
        select 1 from public.e_faktur_drafts d
        where d.toko_id = s.toko_id and d.no_invoice = s.no_invoice
      )
    order by s.created_at
    limit greatest(1, least(coalesce(p_limit, 300), 2000))
  loop
    v_dpp := round(coalesce(r.total_harga, 0) / 1.11)::bigint;
    v_ppn := coalesce(r.total_harga, 0) - v_dpp;
    insert into public.e_faktur_drafts (
      toko_id, sale_id, no_invoice, tanggal, dpp, ppn, nama_pembeli, status, payload
    ) values (
      upper(r.toko_id),
      r.id,
      r.no_invoice,
      (r.created_at at time zone 'Asia/Jakarta')::date,
      v_dpp,
      v_ppn,
      r.nama_pelanggan,
      'READY',
      jsonb_build_object(
        'no_invoice', r.no_invoice,
        'tanggal', (r.created_at at time zone 'Asia/Jakarta')::date,
        'dpp', v_dpp,
        'ppn', v_ppn,
        'nama_pembeli', r.nama_pelanggan,
        'npwp_pembeli', '',
        'keterangan', 'Optik B. Riski — draft e-Faktur'
      )
    );
    v_created := v_created + 1;
  end loop;

  return jsonb_build_object('created', v_created, 'skipped', v_skipped);
end;
$$;

-- Grants
grant execute on function public.gl_current_role() to authenticated;
grant execute on function public.gl_current_toko() to authenticated;
grant execute on function public.gl_is_owner_or_pusat() to authenticated;
grant execute on function public.gl_can_access_toko(text) to authenticated;
grant execute on function public.gl_trial_balance(int, int, text) to authenticated;
grant execute on function public.gl_consolidate_by_toko(int, int) to authenticated;
grant execute on function public.gl_aging_piutang(text, int) to authenticated;
grant execute on function public.gl_aging_hutang(text, int) to authenticated;
grant execute on function public.gl_backfill_sales_batch(text, int, text) to authenticated;
grant execute on function public.gl_backfill_finance_batch(text, int, text) to authenticated;
grant execute on function public.gl_match_bank_line(uuid, uuid) to authenticated;
grant execute on function public.gl_budget_vs_actual(int, int, text) to authenticated;
grant execute on function public.gl_build_efaktur_from_sales(int, int, text, int) to authenticated;
grant execute on function public.close_fiscal_period(int, int, text) to authenticated;
grant execute on function public.reopen_fiscal_period(int, int) to authenticated;
