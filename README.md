# Rekasa

Satu codebase, satu Supabase. **REKASA KARYA INDONESIA** menjual mesin operasional UMKM.

**Optik B. Riski** adalah kulit tenant #1 (`brands/optik-briski.json`, `BRAND=optik-briski`). Bukan nama produk. Jangan ganti `applicationId` Optik di file itu.

- Etalase: `flutter run -t lib/main_store.dart --dart-define=APP_FLAVOR=store`
- APK Rekasa (kode usaha): `bash scripts/release_rekasa_ops.sh`
- APK Optik (kulit): `BRAND=optik-briski bash scripts/release_admin_apk.sh`
