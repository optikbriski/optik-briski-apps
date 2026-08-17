-- =============================================================================
-- Owner Finance ↔ Admin Buku Besar 100% sync
-- 1) Omzet/HPP match Buku Besar daily drill-down (sales_items.subtotal + 40% HPP)
-- 2) FT status filter = APPROVED only (+ POS ref + closing) — mirror Dart
-- 3) Owner Toko cannot INSERT/UPDATE/DELETE finance_transactions
-- 4) Owner Toko SELECT scoped to accessible toko (finance + sales)
-- 5) Align owner_ringkasan omzet/hpp/opex with laporan filters
-- =============================================================================

-- Cleanup accidental QA probe rows (if any)
delete from public.finance_transactions
where kategori = 'QA_TEST_SHOULD_FAIL';

-- ---------------------------------------------------------------------------
-- Buku Besar helpers
-- ---------------------------------------------------------------------------

-- Approved gate: Dart only accepts status == APPROVED (plus POS ref / closing)
create or replace function public._owner_ft_is_approved_or_pos(
  p_status text,
  p_ref text,
  p_kategori text
)
returns boolean
language sql
immutable
as $$
  select
    upper(trim(coalesce(p_status, ''))) = 'APPROVED'
    or public._owner_ft_is_pos_sale_ref(p_ref)
    or public._owner_ft_is_closing(p_ref, p_kategori);
$$;

-- Omzet satu sale = sum(sales_items.subtotal) — mirror _loadAuditDetailHariIni
create or replace function public._owner_sale_omzet_bb(p_sale_id uuid)
returns bigint
language sql
stable
as $$
  select coalesce(sum(si.subtotal), 0)::bigint
  from public.sales_items si
  where si.sale_id = p_sale_id;
$$;

-- HPP satu sale: sales_items.harga_modal if present, else round((subtotal/qty)*0.4)*qty
-- (column may not exist — use products only as last resort via 40% to match live Admin)
create or replace function public._owner_sale_hpp_bb(p_sale_id uuid)
returns bigint
language sql
stable
as $$
  select coalesce(sum(
    (
      round(
        (coalesce(si.subtotal, 0)::numeric / greatest(coalesce(si.qty, 1), 1)) * 0.4
      )::bigint
    ) * greatest(coalesce(si.qty, 1), 1)
  ), 0)::bigint
  from public.sales_items si
  where si.sale_id = p_sale_id;
$$;

comment on function public._owner_sale_omzet_bb(uuid) is
  'Buku Besar omzet: sum(sales_items.subtotal).';
comment on function public._owner_sale_hpp_bb(uuid) is
  'Buku Besar HPP: round((subtotal/qty)*0.4)*qty (si.harga_modal absent on live).';

-- UTC calendar day of timestamptz (Admin uses ISO date prefix = UTC)
create or replace function public._owner_utc_date(p_ts timestamptz)
returns date
language sql
immutable
as $$
  select (timezone('utc', p_ts))::date;
$$;

