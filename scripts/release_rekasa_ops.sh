#!/usr/bin/env bash
# APK operasional Rekasa (kulit bersama paket B/C + staf multi-merek).
# Karyawan + Admin, pinTenant=false. Member toko paket A tetap BRAND=<slug>.
#
#   bash scripts/release_rekasa_ops.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export BRAND=rekasa

echo "==> Rekasa Karyawan (operasional toko)"
bash "$ROOT/scripts/release_karyawan_apk.sh"

echo "==> Rekasa Admin (tablet/HP toko + konsol jika is_platform)"
bash "$ROOT/scripts/release_admin_apk.sh"

echo ""
echo "APK operasional:"
ls -lh build/rekasa-karyawan-*.apk build/rekasa-admin-*.apk 2>/dev/null || true
echo "Pasang, lalu isi kode usaha di login. Data sekat tenant_id."
echo "Etalase/kontrak: bash scripts/release_rekasa_store.sh (com.rekasa.store) — bukan APK ini."
