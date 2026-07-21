#!/usr/bin/env bash
# Build APK Karyawan (split per-ABI = lebih kecil, kualitas sama) + petunjuk publish.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
OUT_DIR="build/app/outputs/flutter-apk"
DEST_ARM64="build/optik-karyawan-${VERSION}.apk"
DEST_ARM32="build/optik-karyawan-${VERSION}-armeabi-v7a.apk"

echo "==> Build Karyawan APK v${VERSION} (split per-ABI, tanpa x86 emulator)"
DEFINE_ARGS=(--dart-define=APP_FLAVOR=karyawan)
if [[ -f .dart_define.karyawan.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.karyawan.json)
else
  [[ -n "${SUPABASE_URL:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi

FLUTTER_ARGS=(
  build apk --release --split-per-abi
  --target-platform android-arm64,android-arm
  -t "lib/main_karyawan.dart"
  --obfuscate --split-debug-info=build/app/outputs/symbols
  "${DEFINE_ARGS[@]}"
)
flutter "${FLUTTER_ARGS[@]}"

# HP modern (2018+) hampir semua arm64 — ini yang dibagikan.
cp -f "$OUT_DIR/app-arm64-v8a-release.apk" "$DEST_ARM64"
# Lolos Supabase Free 50MB: buang aset non-Android / tidak dipakai (kualitas fitur tetap).
bash "$ROOT/scripts/shrink_apk_for_supabase.sh" "$DEST_ARM64"
# HP lama 32-bit (opsional)
if [[ -f "$OUT_DIR/app-armeabi-v7a-release.apk" ]]; then
  cp -f "$OUT_DIR/app-armeabi-v7a-release.apk" "$DEST_ARM32"
fi

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
echo "   Nama wajib: optik-karyawan-${VERSION}.apk"
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
