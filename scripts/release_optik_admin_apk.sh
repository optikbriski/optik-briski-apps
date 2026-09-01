#!/usr/bin/env bash
# Build Admin APK Optik B. Riski (com.optikbriski.admin, saluran versi_app optik-briski).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export BRAND=optik-briski
bash "$ROOT/scripts/release_admin_apk.sh"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
echo ""
echo "==> Upload Optik (bukan rekasa-admin):"
echo "  bash scripts/publish_optik_admin_apk.sh"
echo "  → build/optik-admin-${VERSION}.apk"
echo "  → versi_app: app_flavor=admin, tenant_slug=optik-briski"
