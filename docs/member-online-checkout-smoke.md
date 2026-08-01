# Smoke: Belanja Online Member → finance cabang

## Prasyarat
1. Jalankan migration `supabase/migrations/20260728000003_member_online_checkout.sql` di SQL Editor.
2. (Opsional produksi) Deploy Edge + set secrets:
   - `MIDTRANS_SERVER_KEY`
   - `MIDTRANS_CLIENT_KEY`
   - `MIDTRANS_IS_PRODUCTION`
   - `SUPABASE_SERVICE_ROLE_KEY` (otomatis di Edge)
3. Pastikan cabang punya baris `toko_delivery_settings` (auto-seed) dan stok produk (SKU sama dengan katalog PUSAT) di `products` cabang.

## Path A — Pickup + bayar uji (tanpa Midtrans)
1. Member APK: login → Katalog → tambah Frame/aksesoris (bukan Lensa) ke keranjang.
2. Checkout → pilih cabang → **Ambil di toko** → Bayar.
3. Dialog **Bayar uji** → konfirmasi.
4. Cek:
   - `online_orders.status = paid`, `sale_id` terisi
   - `sales.channel = member_online`, `toko_id` = cabang dipilih, `status_pembayaran = LUNAS`
   - `finance_transactions` PEMASUKAN kategori `Penjualan Online Member` di `toko_id` yang sama
   - Pesanan muncul di tab Pesanan Member

## Path B — Delivery + ongkir
1. Checkout → **Kirim** → kurir Grab/Gojek/Lainnya → isi alamat → Bayar uji.
2. Cek `online_orders.shipping_fee` + `sales.total_harga` = subtotal + ongkir.
3. Admin → **Pesanan Online** → Dikemas → Diserahkan kurir (+ isi resi) → Selesai.

## Path C — Midtrans nyata
1. Set secrets Edge, deploy `online-checkout-create` + `online-midtrans-webhook`.
2. Di Midtrans dashboard, webhook URL:
   `https://<project>.supabase.co/functions/v1/online-midtrans-webhook`
3. Checkout Member membuka Snap; setelah settlement, webhook memanggil `fulfill_online_order_payment`.