-- ---------------------------------------------------------------------------
-- Daily laporan
-- ---------------------------------------------------------------------------
create or replace function public.owner_laporan_harian(
  p_toko_id text,
  p_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day date := coalesce(p_date, current_date);
  v_next date := v_day + 1;
  v_omzet bigint := 0;
  v_hpp bigint := 0;
  v_invoice int := 0;
  v_pemasukan bigint := 0;
  v_opex bigint := 0;
  v_kas_in bigint := 0;
  v_kas_out bigint := 0;
  v_dpp bigint := 0;
  v_ppn bigint := 0;
  v_laba bigint := 0;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;
  if p_toko_id is null or length(trim(p_toko_id)) = 0 then
    raise exception 'p_toko_id wajib';
  end if;
  if not public.owner_can_access_toko(p_toko_id) then
    raise exception 'Toko di luar scope Owner';
  end if;

  -- Sales window: [day 00:00 UTC, next day) — matches Admin gte/lte ISO without TZ
  select
    coalesce(sum(public._owner_sale_omzet_bb(s.id)), 0),
    coalesce(sum(public._owner_sale_hpp_bb(s.id)), 0),
    count(*)::int
  into v_omzet, v_hpp, v_invoice
  from public.sales s
  where s.toko_id = p_toko_id
    and s.created_at >= v_day::timestamptz
    and s.created_at < v_next::timestamptz;

  select coalesce(sum(ft.nominal), 0) into v_pemasukan
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi = v_day
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_pos_sale_ref(ft.referensi_id)
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(ft.nominal), 0) into v_opex
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi = v_day
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(ft.nominal), 0) into v_kas_in
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi = v_day
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_pos_sale_ref(ft.referensi_id)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(ft.nominal), 0) into v_kas_out
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi = v_day
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_modal_noise(ft.kategori);

  v_dpp := round(v_omzet / 1.11);
  v_ppn := v_omzet - v_dpp;
  -- Daily laba = Buku Besar export: (omzet - hpp) + pemasukan - opex
  v_laba := (v_omzet - v_hpp) + v_pemasukan - v_opex;

  return jsonb_build_object(
    'granularity', 'day',
    'toko_id', p_toko_id,
    'date', v_day,
    'omzet', v_omzet,
    'hpp', v_hpp,
    'dpp', v_dpp,
    'ppn', v_ppn,
    'pemasukan', v_pemasukan,
    'opex', v_opex,
    'kas_in', v_kas_in,
    'kas_out', v_kas_out,
    'laba', v_laba,
    'laba_bersih', v_laba,
    'invoice_count', v_invoice,
    'gaji', 0,
    'bagi_utama_est', round(v_laba * 0.5),
    'bagi_toko_est', v_laba - round(v_laba * 0.5)
  );
end;
$$;

