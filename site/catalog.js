/* Harga & modul sama dengan lib/shared/tenant/store_catalog.dart + module_catalog.dart */
window.REKASA_CATALOG = {
  whiteLabelAddonIdr: 200000,
  plans: {
    paket_c: { key: "paket_c", label: "Paket C — Starter", short: "Paket C", eyebrow: "Starter", highlight: "Hemat", priceIdr: 250000, whiteLabel: false, blurb: "Mulai jalan. Kulit Rekasa + kode usaha." },
    paket_b: { key: "paket_b", label: "Paket B — Bisnis", short: "Paket B", eyebrow: "Bisnis", highlight: "Laku", priceIdr: 450000, whiteLabel: false, blurb: "Operasional lebih lengkap. Masih kulit Rekasa." },
    paket_a: { key: "paket_a", label: "Paket A — Pro", short: "Paket A", eyebrow: "Pro", highlight: "Tertinggi", priceIdr: 750000, whiteLabel: true, blurb: "Paket tertinggi: modul penuh bidang ini + merek sendiri." }
  },
  modules: {
    pos: { key: "pos", label: "POS / Kasir", summary: "Nota cepat, DP, struk, dan antrian toko.", addOnPriceIdr: 50000 },
    master_data: { key: "master_data", label: "Master data barang", summary: "SKU, harga, stok awal, dan katalog toko.", addOnPriceIdr: 50000 },
    member_app: { key: "member_app", label: "Aplikasi Member", summary: "Pelanggan lihat pesanan, poin, dan garansi.", addOnPriceIdr: 75000 },
    history_dp: { key: "history_dp", label: "Riwayat DP / nota", summary: "Lacak uang muka dan sisa tagihan pelanggan toko.", addOnPriceIdr: 40000 },
    logistics: { key: "logistics", label: "Logistik / stok antar toko", summary: "Pindah barang pusat ↔ cabang, stok real.", addOnPriceIdr: 60000 },
    warranty: { key: "warranty", label: "Garansi", summary: "Klaim garansi dengan batas waktu.", addOnPriceIdr: 50000 },
    attendance: { key: "attendance", label: "Absensi & geofence", summary: "Hadir di lokasi toko, jadwal, dan pantauan.", addOnPriceIdr: 60000 },
    finance: { key: "finance", label: "Keuangan / buku besar", summary: "Jurnal, periode, dan laporan owner.", addOnPriceIdr: 80000 },
    online_orders: { key: "online_orders", label: "Pesanan online", summary: "Order dari member, ongkir, dan pengiriman.", addOnPriceIdr: 80000 }
  },
  industries: [
    {
      key: "optik",
      label: "Optik / kacamata",
      blurb: "Kasir frame-lensa, resep, garansi, member.",
      labels: { pos: "POS / Kasir optik", master_data: "Master frame & lensa", member_app: "Aplikasi member optik", warranty: "Garansi frame/lensa" },
      plans: {
        paket_c: ["pos", "master_data", "member_app"],
        paket_b: ["pos", "master_data", "member_app", "logistics", "warranty", "attendance", "history_dp"],
        paket_a: ["pos", "master_data", "member_app", "logistics", "warranty", "attendance", "history_dp", "finance", "online_orders"]
      }
    },
    {
      key: "retail",
      label: "Toko retail / fashion",
      blurb: "Kasir barang, stok cabang, member, jualan online.",
      labels: { pos: "Kasir toko", master_data: "Master barang", member_app: "Aplikasi pelanggan" },
      plans: {
        paket_c: ["pos", "master_data", "member_app"],
        paket_b: ["pos", "master_data", "member_app", "logistics", "history_dp", "attendance"],
        paket_a: ["pos", "master_data", "member_app", "logistics", "history_dp", "attendance", "finance", "online_orders"]
      }
    },
    {
      key: "fnb",
      label: "Kafe / resto / F&B",
      blurb: "Kasir menu, stok bahan antar outlet, pelanggan.",
      hide: ["warranty"],
      labels: { pos: "Kasir / meja", master_data: "Menu & bahan", member_app: "Pelanggan / loyalty", online_orders: "Pesan antar / pickup" },
      plans: {
        paket_c: ["pos", "master_data", "member_app"],
        paket_b: ["pos", "master_data", "member_app", "attendance", "history_dp", "logistics"],
        paket_a: ["pos", "master_data", "member_app", "attendance", "history_dp", "logistics", "finance", "online_orders"]
      }
    },
    {
      key: "jasa",
      label: "Jasa (salon, laundry, studio)",
      blurb: "Transaksi layanan, daftar jasa, klien, DP booking.",
      labels: { pos: "Transaksi jasa", master_data: "Daftar layanan", member_app: "Aplikasi klien" },
      plans: {
        paket_c: ["pos", "master_data", "member_app"],
        paket_b: ["pos", "master_data", "member_app", "history_dp", "attendance"],
        paket_a: ["pos", "master_data", "member_app", "history_dp", "attendance", "finance"]
      }
    },
    {
      key: "bengkel",
      label: "Bengkel / otomotif",
      blurb: "Kasir servis, sparepart, DP, garansi pengerjaan.",
      labels: { pos: "Kasir servis", master_data: "Sparepart & jasa", warranty: "Garansi servis" },
      plans: {
        paket_c: ["pos", "master_data", "history_dp"],
        paket_b: ["pos", "master_data", "history_dp", "warranty", "attendance", "logistics"],
        paket_a: ["pos", "master_data", "history_dp", "warranty", "attendance", "logistics", "member_app", "finance"]
      }
    },
    {
      key: "klinik",
      label: "Klinik / praktik",
      blurb: "Kasir tindakan, daftar layanan, rekam klien, DP.",
      labels: { pos: "Kasir klinik", master_data: "Layanan & item", member_app: "Aplikasi klien" },
      plans: {
        paket_c: ["pos", "master_data", "member_app"],
        paket_b: ["pos", "master_data", "member_app", "history_dp", "attendance"],
        paket_a: ["pos", "master_data", "member_app", "history_dp", "attendance", "finance"]
      }
    },
    {
      key: "grosir",
      label: "Grosir / distributor",
      blurb: "Kasir partai, stok gudang, piutang, keuangan.",
      labels: { pos: "Kasir / nota grosir", master_data: "Master SKU gudang" },
      plans: {
        paket_c: ["pos", "master_data", "logistics"],
        paket_b: ["pos", "master_data", "logistics", "history_dp", "attendance", "finance"],
        paket_a: ["pos", "master_data", "logistics", "history_dp", "attendance", "finance", "member_app", "online_orders"]
      }
    },
    {
      key: "umum",
      label: "Usaha umum",
      blurb: "Belum masuk kategori di atas. Nyalakan fitur sesuai kebutuhan.",
      labels: { pos: "Kasir / transaksi", master_data: "Master item" },
      plans: {
        paket_c: ["pos", "master_data"],
        paket_b: ["pos", "master_data", "member_app", "attendance", "history_dp"],
        paket_a: ["pos", "master_data", "member_app", "attendance", "history_dp", "finance", "logistics", "online_orders"]
      }
    }
  ]
};
