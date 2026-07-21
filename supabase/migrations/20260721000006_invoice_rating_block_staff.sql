-- Blokir karyawan/admin mengisi rating sendiri (jalankan jika 000005 sudah pernah di-apply).
create or replace function public.submit_invoice_rating(
  p_no_invoice text,
  p_peran text,
  p_skor int,
  p_komentar text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_kid uuid;
  v_nama text;
  v_row public.invoice_rating%rowtype;
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and (
    exists (select 1 from public.profiles p where p.id = v_uid)
    or exists (
      select 1 from public.karyawan k
      where k.id = v_uid and coalesce(k.status_approval, '') = 'Aktif'
    )
  ) then
    raise exception 'Karyawan/admin tidak boleh mengisi rating. Minta pelanggan scan QR dari HP mereka.';
  end if;

  if p_peran not in ('kasir', 'pembuat') then
    raise exception 'Peran tidak valid';
  end if;
  if p_skor is null or p_skor < 1 or p_skor > 5 then
    raise exception 'Skor harus 1–5';
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
  limit 1;

  if not found then
    raise exception 'Invoice tidak ditemukan';
  end if;

  if v_sale.diambil_at is null and coalesce(v_sale.tracking_status, '') <> 'DIAMBIL' then
    raise exception 'Rating hanya setelah kacamata diambil customer';
  end if;

  if p_peran = 'kasir' then
    v_kid := v_sale.kasir_karyawan_id;
    v_nama := v_sale.nama_kasir;
  else
    v_kid := v_sale.pembuat_kacamata_id;
    v_nama := v_sale.nama_pembuat_kacamata;
  end if;

  if v_kid is null and (v_nama is null or length(trim(v_nama)) = 0) then
    raise exception 'Karyawan untuk peran ini belum ditetapkan di transaksi';
  end if;

  insert into public.invoice_rating (
    sale_id, no_invoice, peran, karyawan_id, nama_karyawan, skor, komentar
  ) values (
    v_sale.id, v_sale.no_invoice, p_peran, v_kid, v_nama, p_skor, nullif(trim(p_komentar), '')
  )
  on conflict (sale_id, peran) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Rating untuk peran ini sudah pernah diisi';
  end if;

  return to_jsonb(v_row);
end;
$$;
