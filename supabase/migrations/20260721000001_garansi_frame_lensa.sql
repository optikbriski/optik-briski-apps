-- =============================================================================
-- Garansi Frame + Lensa: kartu dari penjualan, klaim diputus cabang (instan).
-- Pusat pantau semua cabang (read-only pada klaim di v1).
-- Jalankan di Supabase → SQL Editor jika migration belum di-apply.
-- =============================================================================

create table if not exists public.garansi_kartu (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  sale_item_id uuid not null references public.sales_items (id) on delete cascade,
  toko_id text not null references public.toko_id (id),
  no_invoice text,
  nama_pelanggan text,
  no_wa text,
  product_id uuid references public.products (id) on delete set null,
  nama_produk text,
  jenis_garansi text not null check (jenis_garansi in ('frame', 'lensa')),
  tanggal_mulai date,
  tanggal_akhir date,
  status text not null default 'menunggu_ambil'
    check (status in ('menunggu_ambil', 'aktif', 'habis', 'diklaim', 'batal')),
  created_at timestamptz not null default now(),
  unique (sale_item_id)
);

create index if not exists garansi_kartu_toko_created_idx
  on public.garansi_kartu (toko_id, created_at desc);
create index if not exists garansi_kartu_invoice_idx
  on public.garansi_kartu (no_invoice);
create index if not exists garansi_kartu_status_idx
  on public.garansi_kartu (status);
create index if not exists garansi_kartu_wa_idx
  on public.garansi_kartu (no_wa);

create table if not exists public.garansi_klaim (
  id uuid primary key default gen_random_uuid(),
  kartu_id uuid not null references public.garansi_kartu (id) on delete cascade,
  toko_id text not null references public.toko_id (id),
  diajukan_oleh uuid,
  created_at timestamptz not null default now(),
  alasan text not null,
  catatan text,
  foto_url text,
  keputusan text not null
    check (keputusan in (
      'diterima',
      'ditolak',
      'selesai_perbaikan',
      'selesai_ganti'
    )),
  diputuskan_oleh uuid,
  diputuskan_at timestamptz not null default now()
);

create index if not exists garansi_klaim_kartu_idx
  on public.garansi_klaim (kartu_id, created_at desc);
create index if not exists garansi_klaim_toko_created_idx
  on public.garansi_klaim (toko_id, created_at desc);

alter table public.garansi_kartu enable row level security;
alter table public.garansi_klaim enable row level security;

-- Authenticated admins: full access (app filters pusat vs cabang by toko_id).
-- Matches other operational tables (sales, attendance) pattern.
drop policy if exists garansi_kartu_auth_all on public.garansi_kartu;
create policy garansi_kartu_auth_all on public.garansi_kartu
  for all to authenticated
  using (true)
  with check (true);

drop policy if exists garansi_klaim_auth_all on public.garansi_klaim;
create policy garansi_klaim_auth_all on public.garansi_klaim
  for all to authenticated
  using (true)
  with check (true);

comment on table public.garansi_kartu is
  'Kartu garansi frame/lensa. Aktif 7 hari sejak scan ambil (lihat migrasi 000002).';
comment on table public.garansi_klaim is
  'Klaim garansi 1x/sale; keputusan instan cabang. Pusat pantau.';

-- Catatan: tanggal_mulai/akhir diisi saat konfirmasi ambil (migrasi 000002).
-- Untuk install fresh, biarkan NOT NULL di bawah diubah oleh 000002.
