#!/usr/bin/env bash
# Upload APK Admin ke bucket public app-releases.
#
# Upload saja sudah cukup — trigger Storage otomatis upsert public.versi_app
# (app_flavor=admin). App Admin membaca baris itu untuk update in-app.
#
# Wajib env:
#   SUPABASE_URL=https://xxxx.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY=eyJ...
#
# Opsional:
#   APK_PATH=build/optik-admin-1.3.4.apk   # pakai publish_optik_admin_apk.sh
#   APK_PATH=build/rekasa-admin-1.3.4.apk  # default BRAND=rekasa
#   FORCE_UPDATE=false
#   CATATAN='...'
#   MANUAL_VERSI_APP=1
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
if [[ "$STORE_SLUG" == "rekasa" ]]; then
  echo "NOTE: upload saluran Rekasa (rekasa-admin-*)."
  echo "      Tablet Optik Admin butuh: bash scripts/publish_optik_admin_apk.sh"
  echo ""
fi
APK_PATH="${APK_PATH:-build/${FILE_PREFIX}-admin-${VERSION}.apk}"
OBJECT_NAME="${FILE_PREFIX}-admin-${VERSION}.apk"
FORCE_UPDATE="${FORCE_UPDATE:-false}"
CATATAN="${CATATAN:-${STORE_DISPLAY_NAME} Admin ${VERSION}: i18n ID/EN, perbaikan picker & update in-app.}"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "ERROR: set SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY dulu."
  echo "  export SUPABASE_URL='https://ualqiiprtjysdmtqkpzr.supabase.co'"
  echo "  export SUPABASE_SERVICE_ROLE_KEY='...service_role...'"
  echo "  bash scripts/publish_admin_apk.sh"
  exit 1
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "ERROR: APK tidak ada: $APK_PATH"
  echo "Build dulu: bash scripts/release_admin_apk.sh"
  exit 1
fi

BYTES=$(stat -f%z "$APK_PATH" 2>/dev/null || stat -c%s "$APK_PATH")
if [[ "$BYTES" -ge $((50 * 1000 * 1000)) ]]; then
  echo "ERROR: APK ${BYTES} byte masih >= 50 MB. Jangan upload."
  exit 1
fi

BASE="${SUPABASE_URL%/}"
PUBLIC_URL="${BASE}/storage/v1/object/public/app-releases/${OBJECT_NAME}"

echo "==> Pastikan bucket app-releases ada…"
curl -sS -X POST "${BASE}/storage/v1/bucket" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"id":"app-releases","name":"app-releases","public":true,"file_size_limit":157286400}' \
  >/tmp/optik-bucket-create.json || true
cat /tmp/optik-bucket-create.json
echo ""

echo "==> Upload ${APK_PATH} → app-releases/${OBJECT_NAME}"
HTTP=$(curl -sS -o /tmp/optik-apk-upload.json -w "%{http_code}" \
  -X POST "${BASE}/storage/v1/object/app-releases/${OBJECT_NAME}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/vnd.android.package-archive" \
  -H "x-upsert: true" \
  --data-binary @"${APK_PATH}")
echo "HTTP ${HTTP}"
cat /tmp/optik-apk-upload.json
echo ""
if [[ "$HTTP" != "200" && "$HTTP" != "201" ]]; then
  echo "ERROR: upload gagal"
  exit 1
fi

echo "==> Cek URL publik…"
CODE=$(curl -sS -o /dev/null -w "%{http_code}" -I "$PUBLIC_URL" || true)
echo "HEAD ${PUBLIC_URL} → ${CODE}"

if [[ "${MANUAL_VERSI_APP:-0}" == "1" ]]; then
  echo "==> MANUAL_VERSI_APP=1 → upsert REST versi_app (flavor=admin, versi=${VERSION})"
  curl -sS -X DELETE \
    "${BASE}/rest/v1/versi_app?app_flavor=eq.admin&versi_terbaru=eq.${VERSION}&tenant_slug=eq.${STORE_SLUG}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Prefer: return=minimal" >/dev/null || true

  curl -sS -X POST "${BASE}/rest/v1/versi_app" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$(python3 - <<PY
import json
print(json.dumps({
  "versi_terbaru": "${VERSION}",
  "url_download": "${PUBLIC_URL}",
  "force_update": ${FORCE_UPDATE},
  "catatan_rilis": """${CATATAN}""",
  "app_flavor": "admin",
  "tenant_slug": "${STORE_SLUG}",
}))
PY
)"
  echo ""
else
  echo "==> Skip REST versi_app (trigger Storage sync otomatis)."
  echo "    Set MANUAL_VERSI_APP=1 jika perlu force_update/catatan via script."
fi

echo ""
echo "OK. Upload selesai → app Admin membaca versi terbaru dari versi_app."
echo "URL: ${PUBLIC_URL}"
echo "Cek: select * from public.versi_app where app_flavor='admin' order by created_at desc limit 3;"
