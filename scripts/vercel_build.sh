#!/usr/bin/env bash
set -euo pipefail

# Flutter Web (Admin) di / — tautan nota /i/… dan ?kontrak= tetap hidup.
# Situs perusahaan Rekasa (Midtrans) di /perusahaan/
# Set in Vercel → Project → Settings → Environment Variables (Production + Preview):
#   SUPABASE_URL
#   SUPABASE_ANON_KEY
#   GOOGLE_MAPS_API_KEY   (Maps JavaScript API — Admin geofence editor)

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter-sdk}"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set in Vercel Environment Variables."
  exit 1
fi

if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  echo "Cloning Flutter ($FLUTTER_CHANNEL) → $FLUTTER_DIR"
  rm -rf "$FLUTTER_DIR"
  git clone https://github.com/flutter/flutter.git \
    --depth 1 \
    --branch "$FLUTTER_CHANNEL" \
    "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"

flutter config --no-analytics --enable-web >/dev/null
flutter --version
flutter precache --web
flutter pub get

# Inject Google Maps key into web/index.html before build (optional but needed for geofence map).
if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  sed -i.bak "s/__GOOGLE_MAPS_API_KEY__/${GOOGLE_MAPS_API_KEY}/g" web/index.html
  rm -f web/index.html.bak
else
  echo "WARN: GOOGLE_MAPS_API_KEY not set — peta Google web memakai loader Dart bila dart-define terisi."
fi
bash "$(dirname "$0")/sync_google_maps_native_key.sh" || true

# Konsol Rekasa: jangan pin merek. Web per merek: scripts/release_brand_web.sh
flutter build web --release \
  -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=admin \
  --dart-define=ADMIN_PIN_TENANT=false \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_MAPS_API_KEY="${GOOGLE_MAPS_API_KEY:-}"

test -f build/web/index.html
mkdir -p build/web/perusahaan
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude '.vercel' --exclude '.gitignore' site/ build/web/perusahaan/
else
  cp -R site/. build/web/perusahaan/
  rm -rf build/web/perusahaan/.vercel
fi
python3 - <<'PY'
import json, os
from pathlib import Path
p = Path("build/web/perusahaan/config.js")
cfg = {
    "supabaseUrl": os.environ.get("SUPABASE_URL", ""),
    "supabaseAnon": os.environ.get("SUPABASE_ANON_KEY", ""),
    "midtransClientKey": os.environ.get("MIDTRANS_CLIENT_KEY", ""),
    "midtransProduction": os.environ.get("MIDTRANS_IS_PRODUCTION", "false").lower() == "true",
    "contactEmail": "rekasakaryaindonesia@gmail.com",
}
p.write_text(
    "window.REKASA_CHECKOUT = " + json.dumps(cfg, indent=2) + ";\n",
    encoding="utf-8",
)
PY
test -f build/web/perusahaan/index.html
test -f build/web/perusahaan/store.js
test -f build/web/perusahaan/sw-kill.js
echo "OK: konsol Admin di / ; situs Rekasa di /perusahaan/"
