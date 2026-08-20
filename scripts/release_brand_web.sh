#!/usr/bin/env bash
# Web Admin merek toko (terkunci tenant). Bukan konsol Rekasa.
# Rekasa tetap di Vercel Git (scripts/vercel_build.sh, ADMIN_PIN_TENANT=false).
#
#   BRAND=optik-maju bash scripts/release_brand_web.sh
# Deploy folder build/web ke domain merek (contoh admin.optikmaju.com).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/brand_env.sh
source "$ROOT/scripts/brand_env.sh"

if [[ "${STORE_PIN_TENANT:-true}" != "true" ]]; then
  echo "ERROR: Web merek sendiri hanya untuk paket white-label (pinTenant=true)."
  echo "Paket bawah memakai web Rekasa + kode usaha. Konsol Rekasa: Vercel Git."
  exit 1
fi

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  if [[ -f .dart_define.admin.json ]]; then
    echo "Pakai .dart_define.admin.json untuk URL/key."
  elif [[ -f .dart_define.karyawan.json ]]; then
    echo "Pakai .dart_define.karyawan.json untuk URL/key."
  else
    echo "ERROR: set SUPABASE_URL dan SUPABASE_ANON_KEY, atau file .dart_define.*.json"
    exit 1
  fi
fi

DEFINE_ARGS=(
  --dart-define=APP_FLAVOR=admin
  --dart-define=ADMIN_PIN_TENANT=true
  --dart-define=ADMIN_TENANT_SLUG="$STORE_SLUG"
)
if [[ -f .dart_define.admin.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.admin.json)
  DEFINE_ARGS+=(--dart-define=APP_FLAVOR=admin)
  DEFINE_ARGS+=(--dart-define=ADMIN_PIN_TENANT=true)
  DEFINE_ARGS+=(--dart-define=ADMIN_TENANT_SLUG="$STORE_SLUG")
elif [[ -f .dart_define.karyawan.json ]]; then
  DEFINE_ARGS+=(--dart-define-from-file=.dart_define.karyawan.json)
  DEFINE_ARGS+=(--dart-define=APP_FLAVOR=admin)
  DEFINE_ARGS+=(--dart-define=ADMIN_PIN_TENANT=true)
  DEFINE_ARGS+=(--dart-define=ADMIN_TENANT_SLUG="$STORE_SLUG")
else
  DEFINE_ARGS+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  DEFINE_ARGS+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi

if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  sed -i.bak "s/__GOOGLE_MAPS_API_KEY__/${GOOGLE_MAPS_API_KEY}/g" web/index.html
  rm -f web/index.html.bak
fi

# Judul splash = merek, lalu Flutter ganti lagi dari app_brand.
TITLE="${STORE_ADMIN_APP_NAME:-$STORE_DISPLAY_NAME}"
python3 - "$TITLE" <<'PY'
import pathlib, sys
title = sys.argv[1]
html = pathlib.Path("web/index.html").read_text(encoding="utf-8")
for old in (
    "<title>Rekasa POS</title>",
    "<title>Optik B. Riski</title>",
):
    html = html.replace(old, f"<title>{title}</title>")
html = html.replace(
    'content="Rekasa POS"',
    f'content="{title}"',
)
pathlib.Path("web/index.html").write_text(html, encoding="utf-8")
PY

echo "==> Build web Admin merek ${STORE_DISPLAY_NAME} (${STORE_SLUG})"
flutter build web --release \
  -t lib/main_admin.dart \
  "${DEFINE_ARGS[@]}"

# Jangan commit index.html yang sudah di-sed.
git checkout -- web/index.html 2>/dev/null || true

test -f build/web/index.html
echo "OK: build/web siap diunggah ke domain merek ini."
echo "Konsol Rekasa tetap Vercel utama (tidak di-pin)."
