#!/usr/bin/env bash
# Upload Admin APK Optik B. Riski → optik-admin-<versi>.apk + versi_app tenant_slug=optik-briski.
# Bukan rekasa-admin — tablet Optik Admin (ADMIN_PIN_TENANT) hanya baca saluran optik-briski.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export BRAND=optik-briski
exec bash "$ROOT/scripts/publish_admin_apk.sh"
