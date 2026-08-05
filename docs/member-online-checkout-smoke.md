# Smoke: Belanja Online Member → finance cabang

## Prasyarat
1. Jalankan migration online checkout + align E2E:
   - `supabase/migrations/20260728000003_member_online_checkout.sql`
   - `supabase/migrations/20260805000001_online_orders_e2e_align.sql`
   - `supabase/migrations/20260805000002_online_orders_e2e_harden.sql`
     (pickup tanpa alamat, tracking `DIPROSES_DI_CABANG`, list/get phone `wa_digits`, fulfill harden).
2. Redeploy Edge: `online-checkout-create` (item_details = total setelah voucher), `biteship-create-order` (guard status + alert).
2. (Opsional produksi) Deploy Edge + set secrets:
   - `MIDTRANS_SERVER_KEY`
   - `MIDTRANS_CLIENT_KEY`
   - `MIDTRANS_IS_PRODUCTION`
   - `SUPABASE_SERVICE_ROLE_KEY` (otomatis di Edge)
3. Pastikan cabang punya baris `toko_delivery_settings` (auto-seed) dan stok produk (SKU sama dengan katalog PUSAT) di `products` cabang.

## Path A — Pickup + bayar uji (tanpa Midtrans)
1. Member APK: login → Belanja Online → keranjang → **Detail pesanan**.
2. Pilih **Ambil di toko** + cabang (alamat Maps opsional) → Checkout → Bayar.
3. Dialog **Bayar uji** → konfirmasi.
4. Cek:
   - `online_orders.status = paid`, `sale_id` terisi
   - `sales.channel = member_online`, `tracking_status = DIPROSES_DI_CABANG`, `status_pembayaran = LUNAS`
   - `finance_transactions` PEMASUKAN kategori `Penjualan Online Member` di `toko_id` yang sama
   - Tab Pesanan Member: nota Online; sebelum bayar: kartu “Menunggu pembayaran”
   - Beranda: reminder “Belum dibayar” jika checkout belum lunas

## Path B — Delivery + ongkir
1. Detail pesanan → **Kirim ke alamat** (alamat Maps wajib) → kurir OBR/Biteship → Checkout → Bayar uji.
2. Cek `online_orders.shipping_fee` + `sales.total_harga` = subtotal + ongkir − voucher.
3. Admin → **Pesanan Online** → tab Proses → Dikemas → Resi manual / Panggil Biteship → Selesai.
4. Member label tracking: “Dalam pengiriman” saat `DIKIRIM`.

## Path C — Midtrans nyata
1. Set secrets Edge, deploy `online-checkout-create` + `online-midtrans-webhook`.
2. Di Midtrans dashboard, webhook URL:
   `https://<project>.supabase.co/functions/v1/online-midtrans-webhook`
3. Checkout Member membuka Snap; setelah settlement, webhook memanggil `fulfill_online_order_payment`.
