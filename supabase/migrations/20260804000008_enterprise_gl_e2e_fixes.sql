-- E2E fixes for GL scale-600: trial balance join bug, RLS hole,
-- posting access check, auto-post trigger on sales, AR settlement helper.

-- =============================================================================
-- 1. Fix access helper (jangan buka semua jika profil toko kosong)
-- =============================================================================
create or replace function public.gl_can_access_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    auth.uid() is null -- service/trigger context
    or public.gl_is_owner_or_pusat()
    or (
      public.gl_current_toko() <> ''
      and upper(coalesce(p_toko, '')) = public.gl_current_toko()
    );
$$;

-- =============================================================================
-- 2. Fix trial balance (jangan hitung line dari periode lain)
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
  if auth.uid() is not null then
    if v_toko is not null and not public.gl_can_access_toko(v_toko) then
      raise exception 'Tidak berhak akses toko %', v_toko;
    end if;
    if v_toko is null and not public.gl_is_owner_or_pusat() then
      v_toko := nullif(public.gl_current_toko(), '');
      if v_toko is null then
        raise exception 'Profil toko tidak ditemukan';
      end if;
    end if;
  end if;

  return query
  select
    c.kode,
    c.nama,
    c.tipe,
    c.normal_balance,
    coalesce(sum(jl.debit), 0)::bigint as debit,
    coalesce(sum(jl.kredit), 0)::bigint as kredit
  from public.journal_entries je
  join public.journal_lines jl on jl.entry_id = je.id
  join public.chart_of_accounts c on c.kode = jl.akun_kode
  where je.status = 'POSTED'
    and je.tanggal between v_start and v_end
    and (v_toko is null or je.toko_id = v_toko)
    and c.is_postable
    and c.aktif
  group by c.kode, c.nama, c.tipe, c.normal_balance
  having coalesce(sum(jl.debit), 0) <> 0 or coalesce(sum(jl.kredit), 0) <> 0
  order by c.kode;
end;
$$;

-- =============================================================================
-- 3. Harden post_journal_balanced — cek akses toko
-- =============================================================================
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
  v_toko text := upper(btrim(coalesce(p_toko_id, '')));
begin
  if v_toko = '' then
    raise exception 'toko_id wajib diisi';
  end if;
  -- Service/trigger (auth.uid null) atau user berhak.
  if auth.uid() is not null and not public.gl_can_access_toko(v_toko) then
    raise exception 'Tidak berhak posting ke toko %', v_toko;
  end if;
  if p_tanggal is null then
    raise exception 'tanggal wajib diisi';
  end if;
  if p_sumber is null or p_sumber not in ('POS', 'CLOSING', 'MANUAL', 'SYSTEM', 'REVERSE', 'SETTLE') then
    raise exception 'sumber tidak valid: %', p_sumber;
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'minimal 2 baris jurnal';
  end if;

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
    v_toko, p_tanggal, v_periode_id, p_sumber,
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

-- Allow SETTLE in journal_entries check (recreate constraint if needed)
alter table public.journal_entries drop constraint if exists journal_entries_sumber_check;
alter table public.journal_entries
  add constraint journal_entries_sumber_check
  check (sumber in ('POS', 'CLOSING', 'MANUAL', 'SYSTEM', 'REVERSE', 'SETTLE'));

-- =============================================================================
-- 4. Auto-post GL when sales row created (covers online/member + POS race)
-- =============================================================================
create or replace function public.gl_post_sale_row(p_sale public.sales)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total bigint;
  v_sisa bigint;
  v_bayar bigint;
  v_dpp bigint;
  v_ppn bigint;
  v_asset text;
  v_lines jsonb := '[]'::jsonb;
  v_gap bigint;
  v_id uuid;
begin
  if coalesce(p_sale.no_invoice, '') = '' then
    return null;
  end if;
  v_total := coalesce(p_sale.total_harga, 0);
  if v_total <= 0 then
    return null;
  end if;

  v_sisa := greatest(coalesce(p_sale.sisa_tagihan, 0), 0);
  v_bayar := greatest(v_total - v_sisa, 0);
  v_dpp := round(v_total / 1.11)::bigint;
  v_ppn := v_total - v_dpp;
  v_asset := case
    when upper(coalesce(p_sale.metode_pembayaran, 'CASH')) in ('CASH', 'TUNAI', '') then '1101'
    else '1102'
  end;

  if v_bayar > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'akun_kode', v_asset, 'debit', v_bayar, 'kredit', 0, 'memo', p_sale.no_invoice
    ));
  end if;
  if v_sisa > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'akun_kode', '1103', 'debit', v_sisa, 'kredit', 0, 'memo', p_sale.no_invoice
    ));
  end if;
  if v_dpp > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'akun_kode', '4100', 'debit', 0, 'kredit', v_dpp, 'memo', p_sale.no_invoice
    ));
  end if;
  if v_ppn > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'akun_kode', '2102', 'debit', 0, 'kredit', v_ppn, 'memo', p_sale.no_invoice
    ));
  end if;

  select coalesce(sum((x->>'debit')::bigint),0) - coalesce(sum((x->>'kredit')::bigint),0)
  into v_gap from jsonb_array_elements(v_lines) x;

  if v_gap <> 0 then
    v_lines := (
      select jsonb_agg(
        case
          when e->>'akun_kode' = '4100' then
            jsonb_set(e, '{kredit}', to_jsonb(greatest(((e->>'kredit')::bigint - v_gap), 0)))
          else e
        end
      )
      from jsonb_array_elements(v_lines) e
    );
  end if;

  if jsonb_array_length(v_lines) < 2 then
    return null;
  end if;

  v_id := public.post_journal_balanced(
    upper(p_sale.toko_id),
    (coalesce(p_sale.created_at, now()) at time zone 'Asia/Jakarta')::date,
    'POS',
    p_sale.no_invoice,
    'Auto GL ' || p_sale.no_invoice,
    v_lines,
    coalesce(p_sale.nama_kasir, 'SYSTEM')
  );
  return v_id;
