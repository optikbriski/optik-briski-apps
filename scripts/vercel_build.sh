#!/usr/bin/env bash
set -euo pipefail

# Flutter Web (Admin) for Vercel Git / CLI builds.
# Set in Vercel → Project → Settings → Environment Variables (Production + Preview):
#   SUPABASE_URL
#   SUPABASE_ANON_KEY

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

flutter build web --release \
  -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=admin \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

test -f build/web/index.html
echo "OK: build/web ready"