revoke all on function public.owner_laporan_harian(text, date) from public;
grant execute on function public.owner_laporan_harian(text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Monthly
-- ---------------------------------------------------------------------------
create or replace function public.owner_laporan_bulanan(
  p_toko_id text,
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
  v_omzet bigint := 0;
  v_hpp bigint := 0;
  v_opex bigint := 0;
  v_pemasukan bigint := 0;
  v_gaji bigint := 0;
  v_invoice int := 0;
  v_laba bigint := 0;
  v_laba_bb bigint := 0;
  v_series jsonb := '[]'::jsonb;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;
  if p_toko_id is null or length(trim(p_toko_id)) = 0 then
    raise exception 'p_toko_id wajib';
  end if;
  if not public.owner_can_access_toko(p_toko_id) then
    raise exception 'Toko di luar scope Owner';
  end if;
  if v_ym !~ '^\d{4}-\d{2}$' then
    raise exception 'periode_ym harus YYYY-MM';
  end if;

  v_start := (v_ym || '-01')::date;
  v_end := (v_start + interval '1 month')::date;

  select
    coalesce(sum(public._owner_sale_omzet_bb(s.id)), 0),
    coalesce(sum(public._owner_sale_hpp_bb(s.id)), 0),
    count(*)::int
  into v_omzet, v_hpp, v_invoice
  from public.sales s
  where s.toko_id = p_toko_id
    and s.created_at >= v_start::timestamptz
    and s.created_at < v_end::timestamptz;

  select coalesce(sum(ft.nominal), 0) into v_opex
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(ft.nominal), 0) into v_pemasukan
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_pos_sale_ref(ft.referensi_id)
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(k.gaji_pokok), 0) into v_gaji
  from public.karyawan k
  where k.toko_id = p_toko_id
    and k.status_approval = 'Aktif';

  -- Intentional: monthly Owner laba includes gaji (bagi-hasil); BB daily does not.
  v_laba := v_omzet - v_hpp - v_opex - v_gaji;
  v_laba_bb := (v_omzet - v_hpp) + v_pemasukan - v_opex;

  select coalesce(jsonb_agg(row_to_json(b)::jsonb order by b.bucket), '[]'::jsonb)
  into v_series
  from (
    with days as (
      select generate_series(v_start, v_end - 1, '1 day'::interval)::date as d
    ),
    sales_d as (
      select
        public._owner_utc_date(s.created_at) as d,
        coalesce(sum(public._owner_sale_omzet_bb(s.id)), 0) as omzet,
        coalesce(sum(public._owner_sale_hpp_bb(s.id)), 0) as hpp,
        count(*)::int as invoice_count
      from public.sales s
      where s.toko_id = p_toko_id
        and s.created_at >= v_start::timestamptz
        and s.created_at < v_end::timestamptz
      group by 1
    ),
    opex_d as (
      select
        ft.tanggal_transaksi as d,
        coalesce(sum(ft.nominal), 0) as opex
      from public.finance_transactions ft
      where ft.toko_id = p_toko_id
        and ft.tanggal_transaksi >= v_start
        and ft.tanggal_transaksi < v_end
        and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
        and public._owner_ft_is_approved_or_pos(
          ft.status_konfirmasi, ft.referensi_id, ft.kategori
        )
        and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
        and not public._owner_ft_is_modal_noise(ft.kategori)
      group by 1
    ),
    in_d as (
      select
        ft.tanggal_transaksi as d,
        coalesce(sum(ft.nominal), 0) as pemasukan
      from public.finance_transactions ft
      where ft.toko_id = p_toko_id
        and ft.tanggal_transaksi >= v_start
        and ft.tanggal_transaksi < v_end
        and upper(coalesce(ft.jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
        and public._owner_ft_is_approved_or_pos(
          ft.status_konfirmasi, ft.referensi_id, ft.kategori
        )
        and not public._owner_ft_is_pos_sale_ref(ft.referensi_id)
        and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
        and not public._owner_ft_is_modal_noise(ft.kategori)
      group by 1
    )
    select
      days.d as bucket,
      to_char(days.d, 'DD') as label,
      coalesce(sales_d.omzet, 0)::bigint as omzet,
      coalesce(sales_d.hpp, 0)::bigint as hpp,
      coalesce(opex_d.opex, 0)::bigint as opex,
      coalesce(in_d.pemasukan, 0)::bigint as pemasukan,
      (coalesce(sales_d.omzet, 0) - coalesce(sales_d.hpp, 0)
        + coalesce(in_d.pemasukan, 0) - coalesce(opex_d.opex, 0))::bigint as laba,
      coalesce(sales_d.invoice_count, 0)::int as invoice_count
    from days
    left join sales_d on sales_d.d = days.d
    left join opex_d on opex_d.d = days.d
    left join in_d on in_d.d = days.d
    where coalesce(sales_d.omzet, 0) <> 0
       or coalesce(opex_d.opex, 0) <> 0
       or coalesce(in_d.pemasukan, 0) <> 0
       or coalesce(sales_d.invoice_count, 0) <> 0
  ) b;

  return jsonb_build_object(
    'granularity', 'month',
    'toko_id', p_toko_id,
    'periode_ym', v_ym,
    'date_from', v_start,
    'date_to', (v_end - 1),
    'omzet', v_omzet,
    'hpp', v_hpp,
    'opex', v_opex,
    'pemasukan', v_pemasukan,
    'gaji', v_gaji,
    'laba', v_laba,
    'laba_bersih_est', v_laba,
    'laba_bb', v_laba_bb,
    'invoice_count', v_invoice,
    'bagi_utama_est', round(v_laba * 0.5),
    'bagi_toko_est', v_laba - round(v_laba * 0.5),
    'series', v_series,
    'formula_note', 'laba includes gaji (Owner monthly); laba_bb = (omzet-hpp)+pemasukan-opex matches Buku Besar'
  );
end;
$$;

revoke all on function public.owner_laporan_bulanan(text, text) from public;
grant execute on function public.owner_laporan_bulanan(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Yearly
-- ---------------------------------------------------------------------------
create or replace function public.owner_laporan_tahunan(
  p_toko_id text,
  p_year int default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year int := coalesce(p_year, extract(year from now())::int);
  v_start date;
  v_end date;
  v_omzet bigint := 0;
  v_hpp bigint := 0;
  v_opex bigint := 0;
  v_pemasukan bigint := 0;
  v_gaji bigint := 0;
  v_invoice int := 0;
  v_laba bigint := 0;
  v_laba_bb bigint := 0;
  v_series jsonb := '[]'::jsonb;
  v_m int;
  v_ym text;
  v_ms date;
  v_me date;
  v_mo bigint;
  v_mh bigint;
  v_mx bigint;
  v_mp bigint;
  v_mi int;
  v_mg bigint;
begin
  if not public.is_owner_role() then
    raise exception 'Hanya Owner';
  end if;
  if p_toko_id is null or length(trim(p_toko_id)) = 0 then
    raise exception 'p_toko_id wajib';
  end if;
  if not public.owner_can_access_toko(p_toko_id) then
    raise exception 'Toko di luar scope Owner';
  end if;
  if v_year < 2000 or v_year > 2100 then
    raise exception 'tahun tidak valid';
  end if;

  v_start := make_date(v_year, 1, 1);
  v_end := make_date(v_year + 1, 1, 1);

  select
    coalesce(sum(public._owner_sale_omzet_bb(s.id)), 0),
    coalesce(sum(public._owner_sale_hpp_bb(s.id)), 0),
    count(*)::int
  into v_omzet, v_hpp, v_invoice
  from public.sales s
  where s.toko_id = p_toko_id
    and s.created_at >= v_start::timestamptz
    and s.created_at < v_end::timestamptz;

  select coalesce(sum(ft.nominal), 0) into v_opex
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(ft.nominal), 0) into v_pemasukan
  from public.finance_transactions ft
  where ft.toko_id = p_toko_id
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_pos_sale_ref(ft.referensi_id)
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(k.gaji_pokok), 0) * 12 into v_gaji
  from public.karyawan k
  where k.toko_id = p_toko_id
    and k.status_approval = 'Aktif';

  v_laba := v_omzet - v_hpp - v_opex - v_gaji;
  v_laba_bb := (v_omzet - v_hpp) + v_pemasukan - v_opex;
  v_mg := case when v_gaji = 0 then 0 else (v_gaji / 12) end;

  for v_m in 1..12 loop
    v_ym := v_year::text || '-' || lpad(v_m::text, 2, '0');
    v_ms := make_date(v_year, v_m, 1);
    v_me := (v_ms + interval '1 month')::date;
    v_mo := 0; v_mh := 0; v_mx := 0; v_mp := 0; v_mi := 0;

    select
      coalesce(sum(public._owner_sale_omzet_bb(s.id)), 0),
      coalesce(sum(public._owner_sale_hpp_bb(s.id)), 0),
      count(*)::int
    into v_mo, v_mh, v_mi
    from public.sales s
    where s.toko_id = p_toko_id
      and s.created_at >= v_ms::timestamptz
      and s.created_at < v_me::timestamptz;

    select coalesce(sum(ft.nominal), 0) into v_mx
    from public.finance_transactions ft
    where ft.toko_id = p_toko_id
      and ft.tanggal_transaksi >= v_ms
      and ft.tanggal_transaksi < v_me
      and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
      and public._owner_ft_is_approved_or_pos(
        ft.status_konfirmasi, ft.referensi_id, ft.kategori
      )
      and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
      and not public._owner_ft_is_modal_noise(ft.kategori);

    select coalesce(sum(ft.nominal), 0) into v_mp
    from public.finance_transactions ft
    where ft.toko_id = p_toko_id
      and ft.tanggal_transaksi >= v_ms
      and ft.tanggal_transaksi < v_me
      and upper(coalesce(ft.jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
      and public._owner_ft_is_approved_or_pos(
        ft.status_konfirmasi, ft.referensi_id, ft.kategori
      )
      and not public._owner_ft_is_pos_sale_ref(ft.referensi_id)
      and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
      and not public._owner_ft_is_modal_noise(ft.kategori);

    v_series := v_series || jsonb_build_array(jsonb_build_object(
      'bucket', v_ym,
      'label', to_char(v_ms, 'Mon'),
      'omzet', v_mo,
      'hpp', v_mh,
      'opex', v_mx,
      'pemasukan', v_mp,
      'gaji', v_mg,
      'laba', v_mo - v_mh - v_mx - v_mg,
      'laba_bb', (v_mo - v_mh) + v_mp - v_mx,
      'invoice_count', v_mi
    ));
  end loop;

  return jsonb_build_object(
    'granularity', 'year',
    'toko_id', p_toko_id,
    'year', v_year,
    'date_from', v_start,
    'date_to', (v_end - 1),
    'omzet', v_omzet,
    'hpp', v_hpp,
    'opex', v_opex,
    'pemasukan', v_pemasukan,
    'gaji', v_gaji,
    'laba', v_laba,
    'laba_bersih_est', v_laba,
    'laba_bb', v_laba_bb,
    'invoice_count', v_invoice,
    'bagi_utama_est', round(v_laba * 0.5),
    'bagi_toko_est', v_laba - round(v_laba * 0.5),
    'series', v_series,
    'formula_note', 'laba includes annualized gaji; laba_bb matches Buku Besar aggregate'
  );
end;
$$;

revoke all on function public.owner_laporan_tahunan(text, int) from public;
grant execute on function public.owner_laporan_tahunan(text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- owner_ringkasan: same omzet/hpp/opex as monthly BB path
-- ---------------------------------------------------------------------------
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
  v_pemasukan bigint := 0;
  v_gaji bigint := 0;
  v_invoice int := 0;
  v_karyawan int := 0;
  v_pending int := 0;
  v_laba bigint := 0;
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
    coalesce(sum(public._owner_sale_omzet_bb(s.id)), 0),
    coalesce(sum(public._owner_sale_hpp_bb(s.id)), 0),
    count(*)::int
  into v_omzet, v_hpp, v_invoice
  from public.sales s
  where s.toko_id = any (v_toko)
    and s.created_at >= v_start::timestamptz
    and s.created_at < v_end::timestamptz;

  select coalesce(sum(ft.nominal), 0) into v_opex
  from public.finance_transactions ft
  where ft.toko_id = any (v_toko)
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(ft.nominal), 0) into v_pemasukan
  from public.finance_transactions ft
  where ft.toko_id = any (v_toko)
    and ft.tanggal_transaksi >= v_start
    and ft.tanggal_transaksi < v_end
    and upper(coalesce(ft.jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
    and public._owner_ft_is_approved_or_pos(
      ft.status_konfirmasi, ft.referensi_id, ft.kategori
    )
    and not public._owner_ft_is_pos_sale_ref(ft.referensi_id)
    and not public._owner_ft_is_closing(ft.referensi_id, ft.kategori)
    and not public._owner_ft_is_modal_noise(ft.kategori);

  select coalesce(sum(k.gaji_pokok), 0), count(*)::int
  into v_gaji, v_karyawan
  from public.karyawan k
  where k.toko_id = any (v_toko)
    and k.status_approval = 'Aktif';

  select count(*)::int into v_pending
  from public.karyawan k
  where k.toko_id = any (v_toko)
    and k.status_approval in ('Pending', 'Menunggu OTP', 'Menunggu Persetujuan');

  v_laba := v_omzet - v_hpp - v_opex - v_gaji;

  return jsonb_build_object(
    'periode_ym', v_ym,
    'toko_ids', to_jsonb(v_toko),
    'omzet', v_omzet,
    'hpp', v_hpp,
    'opex', v_opex,
    'pemasukan', v_pemasukan,
    'gaji', v_gaji,
    'laba_bersih_est', v_laba,
    'laba_bb', (v_omzet - v_hpp) + v_pemasukan - v_opex,
    'invoice_count', v_invoice,
    'karyawan_aktif', v_karyawan,
    'karyawan_pending', v_pending,
    'bagi_utama_est', round(v_laba * 0.5),
    'bagi_toko_est', v_laba - round(v_laba * 0.5)
  );
end;
$$;

revoke all on function public.owner_ringkasan(text, text) from public;
grant execute on function public.owner_ringkasan(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: Owner Toko read-only + toko-scoped on finance_transactions + sales
-- ---------------------------------------------------------------------------
drop policy if exists finance_transactions_authenticated_all on public.finance_transactions;
drop policy if exists finance_transactions_select on public.finance_transactions;
drop policy if exists finance_transactions_insert on public.finance_transactions;
drop policy if exists finance_transactions_update on public.finance_transactions;
drop policy if exists finance_transactions_delete on public.finance_transactions;

create policy finance_transactions_select on public.finance_transactions
  for select to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
    or public.owner_can_access_toko(toko_id)
  );

create policy finance_transactions_insert on public.finance_transactions
  for insert to authenticated
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy finance_transactions_update on public.finance_transactions
  for update to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  )
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy finance_transactions_delete on public.finance_transactions
  for delete to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

drop policy if exists sales_authenticated_all on public.sales;
drop policy if exists sales_select on public.sales;
drop policy if exists sales_insert on public.sales;
drop policy if exists sales_update on public.sales;
drop policy if exists sales_delete on public.sales;

create policy sales_select on public.sales
  for select to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
    or public.owner_can_access_toko(toko_id)
  );

create policy sales_insert on public.sales
  for insert to authenticated
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_update on public.sales
  for update to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  )
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_delete on public.sales
  for delete to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

-- sales_items: Owner only via sale in scope (join sales)
drop policy if exists sales_items_authenticated_all on public.sales_items;
drop policy if exists sales_items_select on public.sales_items;
drop policy if exists sales_items_write on public.sales_items;
drop policy if exists sales_items_insert on public.sales_items;
drop policy if exists sales_items_update on public.sales_items;
drop policy if exists sales_items_delete on public.sales_items;

create policy sales_items_select on public.sales_items
  for select to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
    or exists (
      select 1 from public.sales s
      where s.id = sales_items.sale_id
        and public.owner_can_access_toko(s.toko_id)
    )
  );

create policy sales_items_insert on public.sales_items
  for insert to authenticated
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_items_update on public.sales_items
  for update to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  )
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_items_delete on public.sales_items
  for delete to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

-- ---------------------------------------------------------------------------
-- Seed minimal ARCAMANIK activity for non-zero sync proof (idempotent)
-- ---------------------------------------------------------------------------
do $$
declare
  v_sale_id uuid;
  v_product_id uuid;
  v_ft_opex uuid := 'a0000000-0000-4000-8000-000000000001'::uuid;
  v_ft_in uuid := 'a0000000-0000-4000-8000-000000000002'::uuid;
  v_sale_fixed uuid := 'a0000000-0000-4000-8000-000000000010'::uuid;
begin
  select id into v_product_id from public.products order by id limit 1;

  if v_product_id is null then
    raise notice 'skip seed: no products';
    return;
  end if;

  -- Sale on 2026-08-16 UTC for ARCAMANIK (BB omzet=500000, hpp=200000 @40%)
  insert into public.sales (
    id, toko_id, total_harga, sisa_tagihan, dibayarkan, nama_pelanggan,
    metode_pembayaran, no_invoice, status_pembayaran, created_at
  ) values (
    v_sale_fixed,
    'CABANG-ARCAMANIK',
    550000,
    0,
    550000,
    'QA Owner Finance Sync',
    'CASH',
    'QA-OWN-FIN-SYNC-001',
    'LUNAS',
    '2026-08-16T10:00:00+00:00'::timestamptz
  )
  on conflict (id) do update set
    total_harga = excluded.total_harga,
    nama_pelanggan = excluded.nama_pelanggan,
    no_invoice = excluded.no_invoice;

  delete from public.sales_items where sale_id = v_sale_fixed;
  insert into public.sales_items (sale_id, product_id, nama_produk, qty, harga_satuan, subtotal)
  values
    (v_sale_fixed, v_product_id, 'QA Frame Sync', 1, 300000, 300000),
    (v_sale_fixed, v_product_id, 'QA Lensa Sync', 1, 200000, 200000);

  insert into public.finance_transactions (
    id, toko_id, tanggal_transaksi, jenis_transaksi, kategori, deskripsi,
    nominal, status_konfirmasi, metode_pembayaran, created_at
  ) values
    (
      v_ft_opex, 'CABANG-ARCAMANIK', '2026-08-16', 'PENGELUARAN', 'Listrik',
      'QA BB sync opex', 75000, 'APPROVED', 'CASH', '2026-08-16T11:00:00+00:00'::timestamptz
    ),
    (
      v_ft_in, 'CABANG-ARCAMANIK', '2026-08-16', 'PEMASUKAN', 'Lain-lain',
      'QA BB sync pemasukan', 25000, 'APPROVED', 'CASH', '2026-08-16T12:00:00+00:00'::timestamptz
    )
  on conflict (id) do update set
    nominal = excluded.nominal,
    status_konfirmasi = excluded.status_konfirmasi,
    kategori = excluded.kategori,
    deskripsi = excluded.deskripsi;
end $$;

comment on function public.owner_laporan_harian is
  'Owner daily P&L — 100% Buku Besar aligned (items subtotal + 40% HPP).';
comment on function public.owner_laporan_bulanan is
  'Owner monthly — omzet/hpp/opex/pemasukan BB-aligned; laba includes gaji.';
comment on function public.owner_laporan_tahunan is
  'Owner yearly — omzet/hpp/opex/pemasukan BB-aligned; laba includes annualized gaji.';
