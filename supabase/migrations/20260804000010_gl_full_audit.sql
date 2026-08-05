-- =============================================================================
-- GL Full Audit E2E — owner/pusat only (baseline v1)
-- REVISI ANGKA NYATA: lihat 20260804000011_gl_full_audit_with_numbers.sql
-- =============================================================================

create or replace function public.gl_run_full_audit(
  p_toko_id text default null,
  p_limit_per_check int default 80
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := nullif(upper(btrim(coalesce(p_toko_id, ''))), '');
  v_lim int := greatest(10, least(coalesce(p_limit_per_check, 80), 200));
  v_checks jsonb := '[]'::jsonb;
  v_findings jsonb;
  v_count int;
  v_crit int := 0;
  v_high int := 0;
  v_med int := 0;
  v_info int := 0;
  v_toko_n int;
  v_passed boolean;
  v_over_settle boolean;
  v_sales int;
  v_pos int;
  v_je int;
begin
  if not public.gl_is_owner_or_pusat() then
    raise exception 'Audit GL hanya untuk owner/pusat';
  end if;

  select count(distinct upper(toko_id)) into v_toko_n
  from public.sales
  where coalesce(toko_id, '') <> ''
    and (v_toko is null or upper(toko_id) = v_toko);

  -- -------------------------------------------------------------------------
  -- C1 CRITICAL: jurnal POSTED tidak berimbang (sum debit ≠ sum kredit)
  -- Definisi: per entry_id, total debit baris harus = total kredit baris.
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
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
      from public.journal_lines jl
      where jl.entry_id = je.id
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
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C2 CRITICAL: penjualan aktif (bukan batal) tanpa jurnal POS
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'sale_id', s.id,
      'tanggal', (s.created_at at time zone 'Asia/Jakarta')::date,
      'total', coalesce(s.total_harga, 0),
      'sisa', coalesce(s.sisa_tagihan, 0),
      'status', s.status_pembayaran,
      'detail', 'Sale aktif punya omzet > 0 tapi tidak ada jurnal POS POSTED untuk no_invoice ini'
    ) as obj
    from public.sales s
    where coalesce(s.total_harga, 0) > 0
      and coalesce(s.no_invoice, '') <> ''
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
      and (v_toko is null or upper(s.toko_id) = v_toko)
      and not exists (
        select 1 from public.journal_entries je
        where je.status = 'POSTED'
          and je.sumber = 'POS'
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
    'definition', 'Sale total_harga>0, status bukan BATAL/VOID/CANCEL, wajib punya journal_entries(sumber=POS, referensi_id=no_invoice, status=POSTED).',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C3 CRITICAL: sale BATAL/VOID/CANCEL masih punya jurnal POS POSTED
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'sale_id', s.id,
      'entry_id', je.id,
      'status', s.status_pembayaran,
      'detail', 'Sale sudah BATAL/VOID/CANCEL tetapi jurnal POS masih POSTED (harusnya di-void)'
    ) as obj
    from public.sales s
    join public.journal_entries je
      on je.sumber = 'POS'
     and je.referensi_id = s.no_invoice
     and je.status = 'POSTED'
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
    'definition', 'Jika status_pembayaran BATAL/VOID/CANCEL, tidak boleh tersisa journal POS berstatus POSTED.',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C4 HIGH: identitas POS rusak (kas+piutang ≠ penjualan+ppn)
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    select jsonb_build_object(
      'toko_id', je.toko_id,
      'ref', je.referensi_id,
      'entry_id', je.id,
      'asset_side', a.asset_side,
      'revenue_side', a.rev_side,
      'detail', format(
        'Identitas POS rusak: Kas/Bank/Piutang=%s vs Penjualan+PPN=%s',
        a.asset_side, a.rev_side)
    ) as obj
    from public.journal_entries je
    join lateral (
      select
        coalesce(sum(case when jl.akun_kode in ('1101','1102','1103') then jl.debit - jl.kredit else 0 end),0)::bigint as asset_side,
        coalesce(sum(case when jl.akun_kode in ('4100','2102') then jl.kredit - jl.debit else 0 end),0)::bigint as rev_side
      from public.journal_lines jl
      where jl.entry_id = je.id
    ) a on true
    where je.status = 'POSTED'
      and je.sumber = 'POS'
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
    'definition', 'Untuk sumber POS: net (1101+1102+1103) harus = net kredit (4100+2102).',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C5 HIGH: FT CLOSE-* APPROVED tanpa jurnal CLOSING
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    select jsonb_build_object(
      'toko_id', ft.toko_id,
      'ref', coalesce(nullif(btrim(ft.referensi_id), ''), 'FT-' || ft.id::text),
      'ft_id', ft.id,
      'nominal', ft.nominal,
      'tanggal', coalesce(ft.tanggal_transaksi, (ft.created_at at time zone 'Asia/Jakarta')::date),
      'detail', 'Finance closing APPROVED belum punya jurnal CLOSING POSTED dengan referensi yang sama'
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
        where je.status = 'POSTED'
          and je.sumber = 'CLOSING'
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
    'definition', 'FT APPROVED bertanda CLOSE/PENUTUPAN/CLOSING wajib punya journal CLOSING POSTED dengan referensi_id yang sama.',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C6 HIGH: FT manual APPROVED (bukan POS/CLOSE/SETTLE) tanpa jurnal MANUAL
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    select jsonb_build_object(
      'toko_id', ft.toko_id,
      'ref', 'FT-' || ft.id::text,
      'ft_id', ft.id,
      'jenis', ft.jenis_transaksi,
      'kategori', ft.kategori,
      'nominal', ft.nominal,
      'detail', 'FT manual APPROVED belum punya jurnal MANUAL FT-{id}'
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
      -- exclude omzet POS murni (referensi invoice/sale id)
      and (
        ft.referensi_id is null
        or btrim(ft.referensi_id) = ''
        or upper(ft.referensi_id) like 'FT-%'
      )
      and (v_toko is null or upper(ft.toko_id) = v_toko)
      and not exists (
        select 1 from public.journal_entries je
        where je.status = 'POSTED'
          and je.sumber = 'MANUAL'
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
    'definition', 'FT APPROVED jenis PEMASUKAN/PENGELUARAN/PIUTANG/HUTANG (bukan CLOSE/SETTLE/omzet POS) wajib punya journal MANUAL referensi FT-{id}.',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C7 HIGH: piutang masih terbuka di POS (ada Dr 1103) + sale sisa=0
  --         tapi belum ada SETTLE untuk invoice → AR menggantung di GL
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    select jsonb_build_object(
      'toko_id', s.toko_id,
      'ref', s.no_invoice,
      'sale_id', s.id,
      'ar_pos', a.ar,
      'sisa_sales', coalesce(s.sisa_tagihan, 0),
      'detail', 'POS masih punya debit piutang, sale sudah lunas (sisa=0), tapi belum ada jurnal SETTLE untuk invoice ini'
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
        where j2.status = 'POSTED'
          and j2.sumber = 'SETTLE'
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
    'definition', 'Sale sisa_tagihan=0 dan POS punya debit 1103>0 wajib punya minimal satu jurnal SETTLE POSTED untuk invoice yang sama.',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C8 MEDIUM: rekonsiliasi AR — saldo GL 1103 vs sum sisa_tagihan sales
  -- (hanya flag jika beda absolut > 0; bukti kedua sisi disertakan)
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    with gl as (
      select je.toko_id,
             coalesce(sum(jl.debit - jl.kredit),0)::bigint as gl_ar
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED'
        and jl.akun_kode = '1103'
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
      select toko_id from gl
      union
      select toko_id from ss
    )
    select jsonb_build_object(
      'toko_id', k.toko_id,
      'ref', k.toko_id,
      'gl_ar', coalesce(g.gl_ar, 0),
      'sales_sisa', coalesce(s.sales_sisa, 0),
      'selisih', coalesce(g.gl_ar, 0) - coalesce(s.sales_sisa, 0),
      'detail', format(
        'Saldo piutang GL 1103 (%s) ≠ total sisa_tagihan sales aktif (%s)',
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
    'definition', 'Per toko: sum(debit-kredit) akun 1103 pada jurnal POSTED harus = sum(sisa_tagihan) sales aktif (sisa>0, bukan batal).',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C9 MEDIUM: baris jurnal ke akun tidak postable / tidak aktif / hilang
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    select jsonb_build_object(
      'toko_id', je.toko_id,
      'ref', coalesce(je.referensi_id, je.id::text),
      'entry_id', je.id,
      'akun_kode', jl.akun_kode,
      'detail', case
        when c.kode is null then 'Akun tidak ada di chart_of_accounts'
        when not c.aktif then 'Akun nonaktif dipakai di jurnal POSTED'
        when not c.is_postable then 'Akun header/non-postable dipakai di jurnal POSTED'
        else 'Akun tidak valid'
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
    'definition', 'Setiap journal_lines pada entry POSTED harus ke akun yang ada, aktif, dan is_postable=true.',
    'findings', v_findings
  ));

  -- -------------------------------------------------------------------------
  -- C10: settle berlebih (HIGH) atau multi-settle bertahap (INFO)
  --    Flag jika: (a) total kredit 1103 SETTLE > AR POS, ATAU
  --               (b) lebih dari satu SETTLE per invoice (review)
  -- -------------------------------------------------------------------------
  select coalesce(jsonb_agg(x.obj), '[]'::jsonb), count(*)
  into v_findings, v_count
  from (
    with settle as (
      select
        public.gl_extract_settle_invoice(je.referensi_id) as inv,
        je.toko_id,
        count(*)::int as n_settle,
        coalesce(sum(case when jl.akun_kode='1103' then jl.kredit else 0 end),0)::bigint as settle_cr
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      where je.status = 'POSTED'
        and je.sumber = 'SETTLE'
        and (v_toko is null or je.toko_id = v_toko)
        and public.gl_extract_settle_invoice(je.referensi_id) is not null
      group by 1, 2
    ),
    enriched as (
      select
        st.inv,
        st.toko_id,
        st.n_settle,
        st.settle_cr,
        coalesce(ar.ar_pos, 0)::bigint as ar_pos
      from settle st
      left join lateral (
        select coalesce(sum(jl.debit - jl.kredit),0)::bigint as ar_pos
        from public.journal_entries je
        join public.journal_lines jl on jl.entry_id = je.id
        where je.status = 'POSTED' and je.sumber = 'POS'
          and je.referensi_id = st.inv
          and jl.akun_kode = '1103'
      ) ar on true
      where st.settle_cr > coalesce(ar.ar_pos, 0)
         or st.n_settle > 1
    )
    select jsonb_build_object(
      'toko_id', e.toko_id,
      'ref', e.inv,
      'n_settle', e.n_settle,
      'settle_cr_1103', e.settle_cr,
      'ar_pos', e.ar_pos,
      'detail', case
        when e.settle_cr > e.ar_pos
          then format('Settle berlebih: kredit piutang settle=%s > AR POS=%s (%s jurnal SETTLE)', e.settle_cr, e.ar_pos, e.n_settle)
        else format('Ada %s jurnal SETTLE untuk invoice yang sama (total kredit 1103=%s, AR POS=%s) — verifikasi pelunasan bertahap', e.n_settle, e.settle_cr, e.ar_pos)
      end,
      'over_settled', e.settle_cr > e.ar_pos
    ) as obj
    from enriched e
    order by (e.settle_cr > e.ar_pos) desc, e.n_settle desc
    limit v_lim
  ) x;

  v_count := jsonb_array_length(coalesce(v_findings, '[]'::jsonb));
  v_passed := v_count = 0;
  select exists (
    select 1 from jsonb_array_elements(coalesce(v_findings, '[]'::jsonb)) e
    where coalesce((e->>'over_settled')::boolean, false)
  ) into v_over_settle;

  if v_over_settle then
    v_high := v_high + 1;
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'id', 'SETTLE_MULTI_OR_OVER',
      'title', 'Settle ganda / berlebih per invoice',
      'severity', 'HIGH',
      'passed', false,
      'count', v_count,
      'definition', 'Jika ada >1 SETTLE per invoice: sah bila bertahap dan total kredit 1103 ≤ AR POS. FATAL bila total settle > AR POS.',
      'findings', v_findings
    ));
  else
    if not v_passed then v_info := v_info + 1; end if;
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'id', 'SETTLE_MULTI_OR_OVER',
      'title', 'Settle ganda / berlebih per invoice',
      'severity', 'INFO',
      'passed', v_passed,
      'count', v_count,
      'definition', 'Jika ada >1 SETTLE per invoice: sah bila bertahap dan total kredit 1103 ≤ AR POS. FATAL bila total settle > AR POS.',
      'findings', v_findings
    ));
  end if;

  -- -------------------------------------------------------------------------
  -- C11 INFO: coverage ringkas
  -- -------------------------------------------------------------------------
  select count(*) into v_sales
  from public.sales s
  where coalesce(s.total_harga,0) > 0
    and coalesce(s.no_invoice,'') <> ''
    and upper(coalesce(s.status_pembayaran,'')) not in ('BATAL','VOID','CANCEL')
    and (v_toko is null or upper(s.toko_id) = v_toko);

  select count(*) into v_pos
  from public.journal_entries je
  where je.status = 'POSTED' and je.sumber = 'POS'
    and (v_toko is null or je.toko_id = v_toko);

  select count(*) into v_je
  from public.journal_entries je
  where je.status = 'POSTED'
    and (v_toko is null or je.toko_id = v_toko);

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'id', 'COVERAGE_STATS',
    'title', 'Statistik cakupan GL',
    'severity', 'INFO',
    'passed', true,
    'count', 0,
    'definition', 'Ringkasan jumlah sale aktif, jurnal POS, dan seluruh jurnal POSTED pada scope audit.',
    'findings', jsonb_build_array(jsonb_build_object(
      'toko_id', coalesce(v_toko, 'ALL'),
      'ref', 'COVERAGE',
      'sales_aktif', v_sales,
      'pos_journals', v_pos,
      'posted_journals', v_je,
      'toko_distinct_sales', v_toko_n,
      'detail', format(
        'Sale aktif=%s · Jurnal POS=%s · Semua jurnal POSTED=%s · Toko (dari sales)=%s',
        v_sales, v_pos, v_je, v_toko_n)
    ))
  ));
  v_info := v_info + 1;

  return jsonb_build_object(
    'generated_at', now(),
    'scope_toko', coalesce(v_toko, 'ALL'),
    'summary', jsonb_build_object(
      'critical_failed', v_crit,
      'high_failed', v_high,
      'medium_failed', v_med,
      'info_checks', v_info,
      'checks_run', jsonb_array_length(v_checks),
      'all_clear', (v_crit = 0 and v_high = 0 and v_med = 0)
    ),
    'checks', v_checks
  );
end;
$$;

grant execute on function public.gl_run_full_audit(text, int) to authenticated;
