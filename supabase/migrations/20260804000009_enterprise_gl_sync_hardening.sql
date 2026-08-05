-- =============================================================================
-- Enterprise GL sync hardening — tutup celah E2E
-- 1) Settle single-writer (trigger deterministik; FT settle tidak double-post)
-- 2) Finance backfill cursor maju (exclude already-done / POS skip)
-- 3) Trigger finance APPROVED → CLOSING/MANUAL
-- 4) Void POS/SETTLE saat sale delete / BATAL
-- 5) Harden void_journal_entry (ACL + tanggal asli)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function public.gl_extract_settle_invoice(p_ref text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      regexp_replace(coalesce(p_ref, ''), '^SETTLE-', '', 'i'),
      '-(O[0-9]+-N[0-9]+|[0-9]{10,})$',
      ''
    ),
    ''
  );
$$;

create or replace function public.gl_void_by_sumber_ref(
  p_sumber text,
  p_referensi_id text,
  p_created_by text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_n int := 0;
begin
  if coalesce(p_referensi_id, '') = '' then
    return 0;
  end if;
  for r in
    select je.id
    from public.journal_entries je
    where je.status = 'POSTED'
      and je.sumber = upper(p_sumber)
      and je.referensi_id = p_referensi_id
  loop
    begin
      perform public.void_journal_entry(r.id, p_created_by);
      v_n := v_n + 1;
    exception when others then
      raise warning 'gl_void_by_sumber_ref % %: %', p_sumber, r.id, SQLERRM;
    end;
  end loop;
  return v_n;
end;
$$;

create or replace function public.gl_void_sale_journals(
  p_no_invoice text,
  p_created_by text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_n int := 0;
  v_inv text := nullif(btrim(coalesce(p_no_invoice, '')), '');
begin
  if v_inv is null then
    return 0;
  end if;

  -- POS by invoice
  v_n := v_n + public.gl_void_by_sumber_ref('POS', v_inv, p_created_by);

  -- Semua SETTLE untuk invoice ini (trigger + FT historis)
  for r in
    select je.id
    from public.journal_entries je
    where je.status = 'POSTED'
      and je.sumber = 'SETTLE'
      and (
        je.referensi_id = v_inv
        or je.referensi_id ilike 'SETTLE-' || v_inv || '-%'
        or public.gl_extract_settle_invoice(je.referensi_id) = v_inv
      )
  loop
    begin
      perform public.void_journal_entry(r.id, p_created_by);
      v_n := v_n + 1;
    exception when others then
      raise warning 'gl_void_sale_journals settle %: %', r.id, SQLERRM;
    end;
  end loop;

  return v_n;
end;
$$;

-- -----------------------------------------------------------------------------
-- Harden void: ACL toko + reverse di tanggal jurnal asli
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
  if not public.gl_can_access_toko(v_je.toko_id) then
    raise exception 'Tidak berhak void jurnal toko %', v_je.toko_id;
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

  if jsonb_array_length(v_lines) < 2 then
    raise exception 'Jurnal kosong / tidak bisa di-void';
  end if;

  v_ref := 'VOID-' || p_entry_id::text;
  v_reverse_id := public.post_journal_balanced(
    v_je.toko_id,
    v_je.tanggal, -- periode yang sama dengan jurnal asli
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
-- Settle trigger: referensi deterministik (anti double dengan FT)
-- -----------------------------------------------------------------------------
create or replace function public.gl_trg_sales_au_settle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_sisa bigint := coalesce(old.sisa_tagihan, 0);
  v_new_sisa bigint := coalesce(new.sisa_tagihan, 0);
  v_collect bigint;
  v_asset text;
  v_ref text;
  v_inv text;
begin
  if v_new_sisa >= v_old_sisa then
    return new;
  end if;
  v_collect := v_old_sisa - v_new_sisa;
  if v_collect <= 0 then
    return new;
  end if;

  v_inv := coalesce(nullif(btrim(new.no_invoice), ''), new.id::text);
  v_asset := case
    when upper(coalesce(new.metode_pembayaran, 'CASH')) in ('CASH', 'TUNAI', '') then '1101'
    else '1102'
  end;
  -- Deterministik: idempotent bila trigger/retry ulang
  v_ref := 'SETTLE-' || v_inv || '-O' || v_old_sisa::text || '-N' || v_new_sisa::text;

  begin
    perform public.post_journal_balanced(
      upper(new.toko_id),
      (timezone('Asia/Jakarta', now()))::date,
      'SETTLE',
      v_ref,
      'Pelunasan piutang ' || v_inv,
      jsonb_build_array(
        jsonb_build_object('akun_kode', v_asset, 'debit', v_collect, 'kredit', 0, 'memo', 'Settle'),
        jsonb_build_object('akun_kode', '1103', 'debit', 0, 'kredit', v_collect, 'memo', 'Settle')
      ),
      coalesce(new.nama_kasir, 'SYSTEM')
    );
  exception when others then
    raise warning 'gl settle failed for %: %', v_inv, SQLERRM;
  end;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Sale delete / BATAL → void POS + SETTLE
-- -----------------------------------------------------------------------------
create or replace function public.gl_trg_sales_void_cleanup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv text;
  v_old_status text;
  v_new_status text;
begin
  if tg_op = 'DELETE' then
    v_inv := coalesce(nullif(btrim(old.no_invoice), ''), old.id::text);
    perform public.gl_void_sale_journals(v_inv, coalesce(old.nama_kasir, 'SYSTEM'));
    return old;
  end if;

  v_old_status := upper(coalesce(old.status_pembayaran, ''));
  v_new_status := upper(coalesce(new.status_pembayaran, ''));
  if v_new_status in ('BATAL', 'VOID', 'CANCEL') and v_old_status is distinct from v_new_status then
    v_inv := coalesce(nullif(btrim(new.no_invoice), ''), new.id::text);
    perform public.gl_void_sale_journals(v_inv, coalesce(new.nama_kasir, 'SYSTEM'));
  end if;
  return new;
exception when others then
  raise warning 'gl_trg_sales_void_cleanup: %', SQLERRM;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_gl_sales_ad_void on public.sales;
create trigger trg_gl_sales_ad_void
  before delete on public.sales
  for each row
  execute function public.gl_trg_sales_void_cleanup();

drop trigger if exists trg_gl_sales_au_batal on public.sales;
create trigger trg_gl_sales_au_batal
  after update of status_pembayaran on public.sales
  for each row
  when (
    upper(coalesce(new.status_pembayaran, '')) in ('BATAL', 'VOID', 'CANCEL')
    and upper(coalesce(old.status_pembayaran, ''))
        is distinct from upper(coalesce(new.status_pembayaran, ''))
  )
  execute function public.gl_trg_sales_void_cleanup();

-- -----------------------------------------------------------------------------
-- Shared finance row poster (CLOSING / MANUAL; SETTLE owned by sales trigger)
-- -----------------------------------------------------------------------------
create or replace function public.gl_post_finance_row(
  p_ft public.finance_transactions,
  p_created_by text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text;
  v_asset text;
  v_lines jsonb;
  v_jenis text;
  v_nom bigint;
  v_is_close boolean;
  v_is_settle boolean;
  v_id uuid;
  v_tgl date;
begin
  if upper(coalesce(p_ft.status_konfirmasi, '')) <> 'APPROVED' then
    return null;
  end if;
  v_nom := coalesce(p_ft.nominal, 0);
  if v_nom <= 0 then
    return null;
  end if;

  v_ref := coalesce(nullif(btrim(p_ft.referensi_id), ''), 'FT-' || p_ft.id::text);
  v_is_close := upper(v_ref) like 'CLOSE-%'
    or upper(coalesce(p_ft.kategori, '')) like '%PENUTUPAN%'
    or upper(coalesce(p_ft.kategori, '')) like '%CLOSING%';
  v_is_settle := upper(v_ref) like 'SETTLE-%'
    or upper(coalesce(p_ft.kategori, '')) like '%PELUNASAN%';

  -- Omzet POS murni: jangan post dari FT
  if not v_is_close and not v_is_settle
     and p_ft.referensi_id is not null and btrim(p_ft.referensi_id) <> ''
     and upper(p_ft.referensi_id) not like 'CLOSE-%'
     and upper(p_ft.referensi_id) not like 'FT-%'
     and upper(p_ft.referensi_id) not like 'SETTLE-%' then
    return null;
  end if;

  -- SETTLE live: single-writer = sales.sisa_tagihan trigger (bukan FT).
  if v_is_settle then
    return null;
  end if;

  if v_is_close and exists (
    select 1 from public.journal_entries je
    where je.status = 'POSTED' and je.sumber = 'CLOSING' and je.referensi_id = v_ref
  ) then
    return null;
  end if;

  if not v_is_close and exists (
    select 1 from public.journal_entries je
    where je.status = 'POSTED' and je.sumber = 'MANUAL'
      and je.referensi_id = 'FT-' || p_ft.id::text
  ) then
    return null;
  end if;

  v_jenis := upper(coalesce(p_ft.jenis_transaksi, ''));
  v_asset := case
    when upper(coalesce(p_ft.metode_pembayaran, 'CASH')) in ('CASH', 'TUNAI', '') then '1101'
    else '1102'
  end;
  v_tgl := coalesce(
    p_ft.tanggal_transaksi,
    (p_ft.created_at at time zone 'Asia/Jakarta')::date
  );

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
    v_id := public.post_journal_balanced(
      upper(p_ft.toko_id), v_tgl, 'CLOSING', v_ref,
      coalesce(p_ft.deskripsi, 'Closing'), v_lines, p_created_by
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
      return null;
    end if;
    v_id := public.post_journal_balanced(
      upper(p_ft.toko_id), v_tgl, 'MANUAL', 'FT-' || p_ft.id::text,
      coalesce(p_ft.deskripsi, p_ft.kategori), v_lines, p_created_by
    );
  end if;

  return v_id;
exception when others then
  raise warning 'gl_post_finance_row failed %: %', p_ft.id, SQLERRM;
  return null;
end;
$$;

-- Historis: post SETTLE dari FT hanya jika POS masih punya AR dan belum ada SETTLE
create or replace function public.gl_post_settle_ft_historical(
  p_ft public.finance_transactions,
  p_created_by text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text;
  v_inv text;
  v_nom bigint;
  v_asset text;
  v_tgl date;
  v_ar bigint;
  v_settle bigint;
begin
  if upper(coalesce(p_ft.status_konfirmasi, '')) <> 'APPROVED' then
    return null;
  end if;
  v_ref := coalesce(nullif(btrim(p_ft.referensi_id), ''), '');
  if upper(v_ref) not like 'SETTLE-%'
     and upper(coalesce(p_ft.kategori, '')) not like '%PELUNASAN%' then
    return null;
  end if;
  v_nom := coalesce(p_ft.nominal, 0);
  if v_nom <= 0 then
    return null;
  end if;
  v_inv := public.gl_extract_settle_invoice(v_ref);
  if v_inv is null then
    return null;
  end if;

  -- Sudah ada settle untuk invoice ini
  if exists (
    select 1 from public.journal_entries je
    where je.status = 'POSTED' and je.sumber = 'SETTLE'
      and (
        je.referensi_id = v_ref
        or public.gl_extract_settle_invoice(je.referensi_id) = v_inv
      )
  ) then
    return null;
  end if;

  -- Hitung AR bersih di jurnal POS invoice
  select coalesce(sum(jl.debit - jl.kredit), 0) into v_ar
  from public.journal_entries je
  join public.journal_lines jl on jl.entry_id = je.id
  where je.status = 'POSTED' and je.sumber = 'POS' and je.referensi_id = v_inv
    and jl.akun_kode = '1103';

  if coalesce(v_ar, 0) <= 0 then
    return null; -- tidak ada piutang di POS (full cash / belum di-backfill)
  end if;

  select coalesce(sum(jl.kredit - jl.debit), 0) into v_settle
  from public.journal_entries je
  join public.journal_lines jl on jl.entry_id = je.id
  where je.status = 'POSTED' and je.sumber = 'SETTLE'
    and public.gl_extract_settle_invoice(je.referensi_id) = v_inv
    and jl.akun_kode = '1103';

  if coalesce(v_settle, 0) >= v_ar then
    return null;
  end if;

  v_asset := case
    when upper(coalesce(p_ft.metode_pembayaran, 'CASH')) in ('CASH', 'TUNAI', '') then '1101'
    else '1102'
  end;
  v_tgl := coalesce(
    p_ft.tanggal_transaksi,
    (p_ft.created_at at time zone 'Asia/Jakarta')::date
  );

  return public.post_journal_balanced(
    upper(p_ft.toko_id), v_tgl, 'SETTLE', v_ref,
    coalesce(p_ft.deskripsi, 'Pelunasan historis ' || v_inv),
    jsonb_build_array(
      jsonb_build_object('akun_kode', v_asset, 'debit', v_nom, 'kredit', 0, 'memo', 'Settle'),
      jsonb_build_object('akun_kode', '1103', 'debit', 0, 'kredit', v_nom, 'memo', 'Settle')
    ),
    p_created_by
  );
exception when others then
  raise warning 'gl_post_settle_ft_historical %: %', p_ft.id, SQLERRM;
  return null;
end;
$$;

-- Trigger finance: insert APPROVED + update → APPROVED
create or replace function public.gl_trg_finance_ai_au()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if upper(coalesce(new.status_konfirmasi, '')) = 'APPROVED' then
      perform public.gl_post_finance_row(new, coalesce(new.nama_kasir, 'SYSTEM'));
    end if;
    return new;
  end if;

  if upper(coalesce(new.status_konfirmasi, '')) = 'APPROVED'
     and upper(coalesce(old.status_konfirmasi, '')) is distinct from 'APPROVED' then
    perform public.gl_post_finance_row(new, coalesce(new.nama_kasir, 'SYSTEM'));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_gl_finance_ai on public.finance_transactions;
create trigger trg_gl_finance_ai
  after insert on public.finance_transactions
  for each row
  execute function public.gl_trg_finance_ai_au();

drop trigger if exists trg_gl_finance_au_approve on public.finance_transactions;
create trigger trg_gl_finance_au_approve
  after update of status_konfirmasi on public.finance_transactions
  for each row
  execute function public.gl_trg_finance_ai_au();

-- Void GL saat FT dihapus (CLOSE / SETTLE / MANUAL)
create or replace function public.gl_trg_finance_ad_void()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text;
  v_is_close boolean;
  v_is_settle boolean;
begin
  v_ref := coalesce(nullif(btrim(old.referensi_id), ''), 'FT-' || old.id::text);
  v_is_close := upper(v_ref) like 'CLOSE-%'
    or upper(coalesce(old.kategori, '')) like '%PENUTUPAN%'
    or upper(coalesce(old.kategori, '')) like '%CLOSING%';
  v_is_settle := upper(v_ref) like 'SETTLE-%'
    or upper(coalesce(old.kategori, '')) like '%PELUNASAN%';

  begin
    if v_is_close then
      perform public.gl_void_by_sumber_ref('CLOSING', v_ref, coalesce(old.nama_kasir, 'SYSTEM'));
    elsif v_is_settle then
      -- Jangan void settle trigger-deterministik hanya karena FT dihapus:
      -- void hanya jurnal dengan ref FT yang sama (historis FT-posted).
      perform public.gl_void_by_sumber_ref('SETTLE', v_ref, coalesce(old.nama_kasir, 'SYSTEM'));
    else
      perform public.gl_void_by_sumber_ref(
        'MANUAL', 'FT-' || old.id::text, coalesce(old.nama_kasir, 'SYSTEM'));
    end if;
  exception when others then
    raise warning 'gl_trg_finance_ad_void: %', SQLERRM;
  end;
  return old;
end;
$$;

drop trigger if exists trg_gl_finance_ad_void on public.finance_transactions;
create trigger trg_gl_finance_ad_void
  before delete on public.finance_transactions
  for each row
  execute function public.gl_trg_finance_ad_void();

-- -----------------------------------------------------------------------------
-- Backfill finance: hanya kandidat yang belum selesai (cursor maju)
-- -----------------------------------------------------------------------------
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
  v_id uuid;
  v_is_settle boolean;
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
      -- exclude POS omzet murni (bukan CLOSE/SETTLE/FT-)
      and not (
        ft.referensi_id is not null
        and btrim(ft.referensi_id) <> ''
        and upper(ft.referensi_id) not like 'CLOSE-%'
        and upper(ft.referensi_id) not like 'SETTLE-%'
        and upper(ft.referensi_id) not like 'FT-%'
        and upper(coalesce(ft.kategori, '')) not like '%PENUTUPAN%'
        and upper(coalesce(ft.kategori, '')) not like '%CLOSING%'
        and upper(coalesce(ft.kategori, '')) not like '%PELUNASAN%'
      )
      -- exclude CLOSING/MANUAL yang sudah journaled
      and not exists (
        select 1
        from public.journal_entries je
        where je.status = 'POSTED'
          and (
            (
              (upper(coalesce(ft.referensi_id, '')) like 'CLOSE-%'
                or upper(coalesce(ft.kategori, '')) like '%PENUTUPAN%'
                or upper(coalesce(ft.kategori, '')) like '%CLOSING%')
              and je.sumber = 'CLOSING'
              and je.referensi_id = coalesce(nullif(btrim(ft.referensi_id), ''), 'FT-' || ft.id::text)
            )
            or (
              not (
                upper(coalesce(ft.referensi_id, '')) like 'CLOSE-%'
                or upper(coalesce(ft.referensi_id, '')) like 'SETTLE-%'
                or upper(coalesce(ft.kategori, '')) like '%PENUTUPAN%'
                or upper(coalesce(ft.kategori, '')) like '%CLOSING%'
                or upper(coalesce(ft.kategori, '')) like '%PELUNASAN%'
              )
              and je.sumber = 'MANUAL'
              and je.referensi_id = 'FT-' || ft.id::text
            )
          )
      )
      -- SETTLE: hanya kandidat historis yang masih butuh (POS punya AR, belum ada SETTLE)
      and (
        not (
          upper(coalesce(ft.referensi_id, '')) like 'SETTLE-%'
          or upper(coalesce(ft.kategori, '')) like '%PELUNASAN%'
        )
        or (
          public.gl_extract_settle_invoice(coalesce(ft.referensi_id, '')) is not null
          and exists (
            select 1
            from public.journal_entries je
            join public.journal_lines jl on jl.entry_id = je.id
            where je.status = 'POSTED' and je.sumber = 'POS'
              and je.referensi_id = public.gl_extract_settle_invoice(ft.referensi_id)
              and jl.akun_kode = '1103' and jl.debit > 0
          )
          and not exists (
            select 1 from public.journal_entries je
            where je.status = 'POSTED' and je.sumber = 'SETTLE'
              and (
                je.referensi_id = coalesce(nullif(btrim(ft.referensi_id), ''), '')
                or public.gl_extract_settle_invoice(je.referensi_id)
                   = public.gl_extract_settle_invoice(coalesce(ft.referensi_id, ''))
              )
          )
        )
      )
      -- MANUAL: hanya jenis yang bisa di-map
      and (
        upper(coalesce(ft.referensi_id, '')) like 'CLOSE-%'
        or upper(coalesce(ft.referensi_id, '')) like 'SETTLE-%'
        or upper(coalesce(ft.kategori, '')) like '%PENUTUPAN%'
        or upper(coalesce(ft.kategori, '')) like '%CLOSING%'
        or upper(coalesce(ft.kategori, '')) like '%PELUNASAN%'
        or upper(coalesce(ft.jenis_transaksi, '')) in (
          'PEMASUKAN', 'PENGELUARAN', 'PIUTANG', 'HUTANG'
        )
      )
    order by coalesce(ft.tanggal_transaksi, ft.created_at::date), ft.id
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
  loop
    begin
      v_is_settle := upper(coalesce(r.referensi_id, '')) like 'SETTLE-%'
        or upper(coalesce(r.kategori, '')) like '%PELUNASAN%';
      if v_is_settle then
        v_id := public.gl_post_settle_ft_historical(r, p_created_by);
      else
        v_id := public.gl_post_finance_row(r, p_created_by);
      end if;
      if v_id is null then
        v_skipped := v_skipped + 1;
      else
        v_posted := v_posted + 1;
      end if;
    exception when others then
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'posted', v_posted,
    'skipped', v_skipped,
    'failed', v_failed,
    'done', (v_posted = 0 and v_skipped = 0 and v_failed = 0)
  );
end;
$$;

-- Sales backfill: skip BATAL + pakai gl_post_sale_row
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
  v_id uuid;
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
      and upper(coalesce(s.status_pembayaran, '')) not in ('BATAL', 'VOID', 'CANCEL')
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
      v_id := public.gl_post_sale_row(r);
      if v_id is null then
        v_skipped := v_skipped + 1;
      else
        v_posted := v_posted + 1;
      end if;
    exception when others then
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'posted', v_posted,
    'skipped', v_skipped,
    'failed', v_failed,
    'done', (v_posted = 0 and v_skipped = 0 and v_failed = 0)
  );
end;
$$;

grant execute on function public.gl_extract_settle_invoice(text) to authenticated;
grant execute on function public.gl_void_by_sumber_ref(text, text, text) to authenticated;
grant execute on function public.gl_void_sale_journals(text, text) to authenticated;
grant execute on function public.gl_post_finance_row(public.finance_transactions, text) to authenticated;
grant execute on function public.gl_post_settle_ft_historical(public.finance_transactions, text) to authenticated;
grant execute on function public.void_journal_entry(uuid, text) to authenticated;
grant execute on function public.gl_backfill_finance_batch(text, int, text) to authenticated;
grant execute on function public.gl_backfill_sales_batch(text, int, text) to authenticated;
