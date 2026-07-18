-- Tabel yang belum ada di Table Editor (melengkapi schema app)
-- RLS tetap nyala + policy authenticated

create extension if not exists "pgcrypto";

-- Pastikan toko master ada
insert into public.toko_id (id, toko_id) values
  ('PUSAT', 'Optik B. Riski - Pusat'),
  ('CABANG-CIMAHI', 'Optik B. Riski - CABANG-CIMAHI')
on conflict (id) do nothing;

-- finance_transactions
create table if not exists public.finance_transactions (
  id uuid primary key default gen_random_uuid(),
  toko_id text references public.toko_id (id),
  tanggal_transaksi date,
  jenis_transaksi text,
  kategori text,
  deskripsi text,
  nominal bigint not null default 0,
  status_pembayaran text,
  metode_pembayaran text,
  nama_kasir text,
  status_konfirmasi text default 'PENDING',
  referensi_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- pending_requests
create table if not exists public.pending_requests (
  id bigserial primary key,
  toko_id text references public.toko_id (id),
  no_invoice text,
  nama_pelanggan text,
  sku text,
  nama_produk text,
  kategori text,
  qty_request integer not null default 1,
  tipe_request text,
  status text default 'PENDING',
  tracking_status text,
  detail_resep text,
  created_at timestamptz not null default now()
);

-- session_logs
create table if not exists public.session_logs (
  id uuid primary key default gen_random_uuid(),
  toko_id text references public.toko_id (id),
  karyawan_id text,
  photo_url text,
  timestamp_open timestamptz,
  status text default 'OPEN',
  created_at timestamptz not null default now()
);

-- invoice_settings
create table if not exists public.invoice_settings (
  toko_id text primary key references public.toko_id (id) on delete cascade,
  shop_name text,
  address text,
  phone text,
  logo_url text,
  footer_text text,
  header_alignment text default 'CENTER',
  font_size_header integer default 14,
  font_size_body integer default 11,
  show_qr_invoice boolean default true,
  updated_at timestamptz not null default now()
);

-- stock_move_history
create table if not exists public.stock_move_history (
  id uuid primary key default gen_random_uuid(),
  product_name text,
  dari_lokasi text,
  ke_lokasi text,
  jumlah integer not null default 0,
  tipe text,
  status text default 'TRANSIT',
  bukti_foto_pengirim text,
  bukti_foto_penerima text,
  bukti_foto_penerim text,
  keterangan text,
  created_at timestamptz not null default now()
);

-- draft_pengiriman
create table if not exists public.draft_pengiriman (
  id uuid primary key default gen_random_uuid(),
  tujuan text,
  items text,
  created_at timestamptz not null default now()
);

-- versi_app
create table if not exists public.versi_app (
  id uuid primary key default gen_random_uuid(),
  versi_terbaru text,
  url_download text,
  created_at timestamptz not null default now()
);

insert into public.versi_app (versi_terbaru, url_download)
select '1.2.1', ''
where not exists (select 1 from public.versi_app limit 1);

-- RLS + policy authenticated untuk semua tabel app
do $$
declare
  t text;
begin
  foreach t in array array[
    'toko_id','profiles','karyawan','products','inventory_stocks','sales',
    'sales_items','finance_transactions','pending_requests','session_logs',
    'invoice_settings','stock_move_history','draft_pengiriman','versi_app'
  ]
  loop
    execute format('alter table if exists public.%I enable row level security', t);

    execute format('drop policy if exists %I on public.%I', t || '_authenticated_all', t);
    execute format('drop policy if exists %I on public.%I', t || '_auth_all', t);

    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true)',
      t || '_auth_all', t
    );
  end loop;
end $$;

-- anon baca toko + versi
drop policy if exists toko_id_anon_select on public.toko_id;
create policy toko_id_anon_select on public.toko_id
  for select to anon using (true);

drop policy if exists versi_app_anon_select on public.versi_app;
create policy versi_app_anon_select on public.versi_app
  for select to anon using (true);

drop policy if exists karyawan_anon_insert on public.karyawan;
create policy karyawan_anon_insert on public.karyawan
  for insert to anon with check (true);

drop policy if exists karyawan_anon_select on public.karyawan;
create policy karyawan_anon_select on public.karyawan
  for select to anon using (true);
