#!/usr/bin/env bash
# Build APK Admin (fitur penuh sama web Admin; sinkron Supabase dengan APK lain).
# Default merek = Rekasa. Kulit Optik: BRAND=optik-briski.
# Web Vercel tetap jalan; APK untuk kasir toko (Bluetooth thermal, kamera, dll).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"

python3 "$ROOT/scripts/generate_flavor_launcher_icons.py"

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
  --dart-define=ADMIN_PIN_TENANT="${STORE_PIN_TENANT:-false}"
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
  --dart-define=ADMIN_PIN_TENANT="${STORE_PIN_TENANT:-false}"
  --dart-define=ADMIN_TENANT_SLUG="${ADMIN_TENANT_SLUG:-$STORE_SLUG}"
)
if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  DEFINE_ARGS+=(--dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY")
fi
bash "$ROOT/scripts/sync_google_maps_native_key.sh" || true

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

# Lolos WA / Supabase Free 50 MB. Shrink hanya jika perlu — repack+resign
# kadang bikin sideload gagal di beberapa HP/tablet meski apksigner OK.
LIMIT=$((50 * 1000 * 1000))
PRE_BYTES=$(stat -f%z "$DEST_ARM64" 2>/dev/null || stat -c%s "$DEST_ARM64")
if [[ "$PRE_BYTES" -lt "$LIMIT" && "${FORCE_SHRINK:-0}" != "1" ]]; then
  echo "==> Skip shrink (${PRE_BYTES} byte < ${LIMIT}) — pakai APK build langsung (lebih aman sideload)"
else
  echo "==> Shrink APK (>= limit atau FORCE_SHRINK=1)…"
  DROP_MEMBER_ASSETS=1 EXTRA_ASSET_RECOMPRESS=1 \
    bash "$ROOT/scripts/shrink_apk_for_supabase.sh" "$DEST_ARM64"
fi

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
echo "Pasang di tablet/HP Admin toko → login Admin → menu Toko → Update APK."
echo "Publish update in-app: BRAND=${BRAND:-rekasa} bash scripts/publish_admin_apk.sh"
echo "  (upload ke app-releases → versi_app flavor=admin terisi otomatis)."
echo "Face match memakai kamera perangkat ini + geofence toko."
echo "Admin web (Vercel) tetap untuk POS/monitor; face match tidak jalan di browser."
