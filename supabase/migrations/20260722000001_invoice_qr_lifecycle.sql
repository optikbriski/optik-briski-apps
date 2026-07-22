-- =============================================================================
-- Invoice customer QR lifecycle: one-time DP / LUNAS / CLAIM tokens
-- =============================================================================

alter table public.sales
  add column if not exists qr_dp_token text,
  add column if not exists qr_dp_used_at timestamptz,
  add column if not exists qr_dp_used_by text,
  add column if not exists qr_lunas_token text,
  add column if not exists qr_lunas_used_at timestamptz,
  add column if not exists qr_lunas_used_by text,
  add column if not exists qr_claim_token text,
  add column if not exists qr_claim_used_at timestamptz,
  add column if not exists qr_claim_used_by text,
  add column if not exists lunas_at timestamptz;

comment on column public.sales.qr_dp_token is
  'Token QR pelanggan fase DP (sekali pakai). Payload: OBRINV|v1|<no>|DP|<token>';
comment on column public.sales.qr_lunas_token is
  'Token QR pelanggan fase LUNAS / serah terima (sekali pakai).';
comment on column public.sales.qr_claim_token is
  'Token QR pelanggan fase CLAIM garansi (sekali pakai), diterbitkan setelah serah terima.';

-- Staff hub payload: expose token status (bukan nilai token ke customer/anon)
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
  v_is_staff boolean := false;
  v_uid uuid := auth.uid();
  v_claimable boolean := false;
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

  select exists (
    select 1
    from public.garansi_kartu g
    where g.sale_id = v_sale.id
      and g.status = 'aktif'
      and coalesce(g.klaim_digunakan, false) = false
      and g.tanggal_akhir is not null
      and g.tanggal_akhir::date >= (timezone('Asia/Jakarta', now()))::date
  ) into v_claimable;

  return jsonb_build_object(
    'role_view', case when v_is_staff then 'staff' else 'customer' end,
    'sale_id', v_sale.id,
    'no_invoice', v_sale.no_invoice,
    'toko_id', v_sale.toko_id,
    'nama_pelanggan', v_sale.nama_pelanggan,
    'nama_kasir', v_sale.nama_kasir,
    'status_pembayaran', v_sale.status_pembayaran,
    'tracking_status', v_sale.tracking_status,
    'diambil_at', v_sale.diambil_at,
    'foto_hasil_url', v_sale.foto_hasil_url,
    'created_at', v_sale.created_at,
    'lunas_at', v_sale.lunas_at,
    'total_harga', case when v_is_staff then v_sale.total_harga else null end,
    'dibayarkan', case when v_is_staff then v_sale.dibayarkan else null end,
    'sisa_tagihan', v_sale.sisa_tagihan,
    'metode_pembayaran', case when v_is_staff then v_sale.metode_pembayaran else null end,
    'no_wa', case when v_is_staff then v_sale.no_wa else null end,
    'email_pelanggan', case when v_is_staff then v_sale.email_pelanggan else null end,
    'alamat', case when v_is_staff then v_sale.alamat else null end,
    'items', v_items,
    'garansi', v_garansi,
    'garansi_claimable', v_claimable,
    -- status token (bukan nilai rahasia) untuk validasi UI staff
    'qr_dp_ready', (v_sale.qr_dp_token is not null and v_sale.qr_dp_used_at is null),
    'qr_lunas_ready', (v_sale.qr_lunas_token is not null and v_sale.qr_lunas_used_at is null),
    'qr_claim_ready', (v_sale.qr_claim_token is not null and v_sale.qr_claim_used_at is null),
    'qr_dp_used', (v_sale.qr_dp_used_at is not null),
    'qr_lunas_used', (v_sale.qr_lunas_used_at is not null),
    'qr_claim_used', (v_sale.qr_claim_used_at is not null)
  );
end;
$$;

revoke all on function public.get_invoice_hub(text) from public;
grant execute on function public.get_invoice_hub(text) to anon, authenticated;

comment on function public.get_invoice_hub(text) is
  'Hub QR invoice: customer ringkas; staff + status token lifecycle sekali pakai.';
