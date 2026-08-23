-- =============================================================================
-- 000037 — GL toko: satu tenant, kasir boleh posting, anon dikunci.
-- Apply di SQL Editor live SETELAH 000036.
--
-- Celah live:
-- - EXECUTE masih PUBLIC: anon bisa post_journal_balanced + void + baca trial
-- - auth.uid() null dianggap service → JWT anon lolos
-- - periode/jurnal tidak mengikat tenant_id (unique sudah per tenant)
-- - super_admin / admin_pusat tidak diakui gl_is_owner_or_pusat
-- - SETTLE palsu saat total nota bergerak (sama rumus 000036)
-- =============================================================================

create or replace function public.gl_is_anon_jwt()
returns boolean
language sql
stable
as $$
  select coalesce(auth.role(), '') = 'anon';
$$;

create or replace function public.gl_is_owner_or_pusat()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    not public.gl_is_anon_jwt()
    and (
      public.gl_current_role() in (
        'owner', 'superadmin', 'super_admin', 'admin_pusat'
      )
      or public.gl_current_toko() = 'PUSAT'
    );
$$;

create or replace function public.gl_can_access_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    not public.gl_is_anon_jwt()
    and (
      auth.uid() is null
      or public.gl_is_owner_or_pusat()
      or (
        public.gl_current_toko() <> ''
        and upper(coalesce(p_toko, '')) = public.gl_current_toko()
      )
      or public.can_pos_checkout_for_toko(p_toko)
    );
$$;

create or replace function public._gl_ensure_period(
  p_tanggal date,
  p_tenant uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_tahun int := extract(year from p_tanggal)::int;
  v_bulan int := extract(month from p_tanggal)::int;
  v_tenant uuid := coalesce(
    p_tenant,
    public.current_tenant_id(),
    public.default_tenant_id()
  );
begin
  if public.gl_is_anon_jwt() then
    raise exception 'Unauthorized';
  end if;

  select id into v_id
  from public.fiscal_periods
  where tahun = v_tahun
    and bulan = v_bulan
    and tenant_id is not distinct from v_tenant;

  if v_id is null then
    insert into public.fiscal_periods (tahun, bulan, status, tenant_id)
    values (v_tahun, v_bulan, 'OPEN', v_tenant)
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

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
  v_tenant uuid;
begin
  if public.gl_is_anon_jwt() then
    raise exception 'Unauthorized';
  end if;
  if v_toko = '' then
    raise exception 'toko_id wajib diisi';
  end if;

  select tenant_id into v_tenant
  from public.toko_id
  where upper(trim(id)) = v_toko;
  v_tenant := coalesce(v_tenant, public.current_tenant_id(), public.default_tenant_id());

  if auth.uid() is not null
     and not public.gl_can_access_toko(v_toko) then
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
      and tenant_id is not distinct from v_tenant
      and upper(toko_id) = v_toko
    limit 1;
    if v_entry_id is not null then
      return v_entry_id;
    end if;
  end if;

  v_periode_id := public._gl_ensure_period(p_tanggal, v_tenant);
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
    tenant_id, toko_id, tanggal, periode_id, sumber, referensi_id, memo, status, created_by
  ) values (
    v_tenant, v_toko, p_tanggal, v_periode_id, p_sumber,
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

drop function if exists public._gl_ensure_period(date);

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
  if public.gl_is_anon_jwt() then
    raise exception 'Unauthorized';
  end if;

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
    v_je.tanggal,
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
  if coalesce(old.total_harga, 0) is distinct from coalesce(new.total_harga, 0) then
    return new;
  end if;
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
  if upper(trim(coalesce(p_sale.status_pembayaran, ''))) in ('BATAL', 'VOID', 'CANCEL') then
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
  raise warning 'gl_post_sale_row failed for %: %', p_sale.no_invoice, SQLERRM;
  return null;
end;
$$;

-- Jejak probe 1 rupiah (anon sempat lolos) + reverse-nya: VOID tanpa jurnal baru.
update public.journal_entries
set status = 'VOID', updated_at = now()
where status = 'POSTED'
  and (
    referensi_id = 'GL-PROBE-NO-WRITE'
    or referensi_id = 'VOID-c718be2d-7d2a-48fa-a66a-9e4f182f1271'
    or id in (
      'c718be2d-7d2a-48fa-a66a-9e4f182f1271'::uuid,
      '7c467ae5-fca1-4946-bcc1-8c628257c55d'::uuid
    )
  );

revoke all on function public.gl_is_anon_jwt() from public, anon;
revoke all on function public.gl_is_owner_or_pusat() from public, anon;
revoke all on function public.gl_can_access_toko(text) from public, anon;
revoke all on function public._gl_ensure_period(date, uuid) from public, anon;
revoke all on function public.post_journal_balanced(text, date, text, text, text, jsonb, text) from public, anon;
revoke all on function public.void_journal_entry(uuid, text) from public, anon;
revoke all on function public.gl_void_by_sumber_ref(text, text, text) from public, anon;
revoke all on function public.gl_void_sale_journals(text, text) from public, anon;
revoke all on function public.gl_trial_balance(int, int, text) from public, anon;
revoke all on function public.gl_post_sale_row(public.sales) from public, anon;
revoke all on function public.gl_post_finance_row(public.finance_transactions, text) from public, anon;
revoke all on function public.gl_backfill_sales_batch(text, int, text) from public, anon;
revoke all on function public.gl_backfill_finance_batch(text, int, text) from public, anon;
revoke all on function public.gl_consolidate_by_toko(int, int) from public, anon;
revoke all on function public.gl_aging_piutang(text, int) from public, anon;
revoke all on function public.gl_aging_hutang(text, int) from public, anon;
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.gl_run_full_audit(text, int)',
    'public.gl_run_full_audit(text, int, int, int)'
  ]
  loop
    begin
      execute format('revoke all on function %s from public, anon', f);
    exception when undefined_function then
      null;
    end;
  end loop;
end $$;

grant execute on function public.gl_is_owner_or_pusat() to authenticated;
grant execute on function public.gl_can_access_toko(text) to authenticated;
grant execute on function public.post_journal_balanced(text, date, text, text, text, jsonb, text) to authenticated;
grant execute on function public.void_journal_entry(uuid, text) to authenticated;
grant execute on function public.gl_void_by_sumber_ref(text, text, text) to authenticated;
grant execute on function public.gl_void_sale_journals(text, text) to authenticated;
grant execute on function public.gl_trial_balance(int, int, text) to authenticated;
grant execute on function public.gl_post_sale_row(public.sales) to authenticated;

comment on function public.post_journal_balanced(text, date, text, text, text, jsonb, text) is
  'Post jurnal berimbang per tenant+toko. Bukan anon. Idempotent sumber+ref.';
