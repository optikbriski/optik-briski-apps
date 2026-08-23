#!/usr/bin/env bash
# Build APK Member. Default merek = Rekasa. Kulit Optik: BRAND=optik-briski.
# Shrink hanya buang aset junk + model ML Kit yang tidak dipakai mode accurate.
# Bentuk (referensi wajah/frame) memakai aset foto + overlay — tanpa scan kamera.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"
# Flutter flavor output: build/app/outputs/flutter-apk/app-member-*.apk
OUT_DIR="build/app/outputs/flutter-apk"
if [[ "$STORE_SLUG" == "optik-briski" ]]; then
  DEST_ARM64="build/optik-member-${VERSION}.apk"
  DEST_ARM32="build/optik-member-${VERSION}-armeabi-v7a.apk"
else
  DEST_ARM64="build/${STORE_SLUG}-member-${VERSION}.apk"
  DEST_ARM32="build/${STORE_SLUG}-member-${VERSION}-armeabi-v7a.apk"
fi
# WA menampilkan MB desimal (1000). Target ketat: < 50.000.000 byte.
LIMIT=$((50 * 1000 * 1000))

echo "==> Build Member APK v${VERSION} merek ${STORE_DISPLAY_NAME} (${STORE_SLUG})"
DEFINE_ARGS=(
  --dart-define=APP_FLAVOR=member
  --dart-define=MEMBER_TENANT_SLUG="${MEMBER_TENANT_SLUG:-$STORE_SLUG}"
  --dart-define=PIN_STORE_TENANT="${STORE_PIN_TENANT:-false}"
)
if [[ -f .dart_define.member.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.member.json)
else
  [[ -n "${SUPABASE_URL:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && DEFINE_ARGS+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi
if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  DEFINE_ARGS+=(--dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY")
fi
bash "$ROOT/scripts/sync_google_maps_native_key.sh" || true

FLUTTER_ARGS=(
  build apk --release --split-per-abi
  --flavor member
  --target-platform android-arm64,android-arm
  -t "lib/main_member.dart"
  --obfuscate --split-debug-info=build/app/outputs/symbols-member
  "${DEFINE_ARGS[@]}"
)
if [[ -n "${STORE_MEMBER_APPLICATION_ID:-}" ]]; then
  FLUTTER_ARGS+=(-PstoreApplicationId="$STORE_MEMBER_APPLICATION_ID")
fi
if [[ -n "${STORE_MEMBER_APP_NAME:-}" ]]; then
  FLUTTER_ARGS+=(-PstoreAppName="$STORE_MEMBER_APP_NAME")
fi
flutter "${FLUTTER_ARGS[@]}"

ARM64_SRC=""
for candidate in \
  "$OUT_DIR/app-arm64-v8a-member-release.apk" \
  "$OUT_DIR/app-member-arm64-v8a-release.apk" \
  "$OUT_DIR/app-arm64-v8a-release.apk"; do
  if [[ -f "$candidate" ]]; then ARM64_SRC="$candidate"; break; fi
done
if [[ -z "$ARM64_SRC" ]]; then
  echo "ERROR: APK arm64 tidak ditemukan di $OUT_DIR"
  ls -la "$OUT_DIR" || true
  exit 1
fi
echo "==> Sumber arm64: $ARM64_SRC"
cp -f "$ARM64_SRC" "$DEST_ARM64"

echo "==> Shrink (junk + OCR Member; packing aman <50MB)"
DROP_OCR=1 EXTRA_ASSET_RECOMPRESS=1 \
  bash "$ROOT/scripts/shrink_apk_for_supabase.sh" "$DEST_ARM64"

BYTES=$(stat -f%z "$DEST_ARM64" 2>/dev/null || stat -c%s "$DEST_ARM64")
python3 - <<PY
b=$BYTES
limit=$LIMIT
print(f"==> Ukuran akhir: {b/1e6:.3f} MB (WA) / {b/1024/1024:.3f} MiB  (limit {limit} byte)")
if b >= limit:
    raise SystemExit(f"ERROR: APK {b/1e6:.3f} MB masih >= 50 MB — jangan kirim/upload.")
print("==> OK di bawah 50 MB — aman kirim WA / upload Supabase Free")
PY

for candidate in \
  "$OUT_DIR/app-armeabi-v7a-member-release.apk" \
  "$OUT_DIR/app-member-armeabi-v7a-release.apk" \
  "$OUT_DIR/app-armeabi-v7a-release.apk"; do
  if [[ -f "$candidate" ]]; then
    cp -f "$candidate" "$DEST_ARM32"
    break
  fi
done

echo ""
echo "==> APK utama (arm64) — kirim via WA:"
ls -lh "$DEST_ARM64"
echo "Path: $ROOT/$DEST_ARM64"
echo ""
echo "Catatan: OCR KTP tidak ada di Member (fitur Karyawan). QR tetap."
echo "Setelah uji WA: bash scripts/publish_member_apk.sh"
