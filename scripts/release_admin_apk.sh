#!/usr/bin/env bash
# Build APK Admin untuk tablet/HP toko (Absensi Toko + face match ML Kit).
# Admin production utama tetap web (Vercel); APK ini khusus perangkat toko.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"
OUT_DIR="build/app/outputs/flutter-apk"
if [[ "$STORE_SLUG" == "optik-briski" ]]; then
  DEST_ARM64="build/optik-admin-${VERSION}.apk"
  DEST_ARM32="build/optik-admin-${VERSION}-armeabi-v7a.apk"
else
  DEST_ARM64="build/${STORE_SLUG}-admin-${VERSION}.apk"
  DEST_ARM32="build/${STORE_SLUG}-admin-${VERSION}-armeabi-v7a.apk"
fi

echo "==> Build Admin APK v${VERSION} merek ${STORE_DISPLAY_NAME} (${STORE_SLUG})"
DEFINE_ARGS=(
  --dart-define=APP_FLAVOR=admin
  --dart-define=ADMIN_PIN_TENANT="${STORE_PIN_TENANT:-true}"
  --dart-define=ADMIN_TENANT_SLUG="${ADMIN_TENANT_SLUG:-$STORE_SLUG}"
)
if [[ -f .dart_define.admin.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.admin.json)
elif [[ -f .dart_define.karyawan.json ]]; then
  # Sering share Supabase URL/key dengan karyawan.
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.karyawan.json)
  DEFINE_ARGS+=(--dart-define=APP_FLAVOR=admin)
else
  [[ -n "${SUPABASE_URL:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi
DEFINE_ARGS+=(
  --dart-define=ADMIN_PIN_TENANT="${STORE_PIN_TENANT:-true}"
  --dart-define=ADMIN_TENANT_SLUG="${ADMIN_TENANT_SLUG:-$STORE_SLUG}"
)

FLUTTER_ARGS=(
  build apk --release --split-per-abi
  --flavor admin
  --target-platform android-arm64,android-arm
  -t "lib/main_admin.dart"
  --obfuscate --split-debug-info=build/app/outputs/symbols-admin
  "${DEFINE_ARGS[@]}"
)
if [[ -n "${STORE_ADMIN_APPLICATION_ID:-}" ]]; then
  FLUTTER_ARGS+=(-PstoreApplicationId="$STORE_ADMIN_APPLICATION_ID")
fi
if [[ -n "${STORE_ADMIN_APP_NAME:-}" ]]; then
  FLUTTER_ARGS+=(-PstoreAppName="$STORE_ADMIN_APP_NAME")
fi
flutter "${FLUTTER_ARGS[@]}"

ARM64_SRC=""
for candidate in \
  "$OUT_DIR/app-arm64-v8a-admin-release.apk" \
  "$OUT_DIR/app-admin-arm64-v8a-release.apk" \
  "$OUT_DIR/app-arm64-v8a-release.apk"; do
  if [[ -f "$candidate" ]]; then ARM64_SRC="$candidate"; break; fi
done
if [[ -z "$ARM64_SRC" ]]; then
  echo "ERROR: APK arm64 Admin tidak ditemukan di $OUT_DIR"
  ls -la "$OUT_DIR" || true
  exit 1
fi
cp -f "$ARM64_SRC" "$DEST_ARM64"
for candidate in \
  "$OUT_DIR/app-armeabi-v7a-admin-release.apk" \
  "$OUT_DIR/app-admin-armeabi-v7a-release.apk" \
  "$OUT_DIR/app-armeabi-v7a-release.apk"; do
  if [[ -f "$candidate" ]]; then
    cp -f "$candidate" "$DEST_ARM32"
    break
  fi
done

echo ""
echo "==> APK Admin toko (arm64):"
ls -lh "$DEST_ARM64"
if [[ -f "$DEST_ARM32" ]]; then
  echo "==> APK cadangan (armeabi-v7a):"
  ls -lh "$DEST_ARM32"
fi
echo ""
echo "Pasang di tablet/HP Admin toko → login Admin → menu Absensi Toko."
echo "Face match memakai kamera perangkat ini + geofence toko."
echo "Admin web (Vercel) tetap untuk POS/monitor; face match tidak jalan di browser."
