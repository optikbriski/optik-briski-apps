-- =============================================================================
-- Member klaim garansi: RPC phone-scoped (submit + list) + kunci RLS anon.
-- App Member pakai anon key → wajib lewat security definer, bukan insert/select langsung.
-- =============================================================================

create or replace function public.list_member_claim_requests(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
begin
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select r.*
      from public.garansi_klaim_request r
      where public.wa_digits(r.phone_e164) = v_phone
      order by r.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

comment on function public.list_member_claim_requests(text) is
  'Daftar pengajuan klaim Member — hanya baris nomor HP pemanggil.';

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

  if coalesce(v_kartu.status, '') <> 'aktif' then
    raise exception 'Garansi tidak aktif — ambil barang di toko dulu atau masa sudah habis';
  end if;
  if coalesce(v_kartu.klaim_digunakan, false) then
    raise exception 'Klaim untuk transaksi ini sudah dipakai (maks. 1×)';
  end if;
  if v_kartu.tanggal_akhir is null or v_kartu.tanggal_akhir::date < v_today then
    raise exception 'Masa garansi sudah habis';
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
  'Ajukan klaim Member: validasi kepemilikan kartu + status aktif + tidak ada pengajuan terbuka.';

grant execute on function public.list_member_claim_requests(text) to anon, authenticated;
grant execute on function public.submit_member_garansi_klaim(text, uuid, text, text, timestamptz, uuid, uuid, text)
  to anon, authenticated;

-- Kunci akses langsung tabel dari anon (Member APK). Staff authenticated tetap bisa.
drop policy if exists garansi_klaim_req_anon_all on public.garansi_klaim_request;

drop policy if exists garansi_klaim_req_staff_all on public.garansi_klaim_request;
create policy garansi_klaim_req_staff_all on public.garansi_klaim_request
  for all to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid())
    or exists (
      select 1 from public.karyawan k
      where k.id = auth.uid()
        and coalesce(k.status_approval, '') = 'Aktif'
    )
  )
  with check (
    exists (select 1 from public.profiles p where p.id = auth.uid())
    or exists (
      select 1 from public.karyawan k
      where k.id = auth.uid()
        and coalesce(k.status_approval, '') = 'Aktif'
    )
  );
