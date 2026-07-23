#!/usr/bin/env bash
# Build APK Admin untuk tablet/HP toko (Absensi Toko + face match ML Kit).
# Admin production utama tetap web (Vercel); APK ini khusus perangkat toko.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
OUT_DIR="build/app/outputs/flutter-apk"
DEST_ARM64="build/optik-admin-${VERSION}.apk"
DEST_ARM32="build/optik-admin-${VERSION}-armeabi-v7a.apk"

echo "==> Build Admin APK v${VERSION} (tablet toko / Absensi Toko)"
DEFINE_ARGS=(--dart-define=APP_FLAVOR=admin)
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

FLUTTER_ARGS=(
  build apk --release --split-per-abi
  --target-platform android-arm64,android-arm
  -t "lib/main_admin.dart"
  --obfuscate --split-debug-info=build/app/outputs/symbols-admin
  "${DEFINE_ARGS[@]}"
)
flutter "${FLUTTER_ARGS[@]}"

cp -f "$OUT_DIR/app-arm64-v8a-release.apk" "$DEST_ARM64"
if [[ -f "$OUT_DIR/app-armeabi-v7a-release.apk" ]]; then
  cp -f "$OUT_DIR/app-armeabi-v7a-release.apk" "$DEST_ARM32"
fi

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
