#!/usr/bin/env bash
# Tulis kunci native iOS dari env / .dart_define*.json (sama sumber Flutter).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/ios/Flutter/GoogleMaps.xcconfig"

key="${GOOGLE_MAPS_API_KEY:-}"
if [[ -z "$key" ]]; then
  for f in \
    "$ROOT/.dart_define.admin.json" \
    "$ROOT/.dart_define.karyawan.json" \
    "$ROOT/.dart_define.member.json"
  do
    if [[ -f "$f" ]]; then
      key="$(python3 - "$f" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
print(str(p.get("GOOGLE_MAPS_API_KEY") or "").strip())
PY
)"
      if [[ -n "$key" ]]; then
        break
      fi
    fi
  done
fi

# Jangan tulis kunci ke stdout. File ini di-gitignore.
printf 'GOOGLE_MAPS_API_KEY=%s\n' "$key" > "$OUT"
