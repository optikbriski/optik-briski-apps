-- =============================================================================
-- Enforce Member Garansi window: klaim hanya hari 0..7 sejak diambil (Jakarta).
-- Hari ke-8+ → mati. Server reject even if client bypassed.
-- list_member_garansi returns effective status 'habis' when past window.
-- =============================================================================

create or replace function public.submit_member_garansi_klaim(
  p_phone text,
  p_kartu_id uuid,
  p_toko_id text,
  p_alasan text,
  p_jadwal_kunjungan timestamptz,
  p_sale_id uuid default null,
  p_member_id uuid default null,
  p_foto_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_kartu public.garansi_kartu%rowtype;
  v_alasan text := trim(coalesce(p_alasan, ''));
  v_toko text := trim(coalesce(p_toko_id, ''));
  v_row public.garansi_klaim_request%rowtype;
  v_today date := (timezone('Asia/Jakarta', now()))::date;
  v_start date;
  v_end date;
begin
  if v_phone is null or length(v_phone) < 8 then
    raise exception 'Nomor HP tidak valid';
  end if;
  if p_kartu_id is null then
    raise exception 'Kartu garansi wajib dipilih';
  end if;
  if v_toko = '' then
    raise exception 'Cabang kunjungan wajib dipilih';
  end if;
  if v_alasan = '' then
    raise exception 'Alasan / keluhan wajib diisi';
  end if;
  if p_jadwal_kunjungan is null then
    raise exception 'Jadwal kunjungan wajib diisi';
  end if;
  if coalesce(trim(p_foto_url), '') = '' then
    raise exception 'Foto kondisi barang wajib diunggah';
  end if;

  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;

  select * into v_kartu
  from public.garansi_kartu g
  where g.id = p_kartu_id
  limit 1;
  if not found then
    raise exception 'Kartu garansi tidak ditemukan';
  end if;

  -- Harus milik nomor HP member (sama pola list_member_garansi)
  if not (
    public.wa_digits(v_kartu.no_wa) = v_phone
    or regexp_replace(coalesce(v_kartu.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
  ) then
    raise exception 'Kartu garansi tidak milik nomor ini';
  end if;

  if coalesce(v_kartu.status, '') = 'menunggu_ambil' then
    raise exception 'Garansi belum aktif — ambil barang di toko dulu';
  end if;
  if coalesce(v_kartu.klaim_digunakan, false)
     or coalesce(v_kartu.status, '') = 'diklaim' then
    raise exception 'Klaim untuk transaksi ini sudah dipakai (maks. 1×)';
  end if;
  if coalesce(v_kartu.status, '') in ('habis', 'batal') then
    raise exception 'Garansi mati — lebih dari 7 hari sejak diambil';
  end if;
  if coalesce(v_kartu.status, '') <> 'aktif' then
    raise exception 'Garansi tidak aktif — ambil barang di toko dulu atau masa sudah habis';
  end if;

  -- Clock: hari kalender diambil (Jakarta). Window inklusif hari 0..7.
  v_start := coalesce(
    (timezone('Asia/Jakarta', v_kartu.diambil_at))::date,
    v_kartu.tanggal_mulai
  );
  if v_start is null then
    raise exception 'Garansi belum aktif — ambil barang di toko dulu';
  end if;

  v_end := coalesce(v_kartu.tanggal_akhir, v_start + 7);
  -- Hard cap: tidak boleh melebihi mulai+7 meski tanggal_akhir diutak-atik
  if v_end > (v_start + 7) then
    v_end := v_start + 7;
  end if;

  if v_today > v_end then
    -- Soft-expire kartu biar UI list konsisten
    update public.garansi_kartu
       set status = 'habis'
     where id = v_kartu.id
       and status = 'aktif'
       and coalesce(klaim_digunakan, false) = false;
    raise exception 'Garansi mati — lebih dari 7 hari sejak diambil';
  end if;

  if exists (
    select 1
    from public.garansi_klaim_request r
    where r.kartu_id = p_kartu_id
      and r.status in ('diajukan', 'diproses_toko')
  ) then
    raise exception 'Pengajuan untuk kartu ini masih terbuka';
  end if;

  insert into public.garansi_klaim_request (
    phone_e164,
    member_id,
    kartu_id,
    sale_id,
    toko_id,
    alasan,
    foto_url,
    jadwal_kunjungan,
    status
  ) values (
    v_phone,
    p_member_id,
    p_kartu_id,
    coalesce(p_sale_id, v_kartu.sale_id),
    v_toko,
    v_alasan,
    trim(p_foto_url),
    p_jadwal_kunjungan,
    'diajukan'
  )
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

comment on function public.submit_member_garansi_klaim(text, uuid, text, text, timestamptz, uuid, uuid, text) is
  'Ajukan klaim Member: milik HP + aktif + window 0..7 hari sejak diambil (Jakarta) + tidak ada pengajuan terbuka.';

create or replace function public.list_member_garansi(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_today date := (timezone('Asia/Jakarta', now()))::date;
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;

  -- Soft-expire kartu aktif yang lewat window (mulai+7 / tanggal_akhir)
  update public.garansi_kartu g
     set status = 'habis'
   where coalesce(g.klaim_digunakan, false) = false
     and g.status = 'aktif'
     and (
       public.wa_digits(g.no_wa) = v_phone
       or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
     )
     and (
       coalesce(
         g.tanggal_akhir,
         coalesce(
           (timezone('Asia/Jakarta', g.diambil_at))::date,
           g.tanggal_mulai
         ) + 7
       ) < v_today
       or (
         coalesce(
           (timezone('Asia/Jakarta', g.diambil_at))::date,
           g.tanggal_mulai
         ) is not null
         and coalesce(
           (timezone('Asia/Jakarta', g.diambil_at))::date,
           g.tanggal_mulai
         ) + 7 < v_today
       )
     );

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.tanggal_akhir desc nulls last)
    from (
      select g.*
      from public.garansi_kartu g
      where public.wa_digits(g.no_wa) = v_phone
         or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
      order by g.tanggal_akhir desc nulls last
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

comment on function public.list_member_garansi(text) is
  'Daftar kartu garansi Member (HP pemanggil); soft-expire status habis jika >7 hari sejak diambil.';

grant execute on function public.list_member_garansi(text) to anon, authenticated;
grant execute on function public.submit_member_garansi_klaim(text, uuid, text, text, timestamptz, uuid, uuid, text)
  to anon, authenticated;
