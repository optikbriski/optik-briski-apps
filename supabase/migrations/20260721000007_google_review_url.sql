-- URL Google Review per cabang (tombol dari Hub Invoice / struk).
alter table public.invoice_settings
  add column if not exists google_review_url text;

comment on column public.invoice_settings.google_review_url is
  'Link Google Review cabang (Maps / g.page). Dipakai QR hub & struk.';

-- Sertakan di get_invoice_hub
create or replace function public.get_invoice_hub(p_no_invoice text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_items jsonb;
  v_garansi jsonb;
  v_ratings jsonb;
  v_google text;
  v_is_staff boolean := false;
  v_uid uuid := auth.uid();
begin
  if p_no_invoice is null or length(trim(p_no_invoice)) = 0 then
    return null;
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
  limit 1;

  if not found then
    return null;
  end if;

  if v_uid is not null then
    v_is_staff := exists (
      select 1 from public.profiles p where p.id = v_uid
    ) or exists (
      select 1 from public.karyawan k
      where k.id = v_uid and coalesce(k.status_approval, '') = 'Aktif'
    );
  end if;

  select nullif(trim(s.google_review_url), '')
  into v_google
  from public.invoice_settings s
  where s.toko_id = v_sale.toko_id;

  if v_google is null then
    select nullif(trim(s.google_review_url), '')
    into v_google
    from public.invoice_settings s
    where s.toko_id = 'PUSAT';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'nama_produk', si.nama_produk,
    'tipe_produk', si.tipe_produk,
    'qty', si.qty,
    'subtotal', case when v_is_staff then si.subtotal else null end
  ) order by si.nama_produk), '[]'::jsonb)
  into v_items
  from public.sales_items si
  where si.sale_id = v_sale.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id,
    'jenis_garansi', g.jenis_garansi,
    'nama_produk', g.nama_produk,
    'status', g.status,
    'tanggal_mulai', g.tanggal_mulai,
    'tanggal_akhir', g.tanggal_akhir,
    'klaim_digunakan', g.klaim_digunakan,
    'spesifikasi_produk', g.spesifikasi_produk
  )), '[]'::jsonb)
  into v_garansi
  from public.garansi_kartu g
  where g.sale_id = v_sale.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'peran', r.peran,
    'skor', r.skor,
    'nama_karyawan', r.nama_karyawan,
    'komentar', r.komentar,
    'created_at', r.created_at
  )), '[]'::jsonb)
  into v_ratings
  from public.invoice_rating r
  where r.sale_id = v_sale.id;

  return jsonb_build_object(
    'role_view', case when v_is_staff then 'staff' else 'customer' end,
    'sale_id', v_sale.id,
    'no_invoice', v_sale.no_invoice,
    'toko_id', v_sale.toko_id,
    'nama_pelanggan', v_sale.nama_pelanggan,
    'nama_kasir', v_sale.nama_kasir,
    'kasir_karyawan_id', v_sale.kasir_karyawan_id,
    'pembuat_kacamata_id', v_sale.pembuat_kacamata_id,
    'nama_pembuat_kacamata', v_sale.nama_pembuat_kacamata,
    'status_pembayaran', v_sale.status_pembayaran,
    'tracking_status', v_sale.tracking_status,
    'diambil_at', v_sale.diambil_at,
    'foto_hasil_url', v_sale.foto_hasil_url,
    'created_at', v_sale.created_at,
    'total_harga', case when v_is_staff then v_sale.total_harga else null end,
    'dibayarkan', case when v_is_staff then v_sale.dibayarkan else null end,
    'sisa_tagihan', v_sale.sisa_tagihan,
    'metode_pembayaran', case when v_is_staff then v_sale.metode_pembayaran else null end,
    'no_wa', case when v_is_staff then v_sale.no_wa else null end,
    'google_review_url', v_google,
    'items', v_items,
    'garansi', v_garansi,
    'ratings', v_ratings,
    'bisa_rating', (
      v_sale.diambil_at is not null
      or coalesce(v_sale.tracking_status, '') = 'DIAMBIL'
    )
  );
end;
$$;
