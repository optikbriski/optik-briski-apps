#!/usr/bin/env bash
# Buang aset yang tidak dipakai di Android (bukan fitur/UI), lalu zipalign + resign.
# Target: lolos batas Supabase Free 50 MB tanpa mengurangi kualitas OCR/kamera.
set -euo pipefail

APK="${1:?Usage: shrink_apk_for_supabase.sh path/to.apk}"
JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

BUILD_TOOLS="$(ls -d "$HOME"/Library/Android/sdk/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
ZIPALIGN="${BUILD_TOOLS}zipalign"
APKSIGNER="${BUILD_TOOLS}apksigner"
KS="${DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"

if [[ ! -x "$ZIPALIGN" || ! -x "$APKSIGNER" ]]; then
  echo "ERROR: Android build-tools (zipalign/apksigner) tidak ditemukan."
  exit 1
fi
if [[ ! -f "$KS" ]]; then
  echo "ERROR: debug keystore tidak ada: $KS"
  exit 1
fi

BEFORE=$(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK")
echo "==> Shrink (non-quality) $APK ($(python3 -c "print(f'{$BEFORE/1024/1024:.2f} MB')"))"

# Windows BLE helper + Cupertino font (tidak dipakai di kode) + Flutter license blob
zip -d "$APK" \
  "assets/flutter_assets/packages/win_ble/assets/BLEServer.exe" \
  "assets/flutter_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf" \
  "assets/flutter_assets/NOTICES.Z" \
  2>/dev/null || true

# Kotlin coroutines debug probes (release junk) + license / VCS / OSGI / library version markers
# + kotlin reflection builtins (tidak dipakai Flutter app; metadata saja)
python3 - <<'PY' "$APK"
import sys, zipfile, subprocess
apk = sys.argv[1]
with zipfile.ZipFile(apk) as z:
    names = z.namelist()
kill = []
for n in names:
    if n in (
        "DebugProbesKt.bin",
        "META-INF/androidx/annotation/annotation/LICENSE.txt",
        "META-INF/version-control-info.textproto",
        "META-INF/com/android/build/gradle/app-metadata.properties",
        "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
    ):
        kill.append(n)
    elif n.endswith(".kotlin_builtins"):
        kill.append(n)
    elif n.startswith("META-INF/") and n.endswith(".version"):
        kill.append(n)
if kill:
    # zip -d in batches to avoid arg limits
    for i in range(0, len(kill), 40):
        batch = kill[i:i+40]
        subprocess.run(["zip", "-d", apk, *batch], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"==> Removed {len(kill)} junk entries (licenses/debug/META versions/kotlin_builtins)")
else:
    print("==> No extra junk entries found")
PY

# Lossless PNG recompress for bundled logo (strip ancillary chunks + zlib level 9)
python3 - <<'PY' "$APK"
import sys, zipfile, struct, zlib, tempfile, os, subprocess
from pathlib import Path
apk = Path(sys.argv[1])
logo_path = "assets/flutter_assets/assets/images/logo_briski.png"

def png_strip_and_recompress(data: bytes, level: int = 9) -> bytes:
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    i = 8
    idat = b""
    others = []  # IHDR/PLTE/tRNS only
    while i < len(data):
        ln = struct.unpack(">I", data[i : i + 4])[0]
        typ = data[i + 4 : i + 8]
        payload = data[i + 8 : i + 8 + ln]
        if typ == b"IDAT":
            idat += payload
        elif typ in (b"IHDR", b"PLTE", b"tRNS"):
            others.append((typ, payload))
        i += 12 + ln
    raw = zlib.decompress(idat)
    new_idat = zlib.compress(raw, level)

    def chunk(t: bytes, p: bytes) -> bytes:
        return struct.pack(">I", len(p)) + t + p + struct.pack(">I", zlib.crc32(t + p) & 0xFFFFFFFF)

    out = bytearray(data[:8])
    ihdr = next(p for t, p in others if t == b"IHDR")
    out += chunk(b"IHDR", ihdr)
    for t, p in others:
        if t != b"IHDR":
            out += chunk(t, p)
    out += chunk(b"IDAT", new_idat)
    out += chunk(b"IEND", b"")
    return bytes(out)

with zipfile.ZipFile(apk) as z:
    if logo_path not in z.namelist():
        print("==> Logo not found; skip PNG optimize")
        raise SystemExit(0)
    original = z.read(logo_path)
optimized = png_strip_and_recompress(original)
if len(optimized) >= len(original):
    print(f"==> PNG optimize skipped (no gain: {len(original)} -> {len(optimized)})")
    raise SystemExit(0)

# Replace entry: delete then add via zip
subprocess.run(["zip", "-d", str(apk), logo_path], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
tmpdir = tempfile.mkdtemp(prefix="optik-png-")
# recreate nested path for zip
dest = Path(tmpdir) / logo_path
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_bytes(optimized)
# zip from tmpdir so archive path matches
subprocess.run(["zip", "-9", "-X", str(apk), logo_path], cwd=tmpdir, check=True, stdout=subprocess.DEVNULL)
# cleanup
import shutil
shutil.rmtree(tmpdir)
print(f"==> Lossless PNG: {len(original)} -> {len(optimized)} bytes (-{len(original)-len(optimized)})")
PY

ALIGNED="$(mktemp -t optik-apk).apk"
"$ZIPALIGN" -f 4 "$APK" "$ALIGNED"
"$APKSIGNER" sign \
  --ks "$KS" \
  --ks-pass pass:android \
  --key-pass pass:android \
  --ks-key-alias androiddebugkey \
  --out "$APK" \
  "$ALIGNED"
rm -f "$ALIGNED"
"$APKSIGNER" verify "$APK" >/dev/null

AFTER=$(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK")
LIMIT=$((50 * 1024 * 1024))
python3 - <<PY
before=$BEFORE
after=$AFTER
limit=$LIMIT
print(f"==> Hasil: {after/1024/1024:.3f} MB (was {before/1024/1024:.3f} MB)")
print(f"==> Bytes: {after} (limit {limit})")
print(f"==> Supabase Free 50 MB: {'OK' if after < limit else 'MASIH KELEBIHAN'} (margin {(limit-after)/1024:.1f} KB)")
PY
if [[ "$AFTER" -ge "$LIMIT" ]]; then
  exit 2
fi
