-- Fix owner_compute_bagi_hasil return: do not assign jsonb into rowtype.
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
  v_existing public.bagi_hasil_period%rowtype;
  v_out jsonb;
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
  v_bagi_t := v_laba - v_bagi_u;

  select * into v_existing
  from public.bagi_hasil_period
  where toko_id = p_toko_id and periode_ym = v_ym;

  if v_existing.id is not null and v_existing.status in ('dikunci', 'dibayar') then
    return to_jsonb(v_existing) || jsonb_build_object('readonly', true);
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
  returning b.id into v_period_id;

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

  select to_jsonb(b.*) into v_out
  from public.bagi_hasil_period b
  where b.id = v_period_id;

  return v_out;
end;
$$;
