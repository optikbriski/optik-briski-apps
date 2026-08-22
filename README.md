# Rekasa

Satu codebase, satu Supabase. **REKASA KARYA INDONESIA** menjual mesin operasional UMKM.

**Optik B. Riski** adalah kulit tenant #1 (`brands/optik-briski.json`, `BRAND=optik-briski`). Bukan nama produk. Jangan ganti `applicationId` Optik di file itu.

Debug: `.vscode/launch.json` — **Admin / Karyawan / Member Rekasa**. **Optik B. Riski** tetap sebagai kulit pelanggan #1 (jangan hapus `brands/optik-briski.json` / `applicationId`-nya).

- Etalase: `flutter run -t lib/main_store.dart --flavor store --dart-define=APP_FLAVOR=store --dart-define-from-file=.dart_define.admin.json`
- APK Rekasa (kode usaha): `bash scripts/release_rekasa_ops.sh`
- APK Optik (kulit): `BRAND=optik-briski bash scripts/release_admin_apk.sh`
