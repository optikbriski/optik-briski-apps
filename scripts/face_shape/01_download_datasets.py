#!/usr/bin/env python3
"""Download / clone ketiga dataset publik ke data/raw/."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "data" / "raw"
RAW.mkdir(parents=True, exist_ok=True)


def run(cmd: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(cmd))
    subprocess.check_call(cmd, cwd=str(cwd) if cwd else None)


def clone_pasupa() -> None:
    dest = RAW / "pasupa_faceshape"
    if dest.exists():
        print("Pasupa already present:", dest)
        return
    run(
        [
            "git",
            "clone",
            "--depth",
            "1",
            "https://github.com/dsmlr/faceshape.git",
            str(dest),
        ]
    )


def download_kaggle() -> None:
    dest = RAW / "kaggle_niten19"
    if dest.exists() and any(dest.rglob("*.jpg")):
        print("Kaggle already present:", dest)
        return
    dest.mkdir(parents=True, exist_ok=True)
    try:
        run(
            [
                "kaggle",
                "datasets",
                "download",
                "-d",
                "niten19/face-shape-dataset",
                "-p",
                str(dest),
                "--unzip",
            ]
        )
    except Exception as e:
        print(
            "\n[!] Kaggle download gagal / CLI belum siap.\n"
            "    Download manual: https://www.kaggle.com/datasets/niten19/face-shape-dataset\n"
            f"    Extract ke: {dest}\n"
            f"    Detail: {e}\n"
        )


def download_roboflow() -> None:
    """Roboflow sering butuh API key — sediakan folder manual jika gagal."""
    dest = RAW / "roboflow_face_shape"
    dest.mkdir(parents=True, exist_ok=True)
    marker = dest / "README_MANUAL.txt"
    if not marker.exists():
        marker.write_text(
            "Export dataset dari:\n"
            "https://universe.roboflow.com/yes-ripdh/face-shape-detection\n"
            "Format: folder-per-kelas atau YOLO/COCO — letakkan di folder ini.\n"
            "Cek lisensi export sebelum produksi.\n",
            encoding="utf-8",
        )
    print("Roboflow: letakkan export di", dest)


def main() -> int:
    print("== Face shape dataset download ==")
    clone_pasupa()
    download_kaggle()
    download_roboflow()
    print("Done. Lanjut: python 04_merge_dedup.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