exception when others then
  -- jangan gagalkan penjualan jika GL gagal
  raise warning 'gl_post_sale_row failed for %: %', p_sale.no_invoice, SQLERRM;
  return null;
end;
$$;

create or replace function public.gl_trg_sales_ai()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.gl_post_sale_row(new);
  return new;
end;
$$;

drop trigger if exists trg_gl_sales_ai on public.sales;
create trigger trg_gl_sales_ai
  after insert on public.sales
  for each row
  execute function public.gl_trg_sales_ai();

-- Saat pelunasan DP: sisa turun → posting SETTLE (Dr kas, Cr piutang)
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
begin
  if v_new_sisa >= v_old_sisa then
    return new;
  end if;
  v_collect := v_old_sisa - v_new_sisa;
  if v_collect <= 0 then
    return new;
  end if;

  v_asset := case
    when upper(coalesce(new.metode_pembayaran, 'CASH')) in ('CASH', 'TUNAI', '') then '1101'
    else '1102'
  end;
  v_ref := 'SETTLE-' || coalesce(new.no_invoice, new.id::text) || '-' ||
           to_char(now(), 'YYYYMMDDHH24MISS');

  begin
    perform public.post_journal_balanced(
      upper(new.toko_id),
      (timezone('Asia/Jakarta', now()))::date,
      'SETTLE',
      v_ref,
      'Pelunasan piutang ' || coalesce(new.no_invoice, ''),
      jsonb_build_array(
        jsonb_build_object('akun_kode', v_asset, 'debit', v_collect, 'kredit', 0, 'memo', 'Settle'),
        jsonb_build_object('akun_kode', '1103', 'debit', 0, 'kredit', v_collect, 'memo', 'Settle')
      ),
      coalesce(new.nama_kasir, 'SYSTEM')
    );
  exception when others then
    raise warning 'gl settle failed for %: %', new.no_invoice, SQLERRM;
  end;
  return new;
end;
$$;

drop trigger if exists trg_gl_sales_au_settle on public.sales;
create trigger trg_gl_sales_au_settle
  after update of sisa_tagihan on public.sales
  for each row
  when (coalesce(new.sisa_tagihan, 0) < coalesce(old.sisa_tagihan, 0))
  execute function public.gl_trg_sales_au_settle();

grant execute on function public.gl_post_sale_row(public.sales) to authenticated;
grant execute on function public.post_journal_balanced(text, date, text, text, text, jsonb, text) to authenticated;

-- Backfill: izinkan SETTLE-* (jangan dikira omzet POS)
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
    order by coalesce(ft.tanggal_transaksi, ft.created_at::date)
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
  loop
    begin
      v_ref := coalesce(nullif(btrim(r.referensi_id), ''), 'FT-' || r.id::text);
      v_is_close := upper(v_ref) like 'CLOSE-%'
        or upper(coalesce(r.kategori, '')) like '%PENUTUPAN%'
        or upper(coalesce(r.kategori, '')) like '%CLOSING%';
      v_is_settle := upper(v_ref) like 'SETTLE-%'
        or upper(coalesce(r.kategori, '')) like '%PELUNASAN%';

      -- Skip omzet POS murni (invoice/sale id) — sudah dari sales trigger/backfill
      if not v_is_close and not v_is_settle
         and r.referensi_id is not null and btrim(r.referensi_id) <> ''
         and upper(r.referensi_id) not like 'CLOSE-%'
         and upper(r.referensi_id) not like 'FT-%'
         and upper(r.referensi_id) not like 'SETTLE-%' then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      if exists (
        select 1 from public.journal_entries je
        where je.status = 'POSTED'
          and je.referensi_id = v_ref
          and (
            (v_is_close and je.sumber = 'CLOSING')
            or (v_is_settle and je.sumber = 'SETTLE')
            or (not v_is_close and not v_is_settle and je.sumber = 'MANUAL')
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

      if v_is_settle then
        perform public.post_journal_balanced(
          upper(r.toko_id),
          coalesce(r.tanggal_transaksi, (r.created_at at time zone 'Asia/Jakarta')::date),
          'SETTLE', v_ref, coalesce(r.deskripsi, 'Pelunasan'),
          jsonb_build_array(
            jsonb_build_object('akun_kode', v_asset, 'debit', v_nom, 'kredit', 0),
            jsonb_build_object('akun_kode', '1103', 'debit', 0, 'kredit', v_nom)
          ),
          p_created_by
        );
      elsif v_is_close then
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
