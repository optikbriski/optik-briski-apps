#!/usr/bin/env bash
# Build APK Karyawan. Default merek = Rekasa. Kulit Optik: BRAND=optik-briski.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"
OUT_DIR="build/app/outputs/flutter-apk"
if [[ "$STORE_SLUG" == "optik-briski" ]]; then
  DEST_ARM64="build/optik-karyawan-${VERSION}.apk"
  DEST_ARM32="build/optik-karyawan-${VERSION}-armeabi-v7a.apk"
else
  DEST_ARM64="build/${STORE_SLUG}-karyawan-${VERSION}.apk"
  DEST_ARM32="build/${STORE_SLUG}-karyawan-${VERSION}-armeabi-v7a.apk"
fi

echo "==> Build Karyawan APK v${VERSION} merek ${STORE_DISPLAY_NAME} (${STORE_SLUG})"
DEFINE_ARGS=(
  --dart-define=APP_FLAVOR=karyawan
  --dart-define=KARYAWAN_TENANT_SLUG="${KARYAWAN_TENANT_SLUG:-$STORE_SLUG}"
  --dart-define=PIN_STORE_TENANT="${STORE_PIN_TENANT:-false}"
)
if [[ -f .dart_define.karyawan.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.karyawan.json)
else
  [[ -n "${SUPABASE_URL:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi

FLUTTER_ARGS=(
  build apk --release --split-per-abi
  --flavor karyawan
  --target-platform android-arm64,android-arm
  -t "lib/main_karyawan.dart"
  --obfuscate --split-debug-info=build/app/outputs/symbols
  "${DEFINE_ARGS[@]}"
)
if [[ -n "${STORE_KARYAWAN_APPLICATION_ID:-}" ]]; then
  FLUTTER_ARGS+=(-PstoreApplicationId="$STORE_KARYAWAN_APPLICATION_ID")
fi
if [[ -n "${STORE_KARYAWAN_APP_NAME:-}" ]]; then
  FLUTTER_ARGS+=(-PstoreAppName="$STORE_KARYAWAN_APP_NAME")
fi
flutter "${FLUTTER_ARGS[@]}"

# HP modern (2018+) hampir semua arm64 — ini yang dibagikan.
ARM64_SRC=""
for candidate in \
  "$OUT_DIR/app-arm64-v8a-karyawan-release.apk" \
  "$OUT_DIR/app-karyawan-arm64-v8a-release.apk" \
  "$OUT_DIR/app-arm64-v8a-release.apk"; do
  if [[ -f "$candidate" ]]; then ARM64_SRC="$candidate"; break; fi
done
if [[ -z "$ARM64_SRC" ]]; then
  echo "ERROR: APK arm64 tidak ditemukan di $OUT_DIR"
  ls -la "$OUT_DIR" || true
  exit 1
fi
cp -f "$ARM64_SRC" "$DEST_ARM64"
# Lolos Supabase Free 50MB: buang aset non-Android / tidak dipakai (kualitas fitur tetap).
bash "$ROOT/scripts/shrink_apk_for_supabase.sh" "$DEST_ARM64"
# HP lama 32-bit (opsional)
for candidate in \
  "$OUT_DIR/app-armeabi-v7a-karyawan-release.apk" \
  "$OUT_DIR/app-karyawan-armeabi-v7a-release.apk" \
  "$OUT_DIR/app-armeabi-v7a-release.apk"; do
  if [[ -f "$candidate" ]]; then
    cp -f "$candidate" "$DEST_ARM32"
    break
  fi
done

echo ""
echo "==> APK utama (arm64, direkomendasikan):"
ls -lh "$DEST_ARM64"
if [[ -f "$DEST_ARM32" ]]; then
  echo "==> APK cadangan HP lama (armeabi-v7a):"
  ls -lh "$DEST_ARM32"
fi
echo ""
echo "Langkah publish update (tanpa kirim link ke karyawan):"
echo "1. Supabase → Storage → bucket public 'app-releases' (jika belum)"
echo "2. Upload file: $DEST_ARM64"
echo "Nama wajib: ${STORE_SLUG}-karyawan-${VERSION}.apk"
echo "3. Setelah migration auto-sync: selesai — versi_app terisi otomatis."
echo "   Atau: bash scripts/publish_karyawan_apk.sh (upload + mengandalkan trigger)"
echo ""
echo "Force update (opsional, SQL Editor):"
echo "  update public.versi_app set force_update = true"
echo "  where app_flavor = 'karyawan' and versi_terbaru = '${VERSION}';"
echo ""
echo "Catatan ukuran:"
echo "- Split ABI tidak menurunkan kualitas fitur/UI"
echo "- OCR wajah + KTP tetap ada (ML Kit) — itu yang bikin tetap puluhan MB"
echo "- Package name & signing key HARUS sama dengan yang terpasang"
