#!/usr/bin/env python3
"""Import Frame products from a priced photo folder into Supabase (PUSAT).

Folder layout:
  <ROOT>/Frame/<price>k/<Kategori> - <Nama>.jpg

Example:
  Frame/100k/Cat Eye - Chilli.jpg
    → kategori=Frame, sub_kategori=Cat Eye, nama=Cat Eye - Chilli, harga=100000

Env:
  SUPABASE_URL                 (default: project URL from launch.json)
  SUPABASE_SERVICE_ROLE_KEY    (required for storage + products insert)

Flags:
  --dry-run   parse + print only
  --root PATH override product root (default: /Volumes/WD_BLACK SSD/Products Optik B. Riski)
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_ROOT = Path("/Volumes/WD_BLACK SSD/Products Optik B. Riski")
DEFAULT_URL = "https://ualqiiprtjysdmtqkpzr.supabase.co"
BUCKET = "Foto Frame"
TOKO_ID = "PUSAT"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def parse_price_folder(name: str) -> int | None:
    m = re.fullmatch(r"(\d+)\s*k", name.strip(), re.I)
    if not m:
        return None
    return int(m.group(1)) * 1000


def title_keep(s: str) -> str:
    # Keep user's casing mostly; just trim + collapse spaces.
    return re.sub(r"\s+", " ", s.strip())


def scan(root: Path) -> list[dict]:
    frame = root / "Frame"
    if not frame.is_dir():
        raise SystemExit(f"Frame folder not found: {frame}")

    rows: list[dict] = []
    for price_dir in sorted(p for p in frame.iterdir() if p.is_dir()):
        harga = parse_price_folder(price_dir.name)
        if harga is None:
            print(f"! skip unknown price folder: {price_dir.name}", file=sys.stderr)
            continue
        for f in sorted(price_dir.iterdir()):
            if f.name.startswith(".") or not f.is_file():
                continue
            if f.suffix.lower() not in IMAGE_EXTS:
                continue
            stem = title_keep(f.stem)
            parts = re.split(r"\s*-\s*", stem, maxsplit=1)
            sub = title_keep(parts[0]) if parts else stem
            rows.append(
                {
                    "path": f,
                    "harga": harga,
                    "sub_kategori": sub,
                    "nama": stem,
                }
            )
    return rows


def api(
    method: str,
    url: str,
    key: str,
    *,
    data: bytes | None = None,
    content_type: str | None = None,
    prefer: str | None = None,
) -> tuple[int, bytes]:
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }
    if content_type:
        headers["Content-Type"] = content_type
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        body = e.read()
        raise RuntimeError(f"{method} {url} → {e.code}: {body.decode('utf-8', 'replace')}") from e


def upload_image(base: str, key: str, local: Path, object_path: str) -> str:
    mime = mimetypes.guess_type(local.name)[0] or "image/jpeg"
    if mime == "image/jpg":
        mime = "image/jpeg"
    # webp may be rejected by bucket allow-list; convert hint only
    encoded = "/".join(urllib.parse.quote(p, safe="") for p in object_path.split("/"))
    url = f"{base}/storage/v1/object/{urllib.parse.quote(BUCKET, safe='')}/{encoded}"
    status, _ = api("POST", url, key, data=local.read_bytes(), content_type=mime)
    if status not in (200, 201):
        raise RuntimeError(f"upload failed {status} for {local}")
    public = (
        f"{base}/storage/v1/object/public/"
        f"{urllib.parse.quote(BUCKET, safe='')}/"
        f"{encoded}"
    )
    return public


def insert_product(base: str, key: str, payload: dict) -> dict:
    url = f"{base}/rest/v1/products"
    body = json.dumps(payload).encode("utf-8")
    _, raw = api(
        "POST",
        url,
        key,
        data=body,
        content_type="application/json",
        prefer="return=representation",
    )
    rows = json.loads(raw.decode("utf-8"))
    if not rows:
        raise RuntimeError(f"empty insert response for {payload.get('nama')}")
    return rows[0]


def upsert_inventory(base: str, key: str, sku: str, stok: int = 0) -> None:
    url = f"{base}/rest/v1/inventory_stocks"
    body = json.dumps({"toko_id": TOKO_ID, "sku": sku, "stok": stok}).encode("utf-8")
    api(
        "POST",
        url,
        key,
        data=body,
        content_type="application/json",
        prefer="resolution=merge-duplicates,return=minimal",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()

    rows = scan(args.root)
    print(f"Found {len(rows)} Frame photos under {args.root / 'Frame'}")
    by_price: dict[int, int] = {}
    for r in rows:
        by_price[r["harga"]] = by_price.get(r["harga"], 0) + 1
    for h in sorted(by_price):
        print(f"  Rp{h:,}: {by_price[h]}")

    if args.dry_run:
        for i, r in enumerate(rows, 1):
            print(
                f"{i:02d}. Rp{r['harga']:,} | {r['sub_kategori']} | {r['nama']} | {r['path'].name}"
            )
        return 0

    base = os.environ.get("SUPABASE_URL", DEFAULT_URL).rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not key:
        print(
            "ERROR: set SUPABASE_SERVICE_ROLE_KEY "
            "(Dashboard → Settings → API → service_role).",
            file=sys.stderr,
        )
        return 1

    ok = 0
    failed: list[str] = []
    t0 = int(time.time() * 1000)

    for i, r in enumerate(rows):
        barcode = f"BC-{t0 + i}"
        object_path = f"frames/{barcode}_{r['path'].name}"
        try:
            print(f"[{i+1}/{len(rows)}] {r['nama']} @ Rp{r['harga']:,} …", flush=True)
            image_url = upload_image(base, key, r["path"], object_path)
            payload = {
                "nama": r["nama"],
                "harga": r["harga"],
                "harga_jual": r["harga"],
                "harga_modal": 0,
                "kategori": "Frame",
                "sub_kategori": r["sub_kategori"],
                "barcode": barcode,
                "sku": barcode,
                "image_url": image_url,
                "toko_id": TOKO_ID,
                "stock": 0,
            }
            insert_product(base, key, payload)
            try:
                upsert_inventory(base, key, barcode, 0)
            except Exception as inv_err:
                # Product already created; inventory is best-effort.
                print(f"  ! inventory_stocks: {inv_err}", file=sys.stderr)
            ok += 1
            print(f"  OK {barcode}")
        except Exception as e:
            msg = f"{r['path']}: {e}"
            failed.append(msg)
            print(f"  FAIL {e}", file=sys.stderr)

    print(f"\nDone: {ok}/{len(rows)} imported to {TOKO_ID}")
    if failed:
        print(f"Failed ({len(failed)}):")
        for m in failed:
            print(f"  - {m}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
