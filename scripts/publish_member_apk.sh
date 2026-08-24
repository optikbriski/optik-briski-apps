#!/usr/bin/env bash
# Upload APK Member ke bucket public app-releases (+ auto-sync versi_app).
#
# Wajib env:
#   SUPABASE_URL=https://xxxx.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY=eyJ...
#
# Opsional:
#   APK_PATH=build/optik-member-1.3.1.apk
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"
if [[ "$STORE_SLUG" == "optik-briski" ]]; then
  FILE_PREFIX="optik"
else
  FILE_PREFIX="$STORE_SLUG"
fi
APK_PATH="${APK_PATH:-build/${FILE_PREFIX}-member-${VERSION}.apk}"
OBJECT_NAME="${FILE_PREFIX}-member-${VERSION}.apk"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "ERROR: set SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY dulu."
  echo "  export SUPABASE_URL='https://ualqiiprtjysdmtqkpzr.supabase.co'"
  echo "  export SUPABASE_SERVICE_ROLE_KEY='...service_role...'"
  echo "  bash scripts/publish_member_apk.sh"
  exit 1
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "ERROR: APK tidak ada: $APK_PATH"
  echo "Build dulu: bash scripts/release_member_apk.sh"
  exit 1
fi

BASE="${SUPABASE_URL%/}"
PUBLIC_URL="${BASE}/storage/v1/object/public/app-releases/${OBJECT_NAME}"

echo "==> Upload ${APK_PATH} → app-releases/${OBJECT_NAME}"
HTTP=$(curl -sS -o /tmp/optik-member-apk-upload.json -w "%{http_code}" \
  -X POST "${BASE}/storage/v1/object/app-releases/${OBJECT_NAME}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/vnd.android.package-archive" \
  -H "x-upsert: true" \
  --data-binary @"${APK_PATH}")
echo "HTTP ${HTTP}"
cat /tmp/optik-member-apk-upload.json
echo ""
if [[ "$HTTP" != "200" && "$HTTP" != "201" ]]; then
  echo "ERROR: upload gagal"
  exit 1
fi

echo "==> URL publik (nanti dipakai update in-app):"
echo "$PUBLIC_URL"
CODE=$(curl -sS -o /dev/null -w "%{http_code}" -I "$PUBLIC_URL" || true)
echo "HEAD → ${CODE}"
echo ""
echo "Selesai. Trigger Storage akan isi versi_app flavor=member (jika migration auto-sync sudah jalan)."
