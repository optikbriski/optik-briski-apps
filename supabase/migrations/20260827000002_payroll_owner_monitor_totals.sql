-- Owner payroll monitor: expose pokok vs nett separately (was mapping nett into both).
create or replace function public.owner_payroll_monitor(p_toko_id text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text[];
  v_ym text := to_char((timezone('Asia/Jakarta', now()))::date, 'YYYY-MM');
  v_periods jsonb;
  v_lines jsonb;
  v_period_id uuid;
  v_status text;
  v_total_pokok bigint := 0;
  v_total_tunj bigint := 0;
  v_total_pot bigint := 0;
  v_total_nett bigint := 0;
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

  select coalesce(jsonb_agg(to_jsonb(p) order by p.periode_ym desc, p.toko_id), '[]'::jsonb)
  into v_periods
  from public.payroll_period p
  where p.toko_id = any (v_toko);

  select p.id, p.status, p.total_gaji_pokok, p.total_tunjangan, p.total_potongan, p.total_nett
  into v_period_id, v_status, v_total_pokok, v_total_tunj, v_total_pot, v_total_nett
  from public.payroll_period p
  where p.toko_id = any (v_toko)
    and p.periode_ym = v_ym
  order by p.updated_at desc
  limit 1;

  if v_period_id is not null then
    select coalesce(jsonb_agg(to_jsonb(l) order by l.nama), '[]'::jsonb)
    into v_lines
    from public.payroll_lines l
    where l.period_id = v_period_id;

    return jsonb_build_object(
      'periode_ym', v_ym,
      'period_id', v_period_id,
      'status', v_status,
      'lines', coalesce(v_lines, '[]'::jsonb),
      'total_gaji_pokok', coalesce(v_total_pokok, 0),
      'total_tunjangan', coalesce(v_total_tunj, 0),
      'total_potongan', coalesce(v_total_pot, 0),
      'total_nett', coalesce(v_total_nett, 0),
      'periods', coalesce(v_periods, '[]'::jsonb),
      'note', 'Payroll period real (Admin run/lock). Owner monitor saja.'
    );
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.toko_id, x.nama), '[]'::jsonb),
         coalesce(sum(x.gaji_pokok), 0)
  into v_lines, v_total_pokok
  from (
    select
      k.id as karyawan_id,
      k.nama,
      k.jabatan,
      k.toko_id,
      coalesce(k.gaji_pokok, 0) as gaji_pokok,
      coalesce(k.gaji_pokok, 0) as nett
    from public.karyawan k
    where k.toko_id = any (v_toko)
      and k.status_approval = 'Aktif'
  ) x;

  return jsonb_build_object(
    'periode_ym', v_ym,
    'period_id', null,
    'status', 'belum_dijalankan',
    'lines', coalesce(v_lines, '[]'::jsonb),
    'total_gaji_pokok', coalesce(v_total_pokok, 0),
    'total_tunjangan', 0,
    'total_potongan', 0,
    'total_nett', coalesce(v_total_pokok, 0),
    'periods', coalesce(v_periods, '[]'::jsonb),
    'note', 'Belum ada payroll_period bulan ini — menampilkan estimasi gaji_pokok. Minta Admin run period.'
  );
end;
$$;

comment on function public.owner_payroll_monitor(text) is
  'Owner monitor: totals from locked/draft period (pokok vs nett terpisah); fallback gaji_pokok.';

grant execute on function public.owner_payroll_monitor(text) to authenticated;
