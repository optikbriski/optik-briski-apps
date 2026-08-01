#!/usr/bin/env python3
"""Merge Pasupa + Kaggle + Roboflow ke data/merged/ dengan dedup perceptual hash.

Mendukung:
- folder-per-kelas (Kaggle / Pasupa)
- YOLOv8 Roboflow (train|valid|test)/images + data.yaml
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

from PIL import Image
import imagehash
from tqdm import tqdm

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "data" / "raw"
MERGED = ROOT / "data" / "merged"

LABEL_MAP = {
    "heart": "heart",
    "oblong": "oblong",
    "oval": "oval",
    "round": "round",
    "square": "square",
    "rectangle": "oblong",
    "rectangular": "oblong",
    "diamond": "diamond",
}

IMG_EXT = {".jpg", ".jpeg", ".png", ".webp"}


def normalize_label(name: str) -> str | None:
    key = name.strip().lower().replace(" ", "_")
    return LABEL_MAP.get(key)


def parse_yolo_names(yaml_path: Path) -> list[str]:
    """Parse names list dari data.yaml sederhana (tanpa PyYAML)."""
    text = yaml_path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"names:\s*\[([^\]]+)\]", text)
    if not m:
        return []
    parts = [p.strip().strip("'\"") for p in m.group(1).split(",")]
    return parts


def label_from_yolo_image(img: Path, class_names: list[str]) -> str | None:
    # 1) dari nama file: heart-1-_jpg.rf....jpg
    stem = img.stem.lower()
    for key in LABEL_MAP:
        if stem.startswith(key + "-") or stem.startswith(key + "_"):
            return LABEL_MAP[key]

    # 2) dari file label YOLO (class id di kolom pertama)
    # images/...jpg → labels/...txt
    if img.parent.name == "images":
        label_file = img.parent.parent / "labels" / (img.stem + ".txt")
    else:
        label_file = img.with_suffix(".txt")
    if label_file.exists() and class_names:
        try:
            first = label_file.read_text(encoding="utf-8").strip().split()
            if first:
                idx = int(float(first[0]))
                if 0 <= idx < len(class_names):
                    return normalize_label(class_names[idx])
        except Exception:
            pass
    return None


def iter_labeled_images(root: Path):
    if not root.exists():
        return

    yaml_path = root / "data.yaml"
    class_names = parse_yolo_names(yaml_path) if yaml_path.exists() else []

    # YOLO layout
    yolo_splits = [root / s / "images" for s in ("train", "valid", "val", "test")]
    yolo_dirs = [p for p in yolo_splits if p.is_dir()]
    if yolo_dirs:
        for img_dir in yolo_dirs:
            for img in img_dir.iterdir():
                if img.suffix.lower() not in IMG_EXT:
                    continue
                label = label_from_yolo_image(img, class_names)
                if label:
                    yield label, img
        return

    # Folder-per-kelas
    for cls_dir in root.rglob("*"):
        if not cls_dir.is_dir():
            continue
        label = normalize_label(cls_dir.name)
        if label is None:
            continue
        for img in cls_dir.iterdir():
            if img.suffix.lower() in IMG_EXT:
                yield label, img


def main() -> int:
    if MERGED.exists():
        shutil.rmtree(MERGED)
    for lab in sorted(set(LABEL_MAP.values())):
        (MERGED / lab).mkdir(parents=True, exist_ok=True)

    seen: set[str] = set()
    kept = 0
    skipped = 0

    sources = [
        RAW / "pasupa_faceshape",
        RAW / "kaggle_niten19",
        RAW / "roboflow_face_shape",
    ]

    for src in sources:
        print("Scanning", src)
        items = list(iter_labeled_images(src))
        print(f"  found {len(items)} labeled images")
        for label, path in tqdm(items, desc=src.name):
            try:
                with Image.open(path) as im:
                    im = im.convert("RGB")
                    h = str(imagehash.phash(im))
            except Exception:
                skipped += 1
                continue
            if h in seen:
                skipped += 1
                continue
            seen.add(h)
            dest = MERGED / label / f"{src.name}_{kept:05d}{path.suffix.lower()}"
            shutil.copy2(path, dest)
            kept += 1

    print(f"Merged kept={kept} skipped_dup_or_bad={skipped} → {MERGED}")
    print("Lanjut: python 02_extract_features.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
