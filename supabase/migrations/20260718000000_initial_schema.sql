-- =============================================================================
-- Optik B. Riski — schema awal (Admin + Karyawan)
-- Jalankan di: Supabase Dashboard → SQL Editor → New query → Run
-- Project: Optik B Riski Apps
-- =============================================================================

create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- 1. Master toko
-- -----------------------------------------------------------------------------
create table if not exists public.toko_id (
  id text primary key,              -- kode: PUSAT, CABANG-CIMAHI, ...
  toko_id text not null,            -- nama tampilan
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 2. Profil admin (1:1 auth.users)
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  role text not null default 'admin_toko',
  toko_id text not null default 'PUSAT' references public.toko_id (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_toko_id_idx on public.profiles (toko_id);

-- -----------------------------------------------------------------------------
-- 3. Karyawan lapangan
-- -----------------------------------------------------------------------------
create table if not exists public.karyawan (
  id uuid primary key default gen_random_uuid(),
  nik text unique,
  nama text,
  email text unique,
  wa text,
  gender text,
  umur text,
  jabatan text,
  cabang text,
  toko_id text references public.toko_id (id),
  pin_absensi text,
  alamat_lengkap text,
  nama_bank text,
  no_rekening text,
  darurat_nama text,
  darurat_wa text,
  tanggal_mulai timestamptz,
  status_approval text default 'Pending',
  foto_profile text,
  created_at timestamptz not null default now()
);

create index if not exists karyawan_toko_id_idx on public.karyawan (toko_id);
create index if not exists karyawan_status_idx on public.karyawan (status_approval);

-- Saat register: setelah signUp, set id = auth.uid() bila kosong
create or replace function public.karyawan_set_auth_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id is null and auth.uid() is not null then
    new.id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_karyawan_set_auth_id on public.karyawan;
create trigger trg_karyawan_set_auth_id
  before insert on public.karyawan
  for each row
  execute function public.karyawan_set_auth_id();

-- -----------------------------------------------------------------------------
-- 4. Produk (satu baris per toko)
-- -----------------------------------------------------------------------------
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  harga bigint not null default 0,
  harga_jual bigint,
  harga_modal bigint not null default 0,
  kategori text,
  sub_kategori text,
  barcode text,
  sku text,
  warna text,
  jenis_lensa text,
  sph_r double precision,
  sph_l double precision,
  cyl_r double precision,
  cyl_l double precision,
  add_r double precision,
  add_l double precision,
  image_url text,
  foto_url text,
  toko_id text not null references public.toko_id (id),
  stock integer not null default 0,
  created_at timestamptz not null default now()
);

-- Samakan harga_jual dengan harga bila kosong (app baca keduanya)
create or replace function public.products_sync_harga()
returns trigger
language plpgsql
as $$
begin
  if new.harga_jual is null then
    new.harga_jual := new.harga;
  end if;
  if new.harga is null and new.harga_jual is not null then
    new.harga := new.harga_jual;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_products_sync_harga on public.products;
create trigger trg_products_sync_harga
  before insert or update on public.products
  for each row
  execute function public.products_sync_harga();

create index if not exists products_toko_id_idx on public.products (toko_id);
create index if not exists products_barcode_toko_idx on public.products (barcode, toko_id);
create index if not exists products_sku_idx on public.products (sku);
create unique index if not exists products_barcode_toko_unique
  on public.products (barcode, toko_id)
  where barcode is not null and barcode <> '';

-- -----------------------------------------------------------------------------
-- 5. Stok paralel (SKU)
-- -----------------------------------------------------------------------------
create table if not exists public.inventory_stocks (
  toko_id text not null references public.toko_id (id),
  sku text not null,
  stok integer not null default 0,
  primary key (toko_id, sku)
);

-- -----------------------------------------------------------------------------
-- 6. Penjualan POS
-- -----------------------------------------------------------------------------
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  no_invoice text,
  toko_id text not null references public.toko_id (id),
  kasir_id uuid,
  nama_kasir text,
  nama_pelanggan text,
  no_wa text,
  alamat text,
  email_pelanggan text,
  total_harga bigint not null default 0,
  dibayarkan bigint not null default 0,
  sisa_tagihan bigint not null default 0,
  kembalian bigint not null default 0,
  status_pembayaran text,
  metode_pembayaran text,
  tracking_status text,
  created_at timestamptz not null default now()
);

create index if not exists sales_toko_created_idx on public.sales (toko_id, created_at desc);
create unique index if not exists sales_no_invoice_unique
  on public.sales (no_invoice)
  where no_invoice is not null;

create table if not exists public.sales_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  tipe_produk text,
  nama_produk text,
  harga_satuan bigint not null default 0,
  qty integer not null default 1,
  subtotal bigint not null default 0,
  detail_resep text
);

create index if not exists sales_items_sale_id_idx on public.sales_items (sale_id);

-- -----------------------------------------------------------------------------
-- 7. Keuangan / COA
-- -----------------------------------------------------------------------------
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

create index if not exists finance_toko_tgl_idx
  on public.finance_transactions (toko_id, tanggal_transaksi);
create index if not exists finance_status_idx
  on public.finance_transactions (status_konfirmasi);

-- -----------------------------------------------------------------------------
-- 8. Request order / restock
-- -----------------------------------------------------------------------------
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

create index if not exists pending_requests_toko_status_idx
  on public.pending_requests (toko_id, status, created_at desc);

