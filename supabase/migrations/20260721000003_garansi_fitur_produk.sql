-- =============================================================================
-- Klaim fitur produk gagal (anti-baret baret, bluechromic tidak berubah, dll)
-- → ganti barang sesuai spek yang dibeli. Jalankan setelah 000002.
-- =============================================================================

alter table public.garansi_kartu
  add column if not exists spesifikasi_produk text;

comment on column public.garansi_kartu.spesifikasi_produk is
  'Spek/fitur yang dijanjikan saat beli (jenis lensa, anti-baret, elastis, dll).';

alter table public.garansi_klaim
  drop constraint if exists garansi_klaim_kategori_masalah_check;

alter table public.garansi_klaim
  add constraint garansi_klaim_kategori_masalah_check
  check (kategori_masalah is null or kategori_masalah in (
    'ukuran_lensa',
    'kelalaian_customer',
    'cacat_pabrik',
    'fitur_tidak_berfungsi',
    'lainnya'
  ));

alter table public.garansi_klaim
  add column if not exists spesifikasi_pengganti text;

comment on column public.garansi_klaim.spesifikasi_pengganti is
  'Spek barang pengganti (harus sama dengan yang dibeli).';
