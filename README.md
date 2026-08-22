# Rekasa

Satu codebase, satu Supabase. **REKASA KARYA INDONESIA** menjual mesin operasional UMKM.

**Optik B. Riski** adalah kulit tenant #1 (`brands/optik-briski.json`, `BRAND=optik-briski`). Bukan nama produk. Jangan ganti `applicationId` Optik di file itu.

Debug (milik Rekasa): salin `.vscode/launch.json.example` → `.vscode/launch.json`, lalu pilih **Rekasa Etalase / Admin / Karyawan / Member**. Kulit Optik = pilihan terpisah, bukan default.

- Etalase: `flutter run -t lib/main_store.dart --flavor store --dart-define=APP_FLAVOR=store --dart-define-from-file=.dart_define.admin.json`
- APK Rekasa (kode usaha): `bash scripts/release_rekasa_ops.sh`
- APK Optik (kulit): `BRAND=optik-briski bash scripts/release_admin_apk.sh`
