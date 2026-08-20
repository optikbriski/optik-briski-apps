# shellcheck shell=bash
# Muat brands/<BRAND>.json → env. Default BRAND=optik-briski.
# Dipakai release_member_apk.sh / release_karyawan_apk.sh.

: "${ROOT:?ROOT harus di-set sebelum source brand_env.sh}"

BRAND="${BRAND:-optik-briski}"
BRAND_FILE="$ROOT/brands/${BRAND}.json"

if [[ ! -f "$BRAND_FILE" ]]; then
  echo "ERROR: $BRAND_FILE tidak ada."
  echo "Salin brands/_template.json → brands/${BRAND}.json, isi slug/nama/applicationId."
  echo "Tenant harus sudah dibuat di Admin Rekasa (UMKM / Tenant)."
  exit 1
fi

eval "$(python3 - "$BRAND_FILE" <<'PY'
import json, shlex, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    p = json.load(f)

def exp(name, key, default=""):
    v = str(p.get(key) or default).strip()
    print(f"export {name}={shlex.quote(v)}")

slug = str(p.get("slug") or "optik-briski").strip()
pin = p.get("pinTenant")
if pin is None:
    pin = slug != "rekasa"
print(f"export STORE_PIN_TENANT={shlex.quote('true' if pin else 'false')}")
exp("STORE_SLUG", "slug", "optik-briski")
exp("STORE_DISPLAY_NAME", "displayName", slug)
exp("STORE_MEMBER_APP_NAME", "memberAppName", p.get("displayName") or slug)
exp("STORE_KARYAWAN_APP_NAME", "karyawanAppName", p.get("displayName") or slug)
exp("STORE_MEMBER_APPLICATION_ID", "memberApplicationId")
exp("STORE_KARYAWAN_APPLICATION_ID", "karyawanApplicationId")
exp("STORE_ADMIN_APP_NAME", "adminAppName", (p.get("displayName") or slug) + " Admin")
exp("STORE_ADMIN_APPLICATION_ID", "adminApplicationId")
PY
)"

if [[ -z "${STORE_SLUG:-}" ]]; then
  echo "ERROR: brands/${BRAND}.json wajib punya slug."
  exit 1
fi
