-- =============================================================================
-- Owner Finance + Laporan (read-only tracking)
-- Mirrors Admin Buku Besar P&L read path for owned toko.
-- No write RPCs on finance_transactions for Owner Toko (approve stays separate).
-- =============================================================================

-- Helpers: Buku Besar-aligned finance row filters (SQL equivalents)
create or replace function public._owner_ft_is_pos_sale_ref(p_ref text)
returns boolean
language sql
immutable
as $$
  select case
    when nullif(trim(coalesce(p_ref, '')), '') is null then false
    when upper(trim(p_ref)) ~ '^(CLOSE-|SETTLE-|FT-|VOID-)' then false
    else true
  end;
$$;

create or replace function public._owner_ft_is_closing(p_ref text, p_kategori text)
returns boolean
language sql
immutable
as $$
  select
    upper(trim(coalesce(p_ref, ''))) like 'CLOSE-%'
    or upper(coalesce(p_kategori, '')) like '%PENUTUPAN%'
    or upper(coalesce(p_kategori, '')) like '%CLOSING%';
$$;

create or replace function public._owner_ft_is_modal_noise(p_kategori text)
returns boolean
language sql
immutable
as $$
  select case
    when upper(coalesce(p_kategori, '')) ~ '(MODAL|KEMBALIAN|SALDO AWAL)' then true
    when upper(coalesce(p_kategori, '')) ~ '(PENUTUPAN|CLOSING)' then false
    when upper(coalesce(p_kategori, '')) like '%KASIR%' then false
    when upper(coalesce(p_kategori, '')) ~ '(^|[^A-Z])KAS([^A-Z]|$)' then true
    else false
  end;
$$;

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
    upper(trim(coalesce(p_status, ''))) in ('APPROVED', 'OK', 'CONFIRMED', 'DISETUJUI')
    or public._owner_ft_is_pos_sale_ref(p_ref)
    or public._owner_ft_is_closing(p_ref, p_kategori);
$$;