-- -----------------------------------------------------------------------------
-- 9. Session buka toko
-- -----------------------------------------------------------------------------
create table if not exists public.session_logs (
  id uuid primary key default gen_random_uuid(),
  toko_id text references public.toko_id (id),
  karyawan_id text,                 -- NIK (bukan uuid)
  photo_url text,
  timestamp_open timestamptz,
  status text default 'OPEN',
  created_at timestamptz not null default now()
);

create index if not exists session_logs_toko_idx
  on public.session_logs (toko_id, timestamp_open desc);

-- -----------------------------------------------------------------------------
-- 10. Setting invoice per toko
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 11. Mutasi stok antar toko
-- -----------------------------------------------------------------------------
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
  bukti_foto_penerim text,          -- typo kolom lama (kompatibel app)
  keterangan text,                  -- JSON string item
  created_at timestamptz not null default now()
);

create index if not exists stock_move_ke_status_idx
  on public.stock_move_history (ke_lokasi, status);
create index if not exists stock_move_dari_status_idx
  on public.stock_move_history (dari_lokasi, status);

-- -----------------------------------------------------------------------------
-- 12. Draft pengiriman
-- -----------------------------------------------------------------------------
create table if not exists public.draft_pengiriman (
  id uuid primary key default gen_random_uuid(),
  tujuan text,
  items text,                       -- JSON string
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 13. Versi APK karyawan
-- -----------------------------------------------------------------------------
create table if not exists public.versi_app (
  id uuid primary key default gen_random_uuid(),
  versi_terbaru text,
  url_download text,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Seed data awal
-- -----------------------------------------------------------------------------
insert into public.toko_id (id, toko_id) values
  ('PUSAT', 'Optik B. Riski - Pusat'),
  ('CABANG-CIMAHI', 'Optik B. Riski - CABANG-CIMAHI')
on conflict (id) do nothing;

insert into public.versi_app (versi_terbaru, url_download)
select '1.2.1', ''
where not exists (select 1 from public.versi_app limit 1);

-- -----------------------------------------------------------------------------
-- RLS — bootstrap: authenticated boleh CRUD (ketatkan nanti per toko_id)
-- -----------------------------------------------------------------------------
alter table public.toko_id enable row level security;
alter table public.profiles enable row level security;
alter table public.karyawan enable row level security;
alter table public.products enable row level security;
alter table public.inventory_stocks enable row level security;
alter table public.sales enable row level security;
alter table public.sales_items enable row level security;
alter table public.finance_transactions enable row level security;
alter table public.pending_requests enable row level security;
alter table public.session_logs enable row level security;
alter table public.invoice_settings enable row level security;
alter table public.stock_move_history enable row level security;
alter table public.draft_pengiriman enable row level security;
alter table public.versi_app enable row level security;

-- Helper: drop+create policy aman diulang
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
    execute format('drop policy if exists %I on public.%I', t || '_authenticated_all', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true)',
      t || '_authenticated_all', t
    );
  end loop;
end $$;

-- Register / dropdown toko: anon boleh baca daftar toko
drop policy if exists toko_id_anon_select on public.toko_id;
create policy toko_id_anon_select on public.toko_id
  for select to anon using (true);

-- Versi app: anon boleh baca
drop policy if exists versi_app_anon_select on public.versi_app;
create policy versi_app_anon_select on public.versi_app
  for select to anon using (true);

-- Karyawan: anon boleh insert saat register (setelah signUp session kadang masih limbo)
drop policy if exists karyawan_anon_insert on public.karyawan;
create policy karyawan_anon_insert on public.karyawan
  for insert to anon with check (true);

drop policy if exists karyawan_anon_select on public.karyawan;
create policy karyawan_anon_select on public.karyawan
  for select to anon using (true);

-- -----------------------------------------------------------------------------
-- Storage buckets
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('session_photos', 'session_photos', true),
  ('attendance_photos', 'attendance_photos', true),
  ('LOGO', 'LOGO', true),
  ('bukti_transaksi', 'bukti_transaksi', true),
  ('Foto Frame', 'Foto Frame', true),
  ('verification-proofs', 'verification-proofs', true)
on conflict (id) do update set public = excluded.public;

-- Storage policies: baca publik, tulis untuk authenticated
do $$
declare
  b text;
begin
  foreach b in array array[
    'avatars','session_photos','attendance_photos','LOGO',
    'bukti_transaksi','Foto Frame','verification-proofs'
  ]
  loop
    execute format('drop policy if exists %I on storage.objects', 'public_read_' || replace(b, ' ', '_'));
    execute format(
      'create policy %I on storage.objects for select using (bucket_id = %L)',
      'public_read_' || replace(b, ' ', '_'), b
    );

    execute format('drop policy if exists %I on storage.objects', 'auth_write_' || replace(b, ' ', '_'));
    execute format(
      'create policy %I on storage.objects for insert to authenticated with check (bucket_id = %L)',
      'auth_write_' || replace(b, ' ', '_'), b
    );

    execute format('drop policy if exists %I on storage.objects', 'auth_update_' || replace(b, ' ', '_'));
    execute format(
      'create policy %I on storage.objects for update to authenticated using (bucket_id = %L)',
      'auth_update_' || replace(b, ' ', '_'), b
    );
  end loop;
end $$;

-- =============================================================================
-- SELESAI
-- Berikutnya:
-- 1. Authentication → Users → Add user (admin pusat / cabang)
-- 2. (Opsional) isi profiles lewat login Admin app
-- 3. Jalankan Admin (Debug) & login
-- =============================================================================
