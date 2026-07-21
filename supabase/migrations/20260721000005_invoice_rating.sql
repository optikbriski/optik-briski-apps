-- =============================================================================
-- Rating karyawan dari QR invoice: kasir POS + pembuat kacamata
-- 1 rating per peran per transaksi. Customer bisa rate setelah DIAMBIL.
-- =============================================================================

alter table public.sales
  add column if not exists kasir_karyawan_id uuid references public.karyawan (id) on delete set null,
  add column if not exists pembuat_kacamata_id uuid references public.karyawan (id) on delete set null,
  add column if not exists nama_pembuat_kacamata text;

create index if not exists sales_kasir_karyawan_idx on public.sales (kasir_karyawan_id);
create index if not exists sales_pembuat_kacamata_idx on public.sales (pembuat_kacamata_id);

create table if not exists public.invoice_rating (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  no_invoice text,
  peran text not null check (peran in ('kasir', 'pembuat')),
  karyawan_id uuid references public.karyawan (id) on delete set null,
  nama_karyawan text,
  skor integer not null check (skor between 1 and 5),
  komentar text,
  created_at timestamptz not null default now(),
  unique (sale_id, peran)
);

create index if not exists invoice_rating_karyawan_idx
  on public.invoice_rating (karyawan_id, created_at desc);

alter table public.invoice_rating enable row level security;

drop policy if exists invoice_rating_auth_all on public.invoice_rating;
create policy invoice_rating_auth_all on public.invoice_rating
  for all to authenticated
  using (true)
  with check (true);

-- Anon boleh insert rating (customer scan QR) + select ringkas via RPC
drop policy if exists invoice_rating_anon_insert on public.invoice_rating;
create policy invoice_rating_anon_insert on public.invoice_rating
  for insert to anon
  with check (true);

drop policy if exists invoice_rating_anon_select on public.invoice_rating;
create policy invoice_rating_anon_select on public.invoice_rating
  for select to anon
  using (true);

-- Submit rating (validasi: sudah diambil, 1x per peran, karyawan terisi)
-- PENTING: admin/karyawan login DILARANG isi rating (anti self-rating).
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
  -- Blokir self-rating oleh staff
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

revoke all on function public.submit_invoice_rating(text, text, int, text) from public;
grant execute on function public.submit_invoice_rating(text, text, int, text) to anon, authenticated;

-- Update hub RPC: sertakan staff + rating
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

-- Set pembuat kacamata (staff)
create or replace function public.set_invoice_pembuat(
  p_no_invoice text,
  p_karyawan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nama text;
  v_sale_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Login diperlukan';
  end if;

  select nama into v_nama
  from public.karyawan
  where id = p_karyawan_id
  limit 1;

  if v_nama is null then
    raise exception 'Karyawan tidak ditemukan';
  end if;

  update public.sales
  set
    pembuat_kacamata_id = p_karyawan_id,
    nama_pembuat_kacamata = v_nama
  where no_invoice = trim(p_no_invoice)
  returning id into v_sale_id;

  if v_sale_id is null then
    raise exception 'Invoice tidak ditemukan';
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'pembuat_kacamata_id', p_karyawan_id,
    'nama_pembuat_kacamata', v_nama
  );
end;
$$;

revoke all on function public.set_invoice_pembuat(text, uuid) from public;
grant execute on function public.set_invoice_pembuat(text, uuid) to authenticated;

comment on table public.invoice_rating is
  'Rating pelanggan untuk kasir POS dan pembuat kacamata (1x per peran per invoice).';