-- ---------------------------------------------------------------------------
-- Daily laporan (Buku Besar stage3 read path)
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
  where s.toko_id = p_toko_id
    and s.created_at >= v_day::timestamptz
    and s.created_at < v_next::timestamptz
    and coalesce(s.nama_pelanggan, '') not ilike '%Modal Awal%';

  -- Pemasukan non-produk untuk P&L (exclude POS auto-ref & closing & modal noise)
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

  -- OPEX / hutang for P&L (exclude closing & modal noise)
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

  -- Kas masuk jurnal (bukan omzet POS)
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
-- Monthly laporan (deepen owner_ringkasan + day series)
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

  -- Monthly laba uses ringkasan convention: omzet - hpp - opex - gaji
  -- (pemasukan tracked separately for Buku Besar parity)
  v_laba := v_omzet - v_hpp - v_opex - v_gaji;

  -- Day series via set aggregation (only days with activity; fill empty omitted)
  select coalesce(jsonb_agg(row_to_json(b)::jsonb order by b.bucket), '[]'::jsonb)
  into v_series
  from (
    with days as (
      select generate_series(v_start, v_end - 1, '1 day'::interval)::date as d
    ),
    sales_d as (
      select
        (s.created_at at time zone 'Asia/Jakarta')::date as d,
        coalesce(sum(s.total_harga), 0) as omzet,
        coalesce(sum(
          (select coalesce(sum(si.qty * coalesce(p.harga_modal, 0)), 0)
           from public.sales_items si
           left join public.products p on p.id = si.product_id
           where si.sale_id = s.id)
        ), 0) as hpp,
        count(*)::int as invoice_count
      from public.sales s
      where s.toko_id = p_toko_id
        and s.created_at >= v_start
        and s.created_at < v_end
        and coalesce(s.nama_pelanggan, '') not ilike '%Modal Awal%'
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
    'invoice_count', v_invoice,
    'bagi_utama_est', round(v_laba * 0.5),
    'bagi_toko_est', v_laba - round(v_laba * 0.5),
    'series', v_series
  );
end;
$$;

revoke all on function public.owner_laporan_bulanan(text, text) from public;
grant execute on function public.owner_laporan_bulanan(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Yearly laporan (month series)
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

  -- Gaji estimasi: gaji_pokok aktif × 12 (annualized estimate)
  select coalesce(sum(k.gaji_pokok), 0) * 12 into v_gaji
  from public.karyawan k
  where k.toko_id = p_toko_id
    and k.status_approval = 'Aktif';

  v_laba := v_omzet - v_hpp - v_opex - v_gaji;
  v_mg := case when v_gaji = 0 then 0 else (v_gaji / 12) end;

  for v_m in 1..12 loop
    v_ym := v_year::text || '-' || lpad(v_m::text, 2, '0');
    v_ms := make_date(v_year, v_m, 1);
    v_me := (v_ms + interval '1 month')::date;
    v_mo := 0; v_mh := 0; v_mx := 0; v_mp := 0; v_mi := 0;

    select
      coalesce(sum(s.total_harga), 0),
      coalesce(sum(
        (select coalesce(sum(si.qty * coalesce(p.harga_modal, 0)), 0)
         from public.sales_items si
         left join public.products p on p.id = si.product_id
         where si.sale_id = s.id)
      ), 0),
      count(*)::int
    into v_mo, v_mh, v_mi
    from public.sales s
    where s.toko_id = p_toko_id
      and s.created_at >= v_ms
      and s.created_at < v_me
      and coalesce(s.nama_pelanggan, '') not ilike '%Modal Awal%';

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
    'invoice_count', v_invoice,
    'bagi_utama_est', round(v_laba * 0.5),
    'bagi_toko_est', v_laba - round(v_laba * 0.5),
    'series', v_series
  );
end;
$$;

revoke all on function public.owner_laporan_tahunan(text, int) from public;
grant execute on function public.owner_laporan_tahunan(text, int) to authenticated;

-- Unified summary dispatcher
create or replace function public.owner_report_summary(
  p_toko_id text,
  p_granularity text,
  p_anchor date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_g text := lower(trim(coalesce(p_granularity, 'day')));
  v_a date := coalesce(p_anchor, current_date);
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

  if v_g in ('day', 'harian', 'daily') then
    return public.owner_laporan_harian(p_toko_id, v_a);
  elsif v_g in ('month', 'bulanan', 'monthly') then
    return public.owner_laporan_bulanan(p_toko_id, to_char(v_a, 'YYYY-MM'));
  elsif v_g in ('year', 'tahunan', 'yearly') then
    return public.owner_laporan_tahunan(p_toko_id, extract(year from v_a)::int);
  else
    raise exception 'granularity harus day|month|year';
  end if;
end;
$$;

revoke all on function public.owner_report_summary(text, text, date) from public;
grant execute on function public.owner_report_summary(text, text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Finance ledger (pending + approved) — SELECT only
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_finance_ledger(
  p_toko_id text default null,
  p_from date default null,
  p_to date default null,
  p_limit int default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text[];
  v_from date := coalesce(p_from, (current_date - interval '30 days')::date);
  v_to date := coalesce(p_to, current_date);
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
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

  select coalesce(jsonb_agg(to_jsonb(x) order by x.tanggal_transaksi desc, x.created_at desc), '[]'::jsonb)
  into v_rows
  from (
    select
      ft.id,
      ft.toko_id,
      ft.tanggal_transaksi,
      ft.jenis_transaksi,
      ft.kategori,
      ft.deskripsi,
      ft.nominal,
      ft.status_konfirmasi,
      ft.metode_pembayaran,
      ft.referensi_id,
      ft.nama_kasir,
      ft.created_at
    from public.finance_transactions ft
    where ft.toko_id = any (v_toko)
      and ft.tanggal_transaksi >= v_from
      and ft.tanggal_transaksi <= v_to
      and upper(coalesce(ft.status_konfirmasi, 'PENDING')) in (
        'PENDING', 'APPROVED', 'OK', 'CONFIRMED', 'DISETUJUI', 'MENUNGGU'
      )
    order by ft.tanggal_transaksi desc, ft.created_at desc
    limit v_limit
  ) x;

  return v_rows;
end;
$$;

-- Alias requested in original brief
create or replace function public.owner_list_finance_tx(
  p_toko_id text default null,
  p_from date default null,
  p_to date default null,
  p_limit int default 100
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.owner_list_finance_ledger(p_toko_id, p_from, p_to, p_limit);
$$;

revoke all on function public.owner_list_finance_ledger(text, date, date, int) from public;
grant execute on function public.owner_list_finance_ledger(text, date, date, int) to authenticated;
revoke all on function public.owner_list_finance_tx(text, date, date, int) from public;
grant execute on function public.owner_list_finance_tx(text, date, date, int) to authenticated;

-- Thin kas snapshot for range
create or replace function public.owner_finance_snapshot(
  p_toko_id text,
  p_from date default null,
  p_to date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_from date := coalesce(p_from, (current_date - interval '30 days')::date);
  v_to date := coalesce(p_to, current_date);
  v_in bigint := 0;
  v_out bigint := 0;
  v_pending int := 0;
  v_approved int := 0;
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

  select
    coalesce(sum(case
      when upper(coalesce(jenis_transaksi, '')) in ('PEMASUKAN', 'PIUTANG')
        and public._owner_ft_is_approved_or_pos(status_konfirmasi, referensi_id, kategori)
        and not public._owner_ft_is_pos_sale_ref(referensi_id)
        and not public._owner_ft_is_modal_noise(kategori)
      then nominal else 0 end), 0),
    coalesce(sum(case
      when upper(coalesce(jenis_transaksi, '')) in ('PENGELUARAN', 'HUTANG')
        and public._owner_ft_is_approved_or_pos(status_konfirmasi, referensi_id, kategori)
        and not public._owner_ft_is_modal_noise(kategori)
      then nominal else 0 end), 0),
    count(*) filter (
      where upper(coalesce(status_konfirmasi, 'PENDING')) in ('PENDING', 'MENUNGGU')
    )::int,
    count(*) filter (
      where upper(coalesce(status_konfirmasi, '')) in ('APPROVED', 'OK', 'CONFIRMED', 'DISETUJUI')
    )::int
  into v_in, v_out, v_pending, v_approved
  from public.finance_transactions
  where toko_id = p_toko_id
    and tanggal_transaksi >= v_from
    and tanggal_transaksi <= v_to;

  return jsonb_build_object(
    'toko_id', p_toko_id,
    'date_from', v_from,
    'date_to', v_to,
    'kas_in', v_in,
    'kas_out', v_out,
    'net', v_in - v_out,
    'pending_count', v_pending,
    'approved_count', v_approved
  );
end;
$$;

revoke all on function public.owner_finance_snapshot(text, date, date) from public;
grant execute on function public.owner_finance_snapshot(text, date, date) to authenticated;

comment on function public.owner_laporan_harian is
  'Owner read-only daily P&L (Buku Besar aligned).';
comment on function public.owner_laporan_bulanan is
  'Owner read-only monthly report + day series.';
comment on function public.owner_laporan_tahunan is
  'Owner read-only yearly report + month series.';
comment on function public.owner_list_finance_ledger is
  'Owner read-only finance_transactions ledger (pending+approved).';
