# Rekasa

Satu codebase, satu Supabase. **REKASA KARYA INDONESIA** menjual mesin operasional UMKM.

**Optik B. Riski** adalah kulit tenant #1 (`brands/optik-briski.json`, `BRAND=optik-briski`). Bukan nama produk. Jangan ganti `applicationId` Optik di file itu.

Debug: `.vscode/launch.json` — **Admin / Karyawan / Member Rekasa** (kasir & operasi toko) plus **Rekasa Company (katalog)** (etalase paket, bukan POS). **Optik B. Riski** tetap sebagai kulit pelanggan #1 (jangan hapus `brands/optik-briski.json` / `applicationId`-nya).

- Etalase Mac/debug: pilih **Rekasa Company (katalog)** — tanpa `--flavor` (Xcode hanya punya scheme Runner).
- Etalase Android release: `bash scripts/release_rekasa_store.sh`
- APK Rekasa (kode usaha): `bash scripts/release_rekasa_ops.sh`
- APK Optik (kulit): `BRAND=optik-briski bash scripts/release_admin_apk.sh`
