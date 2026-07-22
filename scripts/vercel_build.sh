#!/usr/bin/env bash
set -euo pipefail

# Flutter Web (Admin) for Vercel Git / CLI builds.
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
  echo "WARN: GOOGLE_MAPS_API_KEY not set — Geofence Google Map akan gagal load di web."
fi

flutter build web --release \
  -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=admin \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_MAPS_API_KEY="${GOOGLE_MAPS_API_KEY:-}"

test -f build/web/index.html
echo "OK: build/web ready"
