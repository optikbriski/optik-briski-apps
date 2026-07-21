-- =============================================================================
-- Garansi v2: mulai saat customer AMBIL barang (scan barcode invoice + foto hasil).
-- Durasi 7 hari. Klaim maksimal 1x per transaksi (sale).
-- Jalankan SETELAH 20260721000001_garansi_frame_lensa.sql
-- =============================================================================

-- Sales: konfirmasi ambil
alter table public.sales
  add column if not exists diambil_at timestamptz,
  add column if not exists foto_hasil_url text,
  add column if not exists diambil_oleh uuid;

comment on column public.sales.diambil_at is
  'Waktu kasir scan barcode konfirmasi customer sudah ambil kacamata.';
comment on column public.sales.foto_hasil_url is
  'Foto hasil pengerjaan saat serah terima (bukti kondisi baik).';

-- Kartu: boleh menunggu ambil; tanggal null sampai diaktifkan
alter table public.garansi_kartu
  drop constraint if exists garansi_kartu_status_check;

alter table public.garansi_kartu
  alter column tanggal_mulai drop not null,
  alter column tanggal_akhir drop not null;

alter table public.garansi_kartu
  add column if not exists foto_hasil_url text,
  add column if not exists diambil_at timestamptz,
  add column if not exists resep_awal text,
  add column if not exists klaim_digunakan boolean not null default false;

alter table public.garansi_kartu
  add constraint garansi_kartu_status_check
  check (status in ('menunggu_ambil', 'aktif', 'habis', 'diklaim', 'batal'));

-- Default status baru untuk insert berikutnya (app mengisi eksplisit)
alter table public.garansi_kartu
  alter column status set default 'menunggu_ambil';

-- Klaim: bukti cek lensa / kelalaian / resep recheck
alter table public.garansi_klaim
  add column if not exists sale_id uuid references public.sales (id) on delete cascade,
  add column if not exists kategori_masalah text
    check (kategori_masalah is null or kategori_masalah in (
      'ukuran_lensa',
      'kelalaian_customer',
      'cacat_pabrik',
      'lainnya'
    )),
  add column if not exists ukuran_sesuai_beli boolean,
  add column if not exists resep_awal text,
  add column if not exists resep_recheck text,
  add column if not exists resep_berbeda boolean;

-- Max 1 klaim per transaksi (sale) seumur hidup
create unique index if not exists garansi_klaim_one_per_sale_idx
  on public.garansi_klaim (sale_id)
  where sale_id is not null;

create index if not exists sales_diambil_at_idx on public.sales (diambil_at desc);

-- Storage foto hasil / klaim (public read, auth write)
insert into storage.buckets (id, name, public)
values ('garansi-photos', 'garansi-photos', true)
on conflict (id) do nothing;

drop policy if exists garansi_photos_public_read on storage.objects;
create policy garansi_photos_public_read on storage.objects
  for select using (bucket_id = 'garansi-photos');

drop policy if exists garansi_photos_auth_insert on storage.objects;
create policy garansi_photos_auth_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'garansi-photos');

drop policy if exists garansi_photos_auth_update on storage.objects;
create policy garansi_photos_auth_update on storage.objects
  for update to authenticated
  using (bucket_id = 'garansi-photos')
  with check (bucket_id = 'garansi-photos');

comment on table public.garansi_kartu is
  'Kartu garansi frame/lensa. Aktif 7 hari sejak scan ambil barang.';
comment on table public.garansi_klaim is
  'Klaim garansi 1x per sale. Lensa: ukuran cocok + resep recheck harus berbeda.';
