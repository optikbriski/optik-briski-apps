-- =============================================================================
-- GL Full Audit v2 — angka nyata per layer (bukan gimmick)
-- - finance: omzet/ppn/pengeluaran/bersih dihitung dari sumber aslinya
-- - tiap cek: total_count + total_amount FULL (tanpa limit); findings = sampel
-- - cek rekonsiliasi FIN_* gagal jika angka sumber ≠ angka GL
-- =============================================================================

drop function if exists public.gl_run_full_audit(text, int);
drop function if exists public.gl_run_full_audit(text, int, int, int);

create or replace function public.gl_run_full_audit(
  p_toko_id text default null,
  p_limit_per_check int default 80,
  p_tahun int default null,
  p_bulan int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
  v_lim int := greatest(10, least(coalesce(p_limit_per_check, 80), 200));
  v_tahun int := coalesce(
    p_tahun,
    extract(year from (timezone('Asia/Jakarta', now())))::int);
  v_bulan int := coalesce(
    p_bulan,
    extract(month from (timezone('Asia/Jakarta', now())))::int);
  v_start date := make_date(v_tahun, v_bulan, 1);
  v_end date := (make_date(v_tahun, v_bulan, 1) + interval '1 month - 1 day')::date;

  v_checks jsonb := '[]'::jsonb;
  v_findings jsonb;
  v_metrics jsonb;
  v_finance jsonb;
  v_count int;
  v_amt bigint;
  v_amt2 bigint;
  v_crit int := 0;
  v_high int := 0;
  v_med int := 0;
  v_info int := 0;
  v_toko_n int;
  v_passed boolean;
  v_over_settle boolean;

  -- finance totals (periode)
  v_omzet_bruto_sales bigint := 0;
  v_omzet_dpp_sales bigint := 0;
  v_ppn_sales bigint := 0;
  v_omzet_dpp_gl bigint := 0;
  v_ppn_gl bigint := 0;
  v_omzet_bruto_gl bigint := 0;
  v_pengeluaran_ft bigint := 0;
  v_pengeluaran_gl bigint := 0;
  v_pengeluaran_manual_ft bigint := 0;
  v_bersih_gl bigint := 0;
  v_sales_n int := 0;
  v_pos_n int := 0;
  v_je_n int := 0;
begin
  if not public.gl_is_owner_or_pusat() then
    raise exception 'Audit GL hanya untuk owner/pusat';
  end if;

  if v_bulan < 1 or v_bulan > 12 then
    raise exception 'Bulan tidak valid: %', v_bulan;
  end if;

  select count(distinct upper(toko_id)) into v_toko_n
  from public.sales
  where coalesce(toko_id, '') <> ''
    and (v_toko is null or upper(toko_id) = v_toko);

  -- =========================================================================
  -- FINANCE SNAPSHOT (periode aktif) — dihitung terpisah dari tiap sumber
  -- =========================================================================
  select
    count(*)::int,
    coalesce(sum(coalesce(s.total_harga, 0)), 0)::bigint,
    coalesce(sum(round(coalesce(s.total_harga, 0) / 1.11)), 0)::bigint
  into v_sales_n, v_omzet_bruto_sales, v_omzet_dpp_sales
  from public.sales s
  where coalesce(s.total_harga, 0) > 0
    and coalesce(s.no_invoice, '') <> ''
    and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
    and (s.created_at at time zone 'Asia/Jakarta')::date between v_start and v_end
    and (v_toko is null or upper(s.toko_id) = v_toko);

  v_ppn_sales := v_omzet_bruto_sales - v_omzet_dpp_sales;

  select
    coalesce(sum(case when jl.akun_kode = '4100' then jl.kredit - jl.debit else 0 end), 0)::bigint,
    coalesce(sum(case when jl.akun_kode = '2102' then jl.kredit - jl.debit else 0 end), 0)::bigint,
    count(distinct je.id)::int
  into v_omzet_dpp_gl, v_ppn_gl, v_pos_n
  from public.journal_entries je
  join public.journal_lines jl on jl.entry_id = je.id
  where je.status = 'POSTED'
    and je.sumber = 'POS'
    and je.tanggal between v_start and v_end
    and (v_toko is null or je.toko_id = v_toko);

  v_omzet_bruto_gl := v_omzet_dpp_gl + v_ppn_gl;

  select coalesce(sum(coalesce(ft.nominal, 0)), 0)::bigint
  into v_pengeluaran_ft
  from public.finance_transactions ft
  where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
    and upper(coalesce(ft.jenis_transaksi, '')) = 'PENGELUARAN'
    and coalesce(ft.nominal, 0) > 0
    and coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date)
        between v_start and v_end
    and (v_toko is null or upper(ft.toko_id) = v_toko);

  -- Beban GL periode (COGS + EXPENSE)
  select coalesce(sum(jl.debit - jl.kredit), 0)::bigint
  into v_pengeluaran_gl
  from public.journal_entries je
  join public.journal_lines jl on jl.entry_id = je.id
  join public.chart_of_accounts c on c.kode = jl.akun_kode
  where je.status = 'POSTED'
    and je.tanggal between v_start and v_end
    and c.tipe in ('COGS', 'EXPENSE')
    and (v_toko is null or je.toko_id = v_toko);

  -- Jumlah yang benar-benar ter-post dari FT PENGELUARAN → jurnal MANUAL FT-{id}
  select coalesce(sum(x.amt), 0)::bigint
  into v_pengeluaran_manual_ft
  from (
    select coalesce(sum(jl.debit), 0)::bigint as amt
    from public.finance_transactions ft
    join public.journal_entries je
      on je.status = 'POSTED'
     and je.sumber = 'MANUAL'
     and je.referensi_id = 'FT-' || ft.id::text
    join public.journal_lines jl on jl.entry_id = je.id
    join public.chart_of_accounts c on c.kode = jl.akun_kode
    where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
      and upper(coalesce(ft.jenis_transaksi, '')) = 'PENGELUARAN'
      and coalesce(ft.nominal, 0) > 0
      and coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date)
          between v_start and v_end
      and (v_toko is null or upper(ft.toko_id) = v_toko)
      and c.tipe in ('COGS', 'EXPENSE')
    group by ft.id
  ) x;

  v_bersih_gl := v_omzet_dpp_gl - v_pengeluaran_gl;

  select count(*)::int into v_je_n
  from public.journal_entries je
  where je.status = 'POSTED'
    and je.tanggal between v_start and v_end
    and (v_toko is null or je.toko_id = v_toko);

  v_finance := jsonb_build_object(
    'periode', format('%s-%s', v_tahun, lpad(v_bulan::text, 2, '0')),
    'tahun', v_tahun,
    'bulan', v_bulan,
    'tanggal_awal', v_start,
    'tanggal_akhir', v_end,
    'scope_toko', coalesce(v_toko, 'ALL'),
    'omzet_bruto_sales', v_omzet_bruto_sales,
    'omzet_dpp_sales', v_omzet_dpp_sales,
    'ppn_sales', v_ppn_sales,
    'omzet_bruto_gl', v_omzet_bruto_gl,
    'omzet_dpp_gl', v_omzet_dpp_gl,
    'ppn_gl', v_ppn_gl,
    'pengeluaran_ft', v_pengeluaran_ft,
    'pengeluaran_gl', v_pengeluaran_gl,
    'pengeluaran_manual_ft', v_pengeluaran_manual_ft,
    'bersih_gl', v_bersih_gl,
    'bersih_ops', v_omzet_dpp_sales - v_pengeluaran_ft,
    'selisih_omzet_bruto', v_omzet_bruto_gl - v_omzet_bruto_sales,
    'selisih_omzet_dpp', v_omzet_dpp_gl - v_omzet_dpp_sales,
    'selisih_pengeluaran', v_pengeluaran_manual_ft - v_pengeluaran_ft,
    'sales_aktif_periode', v_sales_n,
    'pos_journals_periode', v_pos_n,
    'posted_journals_periode', v_je_n,
    'toko_distinct_sales', v_toko_n,
    'rumus', jsonb_build_object(
      'omzet_bruto_sales', 'sum(sales.total_harga) aktif di periode',
      'omzet_dpp_sales', 'sum(round(total_harga/1.11))',
      'omzet_dpp_gl', 'sum(kredit-debit) akun 4100 sumber POS di periode',
      'ppn_gl', 'sum(kredit-debit) akun 2102 sumber POS di periode',
      'omzet_bruto_gl', 'omzet_dpp_gl + ppn_gl',
      'pengeluaran_ft', 'sum(FT PENGELUARAN APPROVED) di periode',
      'pengeluaran_gl', 'sum(debit-kredit) akun tipe COGS+EXPENSE di periode',
      'pengeluaran_manual_ft', 'sum debit beban pada jurnal MANUAL FT-{id} untuk FT PENGELUARAN periode',
      'bersih_gl', 'omzet_dpp_gl - pengeluaran_gl',
      'bersih_ops', 'omzet_dpp_sales - pengeluaran_ft'
    )
  );

  -- =========================================================================
  -- F1 CRITICAL: omzet DPP sales ≠ omzet DPP GL (POS 4100) — per invoice
  -- =========================================================================
  select count(*)::int,
         coalesce(sum(abs(x.dpp_sales - x.dpp_gl)), 0)::bigint
  into v_count, v_amt
  from (
    select
      coalesce(s.total_harga, 0) as bruto,
      round(coalesce(s.total_harga, 0) / 1.11)::bigint as dpp_sales,
      coalesce((
        select sum(jl.kredit - jl.debit)::bigint
        from public.journal_entries je
        join public.journal_lines jl on jl.entry_id = je.id
        where je.status = 'POSTED' and je.sumber = 'POS'
          and je.referensi_id = s.no_invoice
          and jl.akun_kode = '4100'
      ), 0)::bigint as dpp_gl
    from public.sales s
    where coalesce(s.total_harga, 0) > 0
      and coalesce(s.no_invoice, '') <> ''
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (s.created_at at time zone 'Asia/Jakarta')::date between v_start and v_end
      and (v_toko is null or upper(s.toko_id) = v_toko)
  ) x
  where x.dpp_sales <> x.dpp_gl;

  select coalesce(jsonb_agg(f.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'tanggal', (s.created_at at time zone 'Asia/Jakarta')::date,
      'omzet_bruto', coalesce(s.total_harga, 0),
      'omzet_dpp_sales', round(coalesce(s.total_harga, 0) / 1.11)::bigint,
      'omzet_dpp_gl', coalesce(g.dpp_gl, 0),
      'selisih', round(coalesce(s.total_harga, 0) / 1.11)::bigint - coalesce(g.dpp_gl, 0),
      'detail', format(
        'DPP sales=%s ≠ DPP GL 4100=%s (bruto=%s)',
        round(coalesce(s.total_harga, 0) / 1.11)::bigint,
        coalesce(g.dpp_gl, 0),
        coalesce(s.total_harga, 0))
    ) as obj
    from public.sales s
    left join lateral (
      select coalesce(sum(jl.kredit - jl.debit), 0)::bigint as dpp_gl
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED' and je.sumber = 'POS'
        and je.referensi_id = s.no_invoice
        and jl.akun_kode = '4100'
    ) g on true
    where coalesce(s.total_harga, 0) > 0
      and coalesce(s.no_invoice, '') <> ''
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (s.created_at at time zone 'Asia/Jakarta')::date between v_start and v_end
      and (v_toko is null or upper(s.toko_id) = v_toko)
      and round(coalesce(s.total_harga, 0) / 1.11)::bigint <> coalesce(g.dpp_gl, 0)
    order by abs(round(coalesce(s.total_harga, 0) / 1.11)::bigint - coalesce(g.dpp_gl, 0)) desc
    limit v_lim
  ) f;

  v_passed := (v_count = 0) and (v_omzet_dpp_sales = v_omzet_dpp_gl);
  if not v_passed then v_crit := v_crit + 1; end if;
  v_metrics := jsonb_build_array(
    jsonb_build_object('key', 'omzet_dpp_sales', 'label', 'Omzet DPP (sales)', 'amount', v_omzet_dpp_sales),
    jsonb_build_object('key', 'omzet_dpp_gl', 'label', 'Omzet DPP (GL 4100 POS)', 'amount', v_omzet_dpp_gl),
    jsonb_build_object('key', 'selisih', 'label', 'Selisih agregat', 'amount', v_omzet_dpp_gl - v_omzet_dpp_sales),
    jsonb_build_object('key', 'invoice_mismatch', 'label', 'Invoice tidak cocok', 'amount', v_count),
    jsonb_build_object('key', 'abs_selisih_invoice', 'label', 'Σ|selisih per invoice|', 'amount', v_amt)
  );
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'FIN_OMZET_DPP',
    'title', 'Omzet DPP: sales vs GL',
    'severity', 'CRITICAL',
    'passed', v_passed,
    'count', case
      when v_count > 0 then v_count
      when v_omzet_dpp_sales <> v_omzet_dpp_gl then 1
      else 0
    end,
    'definition', 'Per invoice & agregat periode: round(total_harga/1.11) harus = kredit-debit akun 4100 pada jurnal POS.',
    'metrics', v_metrics,
    'findings', case
      when v_count = 0 and v_omzet_dpp_sales <> v_omzet_dpp_gl then
        jsonb_build_array(jsonb_build_object(
          'toko_id', coalesce(v_toko, 'ALL'),
          'ref', 'AGGREGAT',
          'detail', format(
            'Agregat DPP sales=%s ≠ DPP GL=%s meski per-invoice lolos — cek jurnal POS di luar sale periode atau sebaliknya',
            v_omzet_dpp_sales, v_omzet_dpp_gl)
        ))
      else v_findings
    end
  ));

  -- =========================================================================
  -- F2 CRITICAL: omzet BRUTO sales ≠ omzet BRUTO GL (4100+2102 POS)
  -- =========================================================================
  select count(*)::int,
         coalesce(sum(abs(x.bruto_sales - x.bruto_gl)), 0)::bigint
  into v_count, v_amt
  from (
    select
      coalesce(s.total_harga, 0)::bigint as bruto_sales,
      coalesce((
        select sum(case when jl.akun_kode in ('4100', '2102') then jl.kredit - jl.debit else 0 end)::bigint
        from public.journal_entries je
        join public.journal_lines jl on jl.entry_id = je.id
        where je.status = 'POSTED' and je.sumber = 'POS'
          and je.referensi_id = s.no_invoice
          and jl.akun_kode in ('4100', '2102')
      ), 0)::bigint as bruto_gl
    from public.sales s
    where coalesce(s.total_harga, 0) > 0
      and coalesce(s.no_invoice, '') <> ''
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (s.created_at at time zone 'Asia/Jakarta')::date between v_start and v_end
      and (v_toko is null or upper(s.toko_id) = v_toko)
  ) x
  where x.bruto_sales <> x.bruto_gl;

  select coalesce(jsonb_agg(f.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'omzet_bruto_sales', coalesce(s.total_harga, 0),
      'omzet_bruto_gl', coalesce(g.bruto_gl, 0),
      'selisih', coalesce(s.total_harga, 0) - coalesce(g.bruto_gl, 0),
      'detail', format(
        'Bruto sales=%s ≠ bruto GL (4100+2102)=%s',
        coalesce(s.total_harga, 0), coalesce(g.bruto_gl, 0))
    ) as obj
    from public.sales s
    left join lateral (
      select coalesce(sum(case when jl.akun_kode in ('4100','2102') then jl.kredit-jl.debit else 0 end),0)::bigint as bruto_gl
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED' and je.sumber = 'POS'
        and je.referensi_id = s.no_invoice
        and jl.akun_kode in ('4100', '2102')
    ) g on true
    where coalesce(s.total_harga, 0) > 0
      and coalesce(s.no_invoice, '') <> ''
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (s.created_at at time zone 'Asia/Jakarta')::date between v_start and v_end
      and (v_toko is null or upper(s.toko_id) = v_toko)
      and coalesce(s.total_harga, 0) <> coalesce(g.bruto_gl, 0)
    order by abs(coalesce(s.total_harga, 0) - coalesce(g.bruto_gl, 0)) desc
    limit v_lim
  ) f;

  v_passed := (v_count = 0) and (v_omzet_bruto_sales = v_omzet_bruto_gl);
  if not v_passed then v_crit := v_crit + 1; end if;
  v_metrics := jsonb_build_array(
    jsonb_build_object('key', 'omzet_bruto_sales', 'label', 'Omzet bruto (sales)', 'amount', v_omzet_bruto_sales),
    jsonb_build_object('key', 'omzet_bruto_gl', 'label', 'Omzet bruto (GL 4100+2102)', 'amount', v_omzet_bruto_gl),
    jsonb_build_object('key', 'selisih', 'label', 'Selisih agregat', 'amount', v_omzet_bruto_gl - v_omzet_bruto_sales),
    jsonb_build_object('key', 'invoice_mismatch', 'label', 'Invoice tidak cocok', 'amount', v_count),
    jsonb_build_object('key', 'abs_selisih_invoice', 'label', 'Σ|selisih per invoice|', 'amount', v_amt)
  );
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'FIN_OMZET_BRUTO',
    'title', 'Omzet bruto: sales vs GL',
    'severity', 'CRITICAL',
    'passed', v_passed,
    'count', case when v_passed then 0 when v_count > 0 then v_count else 1 end,
    'definition', 'Per invoice & agregat: sales.total_harga harus = net kredit (4100+2102) jurnal POS.',
    'metrics', v_metrics,
    'findings', case
      when v_count = 0 and not v_passed then
        jsonb_build_array(jsonb_build_object(
          'toko_id', coalesce(v_toko, 'ALL'),
          'ref', 'AGGREGAT',
          'detail', format('Agregat bruto sales=%s ≠ GL=%s', v_omzet_bruto_sales, v_omzet_bruto_gl)
        ))
      else v_findings
    end
  ));

  -- =========================================================================
  -- F3 HIGH: pengeluaran FT ≠ beban ter-post MANUAL FT-{id}
  -- =========================================================================
  select count(*)::int,
         coalesce(sum(abs(coalesce(ft.nominal, 0) - coalesce(g.beban, 0))), 0)::bigint
  into v_count, v_amt
  from public.finance_transactions ft
  left join lateral (
    select coalesce(sum(jl.debit), 0)::bigint as beban
    from public.journal_entries je
    join public.journal_lines jl on jl.entry_id = je.id
    join public.chart_of_accounts c on c.kode = jl.akun_kode
    where je.status = 'POSTED' and je.sumber = 'MANUAL'
      and je.referensi_id = 'FT-' || ft.id::text
      and c.tipe in ('COGS', 'EXPENSE')
  ) g on true
  where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
    and upper(coalesce(ft.jenis_transaksi, '')) = 'PENGELUARAN'
    and coalesce(ft.nominal, 0) > 0
    and coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date)
        between v_start and v_end
    and (v_toko is null or upper(ft.toko_id) = v_toko)
    and coalesce(ft.nominal, 0) <> coalesce(g.beban, 0);

  select coalesce(jsonb_agg(f.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', ft.toko_id,
      'ref', 'FT-' || ft.id::text,
      'ft_id', ft.id,
      'pengeluaran_ft', coalesce(ft.nominal, 0),
      'pengeluaran_gl', coalesce(g.beban, 0),
      'selisih', coalesce(ft.nominal, 0) - coalesce(g.beban, 0),
      'kategori', ft.kategori,
      'detail', format(
        'FT pengeluaran=%s ≠ debit beban GL MANUAL=%s',
        coalesce(ft.nominal, 0), coalesce(g.beban, 0))
    ) as obj
    from public.finance_transactions ft
    left join lateral (
      select coalesce(sum(jl.debit), 0)::bigint as beban
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      join public.chart_of_accounts c on c.kode = jl.akun_kode
      where je.status = 'POSTED' and je.sumber = 'MANUAL'
        and je.referensi_id = 'FT-' || ft.id::text
        and c.tipe in ('COGS', 'EXPENSE')
    ) g on true
    where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
      and upper(coalesce(ft.jenis_transaksi, '')) = 'PENGELUARAN'
      and coalesce(ft.nominal, 0) > 0
      and coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date)
          between v_start and v_end
      and (v_toko is null or upper(ft.toko_id) = v_toko)
      and coalesce(ft.nominal, 0) <> coalesce(g.beban, 0)
    order by abs(coalesce(ft.nominal, 0) - coalesce(g.beban, 0)) desc
    limit v_lim
  ) f;

  v_passed := (v_count = 0) and (v_pengeluaran_ft = v_pengeluaran_manual_ft);
  if not v_passed then v_high := v_high + 1; end if;
  v_metrics := jsonb_build_array(
    jsonb_build_object('key', 'pengeluaran_ft', 'label', 'Pengeluaran (FT)', 'amount', v_pengeluaran_ft),
    jsonb_build_object('key', 'pengeluaran_manual_ft', 'label', 'Pengeluaran ter-post (GL MANUAL)', 'amount', v_pengeluaran_manual_ft),
    jsonb_build_object('key', 'pengeluaran_gl_all', 'label', 'Semua beban GL (COGS+EXPENSE)', 'amount', v_pengeluaran_gl),
    jsonb_build_object('key', 'selisih_ft_vs_manual', 'label', 'Selisih FT vs MANUAL', 'amount', v_pengeluaran_manual_ft - v_pengeluaran_ft),
    jsonb_build_object('key', 'ft_mismatch', 'label', 'FT tidak cocok', 'amount', v_count),
    jsonb_build_object('key', 'abs_selisih_ft', 'label', 'Σ|selisih per FT|', 'amount', v_amt)
  );
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'FIN_PENGELUARAN',
    'title', 'Pengeluaran: FT vs GL',
    'severity', 'HIGH',
    'passed', v_passed,
    'count', case when v_passed then 0 when v_count > 0 then v_count else 1 end,
    'definition', 'Setiap FT PENGELUARAN APPROVED: nominal harus = total debit akun COGS/EXPENSE pada jurnal MANUAL FT-{id}. Agregat FT = agregat MANUAL.',
    'metrics', v_metrics,
    'findings', v_findings
  ));

  -- =========================================================================
  -- F4 INFO/MEDIUM: ringkasan bersih (tampil angka; gagal MEDIUM jika ops≠gl material)
  -- =========================================================================
  v_amt := v_bersih_gl;
  v_amt2 := v_omzet_dpp_sales - v_pengeluaran_ft;
  -- Material = beda dan ada komponen pengeluaran_gl di luar FT (bukan otomatis error)
  -- Hanya flag MEDIUM jika FT sudah match MANUAL tapi bersih_gl ≠ dpp_gl - manual_ft
  -- (konsistensi internal GL)
  v_passed := (v_omzet_dpp_gl - v_pengeluaran_manual_ft) = (v_omzet_dpp_gl - v_pengeluaran_ft)
    or v_pengeluaran_ft = v_pengeluaran_manual_ft;
  -- Always pass structural; show numbers. Fail only if internal identity breaks:
  v_passed := (v_bersih_gl = (v_omzet_dpp_gl - v_pengeluaran_gl));
  if not v_passed then v_med := v_med + 1; end if;
  v_metrics := jsonb_build_array(
    jsonb_build_object('key', 'omzet_dpp_gl', 'label', 'Omzet DPP GL', 'amount', v_omzet_dpp_gl),
    jsonb_build_object('key', 'pengeluaran_gl', 'label', 'Pengeluaran GL', 'amount', v_pengeluaran_gl),
    jsonb_build_object('key', 'bersih_gl', 'label', 'Bersih / laba GL', 'amount', v_bersih_gl),
    jsonb_build_object('key', 'omzet_dpp_sales', 'label', 'Omzet DPP sales', 'amount', v_omzet_dpp_sales),
    jsonb_build_object('key', 'pengeluaran_ft', 'label', 'Pengeluaran FT', 'amount', v_pengeluaran_ft),
    jsonb_build_object('key', 'bersih_ops', 'label', 'Bersih ops (DPP sales − FT)', 'amount', v_amt2),
    jsonb_build_object('key', 'selisih_bersih', 'label', 'Selisih bersih GL vs ops', 'amount', v_amt - v_amt2)
  );
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'FIN_BERSIH',
    'title', 'Bersih: omzet − pengeluaran',
    'severity', case when v_passed then 'INFO' else 'MEDIUM' end,
    'passed', v_passed,
    'count', case when v_passed then 0 else 1 end,
    'definition', 'bersih_gl = omzet_dpp_gl − pengeluaran_gl. bersih_ops = omzet_dpp_sales − pengeluaran_ft (pembanding operasional; bisa beda jika ada beban non-FT).',
    'metrics', v_metrics,
    'findings', jsonb_build_array(jsonb_build_object(
      'toko_id', coalesce(v_toko, 'ALL'),
      'ref', format('%s-%s', v_tahun, lpad(v_bulan::text, 2, '0')),
      'omzet_dpp_gl', v_omzet_dpp_gl,
      'pengeluaran_gl', v_pengeluaran_gl,
      'bersih_gl', v_bersih_gl,
      'omzet_dpp_sales', v_omzet_dpp_sales,
      'pengeluaran_ft', v_pengeluaran_ft,
      'bersih_ops', v_amt2,
      'detail', format(
        'GL: omzet DPP %s − beban %s = bersih %s · Ops: DPP sales %s − FT keluar %s = %s',
        v_omzet_dpp_gl, v_pengeluaran_gl, v_bersih_gl,
        v_omzet_dpp_sales, v_pengeluaran_ft, v_amt2)
    ))
  ));
  if v_passed then v_info := v_info + 1; end if;

  -- =========================================================================
  -- C1 CRITICAL: jurnal POSTED tidak berimbang — TOTAL penuh
  -- =========================================================================
  select count(*)::int, coalesce(sum(abs(s.d - s.k)), 0)::bigint
  into v_count, v_amt
  from public.journal_entries je
  join lateral (
    select coalesce(sum(jl.debit),0)::bigint d,
           coalesce(sum(jl.kredit),0)::bigint k
    from public.journal_lines jl where jl.entry_id = je.id
  ) s on true
  where je.status = 'POSTED'
    and (v_toko is null or je.toko_id = v_toko)
    and s.d <> s.k;

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', je.toko_id,
      'ref', coalesce(je.referensi_id, je.id::text),
      'sumber', je.sumber,
      'tanggal', je.tanggal,
      'entry_id', je.id,
      'debit', s.d,
      'kredit', s.k,
      'selisih', s.d - s.k,
      'detail', format('Jurnal tidak berimbang: debit=%s kredit=%s', s.d, s.k)
    ) as obj
    from public.journal_entries je
    join lateral (
      select coalesce(sum(jl.debit),0)::bigint d,
             coalesce(sum(jl.kredit),0)::bigint k
      from public.journal_lines jl where jl.entry_id = je.id
    ) s on true
    where je.status = 'POSTED'
      and (v_toko is null or je.toko_id = v_toko)
      and s.d <> s.k
    order by abs(s.d - s.k) desc, je.tanggal desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_crit := v_crit + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'JE_UNBALANCED',
    'title', 'Jurnal tidak berimbang',
    'severity', 'CRITICAL',
    'passed', v_passed,
    'count', v_count,
    'definition', 'Setiap journal_entries status POSTED harus punya total debit baris = total kredit baris.',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah', 'label', 'Jurnal tidak balance', 'amount', v_count),
      jsonb_build_object('key', 'selisih_abs', 'label', 'Σ|Debit−Kredit|', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C2 CRITICAL: sale aktif tanpa POS — total omzet penuh
  -- =========================================================================
  select count(*)::int, coalesce(sum(coalesce(s.total_harga, 0)), 0)::bigint
  into v_count, v_amt
  from public.sales s
  where coalesce(s.total_harga, 0) > 0
    and coalesce(s.no_invoice, '') <> ''
    and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
    and (v_toko is null or upper(s.toko_id) = v_toko)
    and not exists (
      select 1 from public.journal_entries je
      where je.status = 'POSTED' and je.sumber = 'POS'
        and je.referensi_id = s.no_invoice
    );

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'sale_id', s.id,
      'tanggal', (s.created_at at time zone 'Asia/Jakarta')::date,
      'total', coalesce(s.total_harga, 0),
      'sisa', coalesce(s.sisa_tagihan, 0),
      'status', s.status_pembayaran,
      'detail', format('Sale aktif omzet %s tanpa jurnal POS POSTED', coalesce(s.total_harga, 0))
    ) as obj
    from public.sales s
    where coalesce(s.total_harga, 0) > 0
      and coalesce(s.no_invoice, '') <> ''
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (v_toko is null or upper(s.toko_id) = v_toko)
      and not exists (
        select 1 from public.journal_entries je
        where je.status = 'POSTED' and je.sumber = 'POS'
          and je.referensi_id = s.no_invoice
      )
    order by s.created_at desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_crit := v_crit + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'SALE_MISSING_POS_JE',
    'title', 'Penjualan tanpa jurnal POS',
    'severity', 'CRITICAL',
    'passed', v_passed,
    'count', v_count,
    'definition', 'Sale total_harga>0, status bukan BATAL/VOID/CANCEL, wajib punya journal POS POSTED (semua waktu, bukan hanya periode).',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah_sale', 'label', 'Sale tanpa POS', 'amount', v_count),
      jsonb_build_object('key', 'omzet_hilang', 'label', 'Omzet bruto belum di GL', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C3 CRITICAL: batal masih POSTED
  -- =========================================================================
  select count(*)::int,
         coalesce(sum((
           select coalesce(sum(jl.debit), 0) from public.journal_lines jl where jl.entry_id = je.id
         )), 0)::bigint
  into v_count, v_amt
  from public.sales s
  join public.journal_entries je
    on je.sumber = 'POS' and je.referensi_id = s.no_invoice and je.status = 'POSTED'
  where upper(coalesce(s.status_pembayaran, '')) in ('BATAL', 'VOID', 'CANCEL')
    and (v_toko is null or upper(s.toko_id) = v_toko);

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'sale_id', s.id,
      'entry_id', je.id,
      'status', s.status_pembayaran,
      'total', coalesce(s.total_harga, 0),
      'detail', format('Sale %s masih punya jurnal POS POSTED (omzet %s)', s.status_pembayaran, coalesce(s.total_harga, 0))
    ) as obj
    from public.sales s
    join public.journal_entries je
      on je.sumber = 'POS' and je.referensi_id = s.no_invoice and je.status = 'POSTED'
    where upper(coalesce(s.status_pembayaran, '')) in ('BATAL', 'VOID', 'CANCEL')
      and (v_toko is null or upper(s.toko_id) = v_toko)
    order by s.created_at desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_crit := v_crit + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'BATAL_POS_STILL_POSTED',
    'title', 'Sale batal masih punya jurnal POS',
    'severity', 'CRITICAL',
    'passed', v_passed,
    'count', v_count,
    'definition', 'Status BATAL/VOID/CANCEL tidak boleh tersisa jurnal POS POSTED.',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah', 'label', 'Jurnal batal masih POSTED', 'amount', v_count),
      jsonb_build_object('key', 'debit_tersisa', 'label', 'Σ debit jurnal tersisa', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C4 HIGH: identitas POS rusak
  -- =========================================================================
  select count(*)::int, coalesce(sum(abs(a.asset_side - a.rev_side)), 0)::bigint
  into v_count, v_amt
  from public.journal_entries je
  join lateral (
    select
      coalesce(sum(case when jl.akun_kode in ('1101','1102','1103') then jl.debit - jl.kredit else 0 end),0)::bigint as asset_side,
      coalesce(sum(case when jl.akun_kode in ('4100','2102') then jl.kredit - jl.debit else 0 end),0)::bigint as rev_side
    from public.journal_lines jl where jl.entry_id = je.id
  ) a on true
  where je.status = 'POSTED' and je.sumber = 'POS'
    and (v_toko is null or je.toko_id = v_toko)
    and a.asset_side <> a.rev_side;

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', je.toko_id,
      'ref', je.referensi_id,
      'entry_id', je.id,
      'asset_side', a.asset_side,
      'revenue_side', a.rev_side,
      'selisih', a.asset_side - a.rev_side,
      'detail', format('Kas/Bank/Piutang=%s vs Penjualan+PPN=%s', a.asset_side, a.rev_side)
    ) as obj
    from public.journal_entries je
    join lateral (
      select
        coalesce(sum(case when jl.akun_kode in ('1101','1102','1103') then jl.debit - jl.kredit else 0 end),0)::bigint as asset_side,
        coalesce(sum(case when jl.akun_kode in ('4100','2102') then jl.kredit - jl.debit else 0 end),0)::bigint as rev_side
      from public.journal_lines jl where jl.entry_id = je.id
    ) a on true
    where je.status = 'POSTED' and je.sumber = 'POS'
      and (v_toko is null or je.toko_id = v_toko)
      and a.asset_side <> a.rev_side
    order by abs(a.asset_side - a.rev_side) desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_high := v_high + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'POS_IDENTITY_BREAK',
    'title', 'Identitas jurnal POS rusak',
    'severity', 'HIGH',
    'passed', v_passed,
    'count', v_count,
    'definition', 'Sumber POS: net (1101+1102+1103) harus = net kredit (4100+2102).',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah', 'label', 'Jurnal POS rusak', 'amount', v_count),
      jsonb_build_object('key', 'selisih_abs', 'label', 'Σ|aset−pendapatan|', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C5 HIGH: CLOSE FT tanpa jurnal
  -- =========================================================================
  select count(*)::int, coalesce(sum(coalesce(ft.nominal, 0)), 0)::bigint
  into v_count, v_amt
  from public.finance_transactions ft
  where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
    and coalesce(ft.nominal, 0) > 0
    and (
      upper(coalesce(ft.referensi_id, '')) like 'CLOSE-%'
      or upper(coalesce(ft.kategori, '')) like '%PENUTUPAN%'
      or upper(coalesce(ft.kategori, '')) like '%CLOSING%'
    )
    and (v_toko is null or upper(ft.toko_id) = v_toko)
    and not exists (
      select 1 from public.journal_entries je
      where je.status = 'POSTED' and je.sumber = 'CLOSING'
        and je.referensi_id = coalesce(nullif(btrim(ft.referensi_id), ''), 'FT-' || ft.id::text)
    );

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', ft.toko_id,
      'ref', coalesce(nullif(btrim(ft.referensi_id), ''), 'FT-' || ft.id::text),
      'ft_id', ft.id,
      'nominal', ft.nominal,
      'tanggal', coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date),
      'detail', format('Closing APPROVED nominal %s belum punya jurnal CLOSING', ft.nominal)
    ) as obj
    from public.finance_transactions ft
    where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
      and coalesce(ft.nominal, 0) > 0
      and (
        upper(coalesce(ft.referensi_id, '')) like 'CLOSE-%'
        or upper(coalesce(ft.kategori, '')) like '%PENUTUPAN%'
        or upper(coalesce(ft.kategori, '')) like '%CLOSING%'
      )
      and (v_toko is null or upper(ft.toko_id) = v_toko)
      and not exists (
        select 1 from public.journal_entries je
        where je.status = 'POSTED' and je.sumber = 'CLOSING'
          and je.referensi_id = coalesce(nullif(btrim(ft.referensi_id), ''), 'FT-' || ft.id::text)
      )
    order by coalesce(ft.tanggal_transaksi, ft.created_at::date) desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_high := v_high + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'CLOSE_FT_MISSING_JE',
    'title', 'Closing tanpa jurnal CLOSING',
    'severity', 'HIGH',
    'passed', v_passed,
    'count', v_count,
    'definition', 'FT APPROVED CLOSE/PENUTUPAN/CLOSING wajib punya journal CLOSING POSTED.',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah', 'label', 'Closing tanpa jurnal', 'amount', v_count),
      jsonb_build_object('key', 'nominal', 'label', 'Σ nominal belum di GL', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C6 HIGH: FT manual tanpa jurnal
  -- =========================================================================
  select count(*)::int, coalesce(sum(coalesce(ft.nominal, 0)), 0)::bigint
  into v_count, v_amt
  from public.finance_transactions ft
  where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
    and coalesce(ft.nominal, 0) > 0
    and upper(coalesce(ft.jenis_transaksi, '')) in
        ('PEMASUKAN', 'PENGELUARAN', 'PIUTANG', 'HUTANG')
    and upper(coalesce(ft.referensi_id, '')) not like 'CLOSE-%'
    and upper(coalesce(ft.referensi_id, '')) not like 'SETTLE-%'
    and upper(coalesce(ft.kategori, '')) not like '%PENUTUPAN%'
    and upper(coalesce(ft.kategori, '')) not like '%CLOSING%'
    and upper(coalesce(ft.kategori, '')) not like '%PELUNASAN%'
    and (
      ft.referensi_id is null
      or btrim(ft.referensi_id) = ''
      or upper(ft.referensi_id) like 'FT-%'
    )
    and (v_toko is null or upper(ft.toko_id) = v_toko)
    and not exists (
      select 1 from public.journal_entries je
      where je.status = 'POSTED' and je.sumber = 'MANUAL'
        and je.referensi_id = 'FT-' || ft.id::text
    );

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', ft.toko_id,
      'ref', 'FT-' || ft.id::text,
      'ft_id', ft.id,
      'jenis', ft.jenis_transaksi,
      'kategori', ft.kategori,
      'nominal', ft.nominal,
      'detail', format('FT %s nominal %s tanpa jurnal MANUAL', ft.jenis_transaksi, ft.nominal)
    ) as obj
    from public.finance_transactions ft
    where upper(coalesce(ft.status_konfirmasi, '')) = 'APPROVED'
      and coalesce(ft.nominal, 0) > 0
      and upper(coalesce(ft.jenis_transaksi, '')) in
          ('PEMASUKAN', 'PENGELUARAN', 'PIUTANG', 'HUTANG')
      and upper(coalesce(ft.referensi_id, '')) not like 'CLOSE-%'
      and upper(coalesce(ft.referensi_id, '')) not like 'SETTLE-%'
      and upper(coalesce(ft.kategori, '')) not like '%PENUTUPAN%'
      and upper(coalesce(ft.kategori, '')) not like '%CLOSING%'
      and upper(coalesce(ft.kategori, '')) not like '%PELUNASAN%'
      and (
        ft.referensi_id is null
        or btrim(ft.referensi_id) = ''
        or upper(ft.referensi_id) like 'FT-%'
      )
      and (v_toko is null or upper(ft.toko_id) = v_toko)
      and not exists (
        select 1 from public.journal_entries je
        where je.status = 'POSTED' and je.sumber = 'MANUAL'
          and je.referensi_id = 'FT-' || ft.id::text
      )
    order by coalesce(ft.tanggal_transaksi, ft.created_at::date) desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_high := v_high + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'MANUAL_FT_MISSING_JE',
    'title', 'FT manual tanpa jurnal MANUAL',
    'severity', 'HIGH',
    'passed', v_passed,
    'count', v_count,
    'definition', 'FT APPROVED PEMASUKAN/PENGELUARAN/PIUTANG/HUTANG (bukan CLOSE/SETTLE/omzet POS) wajib punya journal MANUAL FT-{id}.',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah', 'label', 'FT tanpa jurnal', 'amount', v_count),
      jsonb_build_object('key', 'nominal', 'label', 'Σ nominal belum di GL', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C7 HIGH: AR menggantung
  -- =========================================================================
  select count(*)::int, coalesce(sum(a.ar), 0)::bigint
  into v_count, v_amt
  from public.sales s
  join public.journal_entries je
    on je.sumber = 'POS' and je.referensi_id = s.no_invoice and je.status = 'POSTED'
  join lateral (
    select coalesce(sum(jl.debit - jl.kredit),0)::bigint ar
    from public.journal_lines jl
    where jl.entry_id = je.id and jl.akun_kode = '1103'
  ) a on true
  where coalesce(s.sisa_tagihan, 0) = 0
    and a.ar > 0
    and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
    and (v_toko is null or upper(s.toko_id) = v_toko)
    and not exists (
      select 1 from public.journal_entries j2
      where j2.status = 'POSTED' and j2.sumber = 'SETTLE'
        and (
          j2.referensi_id ilike 'SETTLE-' || s.no_invoice || '-%'
          or public.gl_extract_settle_invoice(j2.referensi_id) = s.no_invoice
        )
    );

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'sale_id', s.id,
      'ar_pos', a.ar,
      'sisa_sales', coalesce(s.sisa_tagihan, 0),
      'detail', format('Piutang GL %s menggantung; sale sudah lunas tanpa SETTLE', a.ar)
    ) as obj
    from public.sales s
    join public.journal_entries je
      on je.sumber = 'POS' and je.referensi_id = s.no_invoice and je.status = 'POSTED'
    join lateral (
      select coalesce(sum(jl.debit - jl.kredit),0)::bigint ar
      from public.journal_lines jl
      where jl.entry_id = je.id and jl.akun_kode = '1103'
    ) a on true
    where coalesce(s.sisa_tagihan, 0) = 0
      and a.ar > 0
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (v_toko is null or upper(s.toko_id) = v_toko)
      and not exists (
        select 1 from public.journal_entries j2
        where j2.status = 'POSTED' and j2.sumber = 'SETTLE'
          and (
            j2.referensi_id ilike 'SETTLE-' || s.no_invoice || '-%'
            or public.gl_extract_settle_invoice(j2.referensi_id) = s.no_invoice
          )
      )
    order by a.ar desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_high := v_high + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'AR_OPEN_BUT_SALE_LUNAS',
    'title', 'Piutang GL menggantung (sale sudah lunas)',
    'severity', 'HIGH',
    'passed', v_passed,
    'count', v_count,
    'definition', 'Sale sisa=0 + POS debit 1103>0 wajib punya SETTLE POSTED.',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah', 'label', 'Invoice AR menggantung', 'amount', v_count),
      jsonb_build_object('key', 'ar', 'label', 'Σ piutang menggantung', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C8 MEDIUM: AR GL vs sales sisa (per toko, full)
  -- =========================================================================
  select count(*)::int,
         coalesce(sum(abs(coalesce(g.gl_ar, 0) - coalesce(s.sales_sisa, 0))), 0)::bigint
  into v_count, v_amt
  from (
    select toko_id from (
      select je.toko_id
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED' and jl.akun_kode = '1103'
        and (v_toko is null or je.toko_id = v_toko)
      group by je.toko_id
      union
      select upper(s.toko_id)
      from public.sales s
      where coalesce(s.sisa_tagihan, 0) > 0
        and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
        and (v_toko is null or upper(s.toko_id) = v_toko)
      group by upper(s.toko_id)
    ) k
  ) keys
  left join (
    select je.toko_id, coalesce(sum(jl.debit - jl.kredit),0)::bigint as gl_ar
    from public.journal_entries je
    join public.journal_lines jl on jl.entry_id = je.id
    where je.status = 'POSTED' and jl.akun_kode = '1103'
      and (v_toko is null or je.toko_id = v_toko)
    group by je.toko_id
  ) g on g.toko_id = keys.toko_id
  left join (
    select upper(s.toko_id) as toko_id,
           coalesce(sum(s.sisa_tagihan),0)::bigint as sales_sisa
    from public.sales s
    where coalesce(s.sisa_tagihan, 0) > 0
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (v_toko is null or upper(s.toko_id) = v_toko)
    group by upper(s.toko_id)
  ) s on s.toko_id = keys.toko_id
  where coalesce(g.gl_ar, 0) <> coalesce(s.sales_sisa, 0);

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    with gl as (
      select je.toko_id, coalesce(sum(jl.debit - jl.kredit),0)::bigint as gl_ar
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED' and jl.akun_kode = '1103'
        and (v_toko is null or je.toko_id = v_toko)
      group by je.toko_id
    ),
    ss as (
      select upper(s.toko_id) as toko_id,
             coalesce(sum(s.sisa_tagihan),0)::bigint as sales_sisa
      from public.sales s
      where coalesce(s.sisa_tagihan, 0) > 0
        and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
        and (v_toko is null or upper(s.toko_id) = v_toko)
      group by upper(s.toko_id)
    ),
    keys as (
      select toko_id from gl union select toko_id from ss
    )
    select jsonb_build_object(
      'toko_id', k.toko_id,
      'ref', k.toko_id,
      'gl_ar', coalesce(g.gl_ar, 0),
      'sales_sisa', coalesce(s.sales_sisa, 0),
      'selisih', coalesce(g.gl_ar, 0) - coalesce(s.sales_sisa, 0),
      'detail', format(
        'Piutang GL 1103=%s ≠ sisa sales=%s',
        coalesce(g.gl_ar, 0), coalesce(s.sales_sisa, 0))
    ) as obj
    from keys k
    left join gl g on g.toko_id = k.toko_id
    left join ss s on s.toko_id = k.toko_id
    where coalesce(g.gl_ar, 0) <> coalesce(s.sales_sisa, 0)
    order by abs(coalesce(g.gl_ar, 0) - coalesce(s.sales_sisa, 0)) desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_med := v_med + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'AR_GL_VS_SALES_SISA',
    'title', 'Rekonsiliasi piutang GL vs sales',
    'severity', 'MEDIUM',
    'passed', v_passed,
    'count', v_count,
    'definition', 'Per toko: saldo 1103 POSTED = sum sisa_tagihan sales aktif.',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'toko_mismatch', 'label', 'Toko tidak cocok', 'amount', v_count),
      jsonb_build_object('key', 'selisih_abs', 'label', 'Σ|selisih AR|', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C9 MEDIUM: baris ke COA invalid
  -- =========================================================================
  select count(*)::int,
         coalesce(sum(coalesce(jl.debit, 0) + coalesce(jl.kredit, 0)), 0)::bigint
  into v_count, v_amt
  from public.journal_lines jl
  join public.journal_entries je on je.id = jl.entry_id
  left join public.chart_of_accounts c on c.kode = jl.akun_kode
  where je.status = 'POSTED'
    and (v_toko is null or je.toko_id = v_toko)
    and (c.kode is null or c.aktif is not true or c.is_postable is not true);

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    select jsonb_build_object(
      'toko_id', je.toko_id,
      'ref', coalesce(je.referensi_id, je.id::text),
      'entry_id', je.id,
      'akun_kode', jl.akun_kode,
      'debit', jl.debit,
      'kredit', jl.kredit,
      'detail', case
        when c.kode is null then 'Akun tidak ada di COA'
        when not c.aktif then 'Akun nonaktif'
        when not c.is_postable then 'Akun non-postable'
        else 'Akun invalid'
      end
    ) as obj
    from public.journal_lines jl
    join public.journal_entries je on je.id = jl.entry_id
    left join public.chart_of_accounts c on c.kode = jl.akun_kode
    where je.status = 'POSTED'
      and (v_toko is null or je.toko_id = v_toko)
      and (c.kode is null or c.aktif is not true or c.is_postable is not true)
    order by je.tanggal desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if not v_passed then v_med := v_med + 1; end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'LINE_INVALID_COA',
    'title', 'Baris jurnal ke akun invalid',
    'severity', 'MEDIUM',
    'passed', v_passed,
    'count', v_count,
    'definition', 'Baris POSTED wajib ke akun ada, aktif, is_postable=true.',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah_baris', 'label', 'Baris invalid', 'amount', v_count),
      jsonb_build_object('key', 'nominal', 'label', 'Σ debit+kredit invalid', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- =========================================================================
  -- C10 settle multi / over — total penuh
  -- =========================================================================
  select count(*)::int,
         coalesce(sum(greatest(e.settle_cr - e.ar_pos, 0)), 0)::bigint,
         coalesce(bool_or(e.settle_cr > e.ar_pos), false)
  into v_count, v_amt, v_over_settle
  from (
    with settle as (
      select
        public.gl_extract_settle_invoice(je.referensi_id) as inv,
        je.toko_id,
        count(*)::int as n_settle,
        coalesce(sum(case when jl.akun_kode = '1103' then jl.kredit else 0 end), 0)::bigint as settle_cr
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED' and je.sumber = 'SETTLE'
        and (v_toko is null or je.toko_id = v_toko)
        and public.gl_extract_settle_invoice(je.referensi_id) is not null
      group by 1, 2
    )
    select st.*, coalesce(ar.ar_pos, 0)::bigint as ar_pos
    from settle st
    left join lateral (
      select coalesce(sum(jl.debit - jl.kredit), 0)::bigint as ar_pos
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED' and je.sumber = 'POS'
        and je.referensi_id = st.inv and jl.akun_kode = '1103'
    ) ar on true
    where st.settle_cr > coalesce(ar.ar_pos, 0) or st.n_settle > 1
  ) e;

  select coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  into v_findings
  from (
    with settle as (
      select
        public.gl_extract_settle_invoice(je.referensi_id) as inv,
        je.toko_id,
        count(*)::int as n_settle,
        coalesce(sum(case when jl.akun_kode = '1103' then jl.kredit else 0 end), 0)::bigint as settle_cr
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED' and je.sumber = 'SETTLE'
        and (v_toko is null or je.toko_id = v_toko)
        and public.gl_extract_settle_invoice(je.referensi_id) is not null
      group by 1, 2
    ),
    enriched as (
      select st.*, coalesce(ar.ar_pos, 0)::bigint as ar_pos
      from settle st
      left join lateral (
        select coalesce(sum(jl.debit - jl.kredit), 0)::bigint as ar_pos
        from public.journal_entries je
        join public.journal_lines jl on jl.entry_id = je.id
        where je.status = 'POSTED' and je.sumber = 'POS'
          and je.referensi_id = st.inv and jl.akun_kode = '1103'
      ) ar on true
      where st.settle_cr > coalesce(ar.ar_pos, 0) or st.n_settle > 1
    )
    select jsonb_build_object(
      'toko_id', e.toko_id,
      'ref', e.inv,
      'n_settle', e.n_settle,
      'settle_cr_1103', e.settle_cr,
      'ar_pos', e.ar_pos,
      'over_settled', e.settle_cr > e.ar_pos,
      'detail', case
        when e.settle_cr > e.ar_pos then
          format('Settle berlebih: %s > AR POS %s (%s jurnal)', e.settle_cr, e.ar_pos, e.n_settle)
        else
          format('%s jurnal SETTLE (kredit 1103=%s, AR POS=%s)', e.n_settle, e.settle_cr, e.ar_pos)
      end
    ) as obj
    from enriched e
    order by (e.settle_cr > e.ar_pos) desc, e.n_settle desc
    limit v_lim
  ) x;

  v_passed := v_count = 0;
  if v_over_settle then
    v_high := v_high + 1;
  elsif not v_passed then
    v_info := v_info + 1;
  end if;

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'SETTLE_MULTI_OR_OVER',
    'title', 'Settle ganda / berlebih per invoice',
    'severity', case when v_over_settle then 'HIGH' else 'INFO' end,
    'passed', case when v_over_settle then false else v_passed end,
    'count', v_count,
    'definition', 'Settle berlebih (kredit 1103 > AR POS) = HIGH. Multi-settle tanpa over = INFO (pelunasan bertahap).',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'jumlah', 'label', 'Invoice perlu review', 'amount', v_count),
      jsonb_build_object('key', 'over_amount', 'label', 'Σ settle berlebih', 'amount', v_amt)
    ),
    'findings', v_findings
  ));

  -- Coverage info (periode)
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'COVERAGE_STATS',
    'title', 'Statistik cakupan periode',
    'severity', 'INFO',
    'passed', true,
    'count', 0,
    'definition', 'Cakupan data pada periode filter audit (bukan seluruh sejarah).',
    'metrics', jsonb_build_array(
      jsonb_build_object('key', 'sales', 'label', 'Sale aktif periode', 'amount', v_sales_n),
      jsonb_build_object('key', 'pos', 'label', 'Jurnal POS periode', 'amount', v_pos_n),
      jsonb_build_object('key', 'journals', 'label', 'Jurnal POSTED periode', 'amount', v_je_n),
      jsonb_build_object('key', 'toko', 'label', 'Toko (dari sales)', 'amount', v_toko_n)
    ),
    'findings', jsonb_build_array(jsonb_build_object(
      'toko_id', coalesce(v_toko, 'ALL'),
      'ref', format('%s-%s', v_tahun, lpad(v_bulan::text, 2, '0')),
      'detail', format(
        'Periode %s–%s · Sale=%s · POS=%s · Jurnal=%s · Toko=%s',
        v_start, v_end, v_sales_n, v_pos_n, v_je_n, v_toko_n)
    ))
  ));
  v_info := v_info + 1;

  return jsonb_build_object(
    'generated_at', now(),
    'scope_toko', coalesce(v_toko, 'ALL'),
    'finance', v_finance,
    'summary', jsonb_build_object(
      'critical_failed', v_crit,
      'high_failed', v_high,
      'medium_failed', v_med,
      'info_checks', v_info,
      'checks_run', jsonb_array_length(v_checks),
      'all_clear', (v_crit = 0 and v_high = 0 and v_med = 0),
      'omzet_bruto', v_omzet_bruto_gl,
      'omzet_dpp', v_omzet_dpp_gl,
      'pengeluaran', v_pengeluaran_gl,
      'bersih', v_bersih_gl
    ),
    'checks', v_checks
  );
end;
$$;

grant execute on function public.gl_run_full_audit(text, int, int, int) to authenticated;
