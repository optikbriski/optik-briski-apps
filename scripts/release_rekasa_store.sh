#!/usr/bin/env bash
# APK etalase Rekasa (katalog + beli + kontrak). Bukan APK kasir klien.
#   bash scripts/release_rekasa_store.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
export BRAND=rekasa
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"
OUT_DIR="build/app/outputs/flutter-apk"
DEST_ARM64="build/rekasa-store-${VERSION}.apk"
DEST_ARM32="build/rekasa-store-${VERSION}-armeabi-v7a.apk"

echo "==> Build Rekasa Store APK v${VERSION} (etalase, bukan kasir)"
DEFINE_ARGS=(
  --dart-define=APP_FLAVOR=store
  --dart-define=ADMIN_PIN_TENANT=false
  --dart-define=PIN_STORE_TENANT=false
)
if [[ -f .dart_define.admin.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.admin.json)
  DEFINE_ARGS+=(--dart-define=APP_FLAVOR=store)
elif [[ -f .dart_define.karyawan.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.karyawan.json)
  DEFINE_ARGS+=(--dart-define=APP_FLAVOR=store)
else
  [[ -n "${SUPABASE_URL:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi

FLUTTER_ARGS=(
  build apk --release --split-per-abi
  --flavor store
  --target-platform android-arm64,android-arm
  -t "lib/main_store.dart"
  --obfuscate --split-debug-info=build/app/outputs/symbols-store
  "${DEFINE_ARGS[@]}"
  -PstoreApplicationId="${STOREFRONT_APPLICATION_ID:-com.rekasa.store}"
  -PstoreAppName="${STOREFRONT_APP_NAME:-Rekasa}"
)
flutter "${FLUTTER_ARGS[@]}"

ARM64_SRC=""
for candidate in \
  "$OUT_DIR/app-arm64-v8a-store-release.apk" \
  "$OUT_DIR/app-store-arm64-v8a-release.apk"; do
  if [[ -f "$candidate" ]]; then ARM64_SRC="$candidate"; break; fi
done
if [[ -z "$ARM64_SRC" ]]; then
  echo "ERROR: APK arm64 Store tidak ditemukan di $OUT_DIR"
  ls -la "$OUT_DIR" || true
  exit 1
fi
cp -f "$ARM64_SRC" "$DEST_ARM64"
for candidate in \
  "$OUT_DIR/app-armeabi-v7a-store-release.apk" \
  "$OUT_DIR/app-store-armeabi-v7a-release.apk"; do
  if [[ -f "$candidate" ]]; then
    cp -f "$candidate" "$DEST_ARM32"
    break
  fi
done

echo ""
echo "APK etalase Rekasa (com.rekasa.store):"
ls -lh "$DEST_ARM64"
echo "Klien toko tetap pakai APK Admin/Karyawan/Member yang dibeli."
