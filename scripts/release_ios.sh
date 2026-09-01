#!/usr/bin/env bash
# Build IPA iOS — fitur sama APK (target Dart + dart-define identik).
# Tidak mengubah Android. Tidak memotong plugin/fitur.
#
#   APP=admin|karyawan|member
#   BRAND=optik-briski|rekasa
#
# Contoh:
#   BRAND=optik-briski APP=admin bash scripts/release_ios.sh
#   BRAND=optik-briski bash scripts/release_admin_ios.sh
#
# Pasang di iPhone butuh akun Apple Developer (signing). Tanpa itu skrip
# tetap menghasilkan .app unsigned di build/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${APP:-admin}"
case "$APP" in
  admin|karyawan|member) ;;
  *)
    echo "ERROR: APP harus admin, karyawan, atau member (dapat: $APP)"
    exit 1
    ;;
esac

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"

ios_bundle_id() {
  # iOS: huruf, angka, titik, strip. Underscore Android tidak valid.
  echo "$1" | tr '_' '-' | tr '[:upper:]' '[:lower:]'
}

case "$APP" in
  admin)
    TARGET="lib/main_admin.dart"
    DISPLAY_NAME="${STORE_ADMIN_APP_NAME:-$STORE_DISPLAY_NAME Admin}"
    RAW_ID="${STORE_ADMIN_APPLICATION_ID:-com.rekasa.admin}"
    DEFINE_FILE=".dart_define.admin.json"
    EXTRA_DEFINES=(
      --dart-define=APP_FLAVOR=admin
      --dart-define=ADMIN_PIN_TENANT="${STORE_PIN_TENANT:-false}"
      --dart-define=ADMIN_TENANT_SLUG="${ADMIN_TENANT_SLUG:-$STORE_SLUG}"
    )
    ;;
  karyawan)
    TARGET="lib/main_karyawan.dart"
    DISPLAY_NAME="${STORE_KARYAWAN_APP_NAME:-$STORE_DISPLAY_NAME Karyawan}"
    RAW_ID="${STORE_KARYAWAN_APPLICATION_ID:-com.rekasa.karyawan}"
    DEFINE_FILE=".dart_define.karyawan.json"
    EXTRA_DEFINES=(
      --dart-define=APP_FLAVOR=karyawan
      --dart-define=PIN_STORE_TENANT="${STORE_PIN_TENANT:-false}"
      --dart-define=KARYAWAN_TENANT_SLUG="${KARYAWAN_TENANT_SLUG:-$STORE_SLUG}"
    )
    ;;
  member)
    TARGET="lib/main_member.dart"
    DISPLAY_NAME="${STORE_MEMBER_APP_NAME:-$STORE_DISPLAY_NAME}"
    RAW_ID="${STORE_MEMBER_APPLICATION_ID:-com.rekasa.member}"
    DEFINE_FILE=".dart_define.member.json"
    EXTRA_DEFINES=(
      --dart-define=APP_FLAVOR=member
      --dart-define=PIN_STORE_TENANT="${STORE_PIN_TENANT:-false}"
      --dart-define=MEMBER_TENANT_SLUG="${MEMBER_TENANT_SLUG:-$STORE_SLUG}"
    )
    ;;
esac

BUNDLE_ID="$(ios_bundle_id "$RAW_ID")"
if [[ "$STORE_SLUG" == "optik-briski" ]]; then
  DEST_IPA="build/optik-${APP}-${VERSION}.ipa"
else
  DEST_IPA="build/${STORE_SLUG}-${APP}-${VERSION}.ipa"
fi
DEST_APP="${DEST_IPA%.ipa}.app"

DEFINE_ARGS=("${EXTRA_DEFINES[@]}")
if [[ -f "$DEFINE_FILE" ]]; then
  DEFINE_ARGS+=(--dart-define-from-file="$DEFINE_FILE")
elif [[ -f .dart_define.admin.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.admin.json)
  DEFINE_ARGS+=("${EXTRA_DEFINES[@]}")
elif [[ -f .dart_define.karyawan.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.karyawan.json)
  DEFINE_ARGS+=("${EXTRA_DEFINES[@]}")
fi
DEFINE_ARGS+=("${EXTRA_DEFINES[@]}")
if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  DEFINE_ARGS+=(--dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY")
fi

# Tulis overlay Xcode (di-gitignore). Default Runner tetap Rekasa jika file ini tidak ada.
cat > "$ROOT/ios/Flutter/Flavor.xcconfig" <<EOF
APP_BUNDLE_ID=${BUNDLE_ID}
APP_DISPLAY_NAME=${DISPLAY_NAME}
PRODUCT_BUNDLE_IDENTIFIER=${BUNDLE_ID}
EOF

bash "$ROOT/scripts/sync_google_maps_native_key.sh" || true

echo "==> Build iOS ${APP} v${VERSION} merek ${STORE_DISPLAY_NAME} (${STORE_SLUG})"
echo "    bundle ${BUNDLE_ID}"
echo "    target ${TARGET}"

FLUTTER_ARGS=(
  -t "$TARGET"
  --release
  --obfuscate
  --split-debug-info="build/ios/symbols-${APP}"
  "${DEFINE_ARGS[@]}"
)

mkdir -p build

build_unsigned() {
  echo "==> Signing Apple tidak tersedia / gagal — build unsigned (.app), fitur tetap penuh."
  flutter build ios "${FLUTTER_ARGS[@]}" --no-codesign
  local src=""
  for candidate in \
    "build/ios/iphoneos/Runner.app" \
    "build/ios/Release-iphoneos/Runner.app"; do
    if [[ -d "$candidate" ]]; then src="$candidate"; break; fi
  done
  if [[ -z "$src" ]]; then
    echo "ERROR: Runner.app tidak ditemukan."
    find build/ios -name 'Runner.app' -type d | head
    exit 1
  fi
  rm -rf "$DEST_APP"
  cp -R "$src" "$DEST_APP"
  echo "==> Unsigned: $DEST_APP"
  echo "Pasang ke iPhone: buka ios/Runner.xcworkspace di Xcode, pilih Team Apple Developer, Product → Archive."
}

if [[ "${IOS_NO_CODESIGN:-0}" == "1" ]]; then
  build_unsigned
else
  set +e
  flutter build ipa "${FLUTTER_ARGS[@]}"
  ipa_status=$?
  set -e
  if [[ "$ipa_status" -eq 0 ]]; then
    SRC_IPA=""
    for candidate in \
      "build/ios/ipa/"*.ipa \
      "build/ios/ipa/Runner.ipa"; do
      if [[ -f "$candidate" ]]; then SRC_IPA="$candidate"; break; fi
    done
    if [[ -n "$SRC_IPA" ]]; then
      cp -f "$SRC_IPA" "$DEST_IPA"
      echo "==> IPA: $DEST_IPA"
      ls -lh "$DEST_IPA"
    else
      echo "Build ipa OK tapi file .ipa tidak ketemu di build/ios/ipa/"
      ls -la build/ios/ipa/ || true
      exit 1
    fi
  else
    build_unsigned
  fi
fi

echo ""
echo "Android tidak diubah. Update in-app APK tetap Android-only."
echo "iOS sebar lewat TestFlight / App Store (bukan WA .apk)."
echo "Selesai: $DEST_IPA (jika signing ada) atau $DEST_APP (unsigned)."
