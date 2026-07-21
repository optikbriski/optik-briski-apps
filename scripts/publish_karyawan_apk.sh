#!/usr/bin/env bash
# Upload APK Karyawan ke bucket public app-releases.
#
# Setelah migration 20260720000005_app_releases_auto_sync_versi.sql:
#   Upload saja sudah cukup — trigger Storage otomatis upsert public.versi_app
#   (versi_terbaru, url_download, app_flavor=karyawan, force_update=false).
#   Tidak perlu insert SQL manual ke versi_app.
#
# Wajib env:
#   SUPABASE_URL=https://xxxx.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY=eyJ...   (Dashboard → Settings → API → service_role)
#
# Opsional:
#   APK_PATH=build/optik-karyawan-1.2.7.apk
#   FORCE_UPDATE=false          # hanya dipakai jika MANUAL_VERSI_APP=1
#   CATATAN='...'                 # hanya dipakai jika MANUAL_VERSI_APP=1
#   MANUAL_VERSI_APP=1            # paksa REST upsert versi_app (fallback / force_update)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
APK_PATH="${APK_PATH:-build/optik-karyawan-${VERSION}.apk}"
OBJECT_NAME="optik-karyawan-${VERSION}.apk"
FORCE_UPDATE="${FORCE_UPDATE:-false}"
CATATAN="${CATATAN:-Update Optik Karyawan ${VERSION}}"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "ERROR: set SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY dulu."
  echo ""
  echo "Contoh:"
  echo "  export SUPABASE_URL='https://ualqiiprtjysdmtqkpzr.supabase.co'"
  echo "  export SUPABASE_SERVICE_ROLE_KEY='...service_role...'"
  echo "  bash scripts/publish_karyawan_apk.sh"
  exit 1
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "ERROR: APK tidak ada: $APK_PATH"
  echo "Build dulu: bash scripts/release_karyawan_apk.sh"
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
  echo "==> MANUAL_VERSI_APP=1 → upsert REST versi_app (flavor=karyawan, versi=${VERSION})"
  curl -sS -X DELETE \
    "${BASE}/rest/v1/versi_app?app_flavor=eq.karyawan&versi_terbaru=eq.${VERSION}" \
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
  "app_flavor": "karyawan",
}))
PY
)"
  echo ""
else
  echo "==> Skip REST versi_app (trigger Storage sync otomatis)."
  echo "    Set MANUAL_VERSI_APP=1 jika perlu force_update/catatan via script."
fi

echo ""
echo "OK. Upload selesai → app Karyawan membaca versi terbaru dari versi_app."
echo "URL: ${PUBLIC_URL}"
echo "Cek: select * from public.versi_app where app_flavor='karyawan' order by created_at desc limit 3;"
