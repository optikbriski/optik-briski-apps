#!/usr/bin/env python3
"""Ekstrak rasio dari MediaPipe Face Landmarker (Tasks API) — sinkron Flutter."""

from __future__ import annotations

import csv
import json
import sys
import urllib.request
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from tqdm import tqdm

ROOT = Path(__file__).resolve().parent
MERGED = ROOT / "data" / "merged"
STORE = ROOT / "data" / "store" / "corrections.csv"
OUT = ROOT / "data" / "features.csv"
MODEL = ROOT / "models" / "face_landmarker.task"
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/"
    "face_landmarker/face_landmarker/float16/1/face_landmarker.task"
)

FEATURE_NAMES = [
    "length_width",
    "forehead_cheek",
    "jaw_cheek",
    "forehead_jaw",
    "cheek_face",
    "jaw_taper",
    "upper_mid",
    "mid_lower",
    "eye_face",
    "mouth_jaw",
]

# Indeks Face Mesh (sama seperti sebelumnya)
IDX = {
    "chin": 152,
    "forehead": 10,
    "left_cheek": 234,
    "right_cheek": 454,
    "left_temple": 54,
    "right_temple": 284,
    "left_jaw": 172,
    "right_jaw": 397,
    "left_eye": 33,
    "right_eye": 263,
    "mouth_l": 61,
    "mouth_r": 291,
}


def ensure_model() -> Path:
    MODEL.parent.mkdir(parents=True, exist_ok=True)
    if MODEL.exists() and MODEL.stat().st_size > 1_000_000:
        return MODEL
    print("Downloading Face Landmarker model…")
    urllib.request.urlretrieve(MODEL_URL, MODEL)
    print("Saved", MODEL)
    return MODEL


def dist(a, b) -> float:
    return float(np.linalg.norm(a - b))


def features_from_landmarks(landmarks, w: int, h: int) -> list[float] | None:
    def pt(i: int) -> np.ndarray:
        p = landmarks[i]
        return np.array([p.x * w, p.y * h], dtype=np.float64)

    try:
        chin = pt(IDX["chin"])
        forehead = pt(IDX["forehead"])
        l_cheek = pt(IDX["left_cheek"])
        r_cheek = pt(IDX["right_cheek"])
        l_temple = pt(IDX["left_temple"])
        r_temple = pt(IDX["right_temple"])
        l_jaw = pt(IDX["left_jaw"])
        r_jaw = pt(IDX["right_jaw"])
        l_eye = pt(IDX["left_eye"])
        r_eye = pt(IDX["right_eye"])
        m_l = pt(IDX["mouth_l"])
        m_r = pt(IDX["mouth_r"])
    except Exception:
        return None

    face_length = dist(forehead, chin)
    forehead_w = dist(l_temple, r_temple)
    cheek_w = dist(l_cheek, r_cheek)
    jaw_w = dist(l_jaw, r_jaw)
    face_width = max(cheek_w, forehead_w, jaw_w)
    if face_length < 1 or face_width < 1:
        return None

    eye_dist = dist(l_eye, r_eye)
    mouth_w = dist(m_l, m_r)

    def clamp(x, a, b):
        return float(min(max(x, a), b))

    return [
        clamp(face_length / face_width, 0.85, 1.85),
        clamp(forehead_w / cheek_w, 0.70, 1.25),
        clamp(jaw_w / cheek_w, 0.55, 1.20),
        clamp(forehead_w / jaw_w, 0.70, 1.55),
        clamp(cheek_w / face_width, 0.70, 1.15),
        clamp((cheek_w - jaw_w) / cheek_w, -0.15, 0.45),
        clamp(forehead_w / cheek_w, 0.70, 1.25),
        clamp(cheek_w / jaw_w, 0.80, 1.60),
        clamp(eye_dist / face_width, 0.18, 0.48),
        clamp(mouth_w / jaw_w, 0.35, 0.95),
    ]


def extract_image(path: Path, landmarker) -> list[float] | None:
    img = cv2.imread(str(path))
    if img is None:
        return None
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    h, w = rgb.shape[:2]
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = landmarker.detect(mp_image)
    if not result.face_landmarks:
        return None
    return features_from_landmarks(result.face_landmarks[0], w, h)


def main() -> int:
    rows: list[dict] = []
    model_path = ensure_model()
    options = vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.IMAGE,
        num_faces=1,
        min_face_detection_confidence=0.5,
        min_face_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    with vision.FaceLandmarker.create_from_options(options) as landmarker:
        if MERGED.exists():
            for cls_dir in sorted(MERGED.iterdir()):
                if not cls_dir.is_dir():
                    continue
                label = cls_dir.name
                imgs = [
                    p
                    for p in cls_dir.iterdir()
                    if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
                ]
                for img in tqdm(imgs, desc=label):
                    feats = extract_image(img, landmarker)
                    if feats is None:
                        continue
                    row = {"label": label, "source": "merged", "path": str(img)}
                    for n, v in zip(FEATURE_NAMES, feats):
                        row[n] = v
                    rows.append(row)

        if STORE.exists():
            import pandas as pd

            df = pd.read_csv(STORE)
            for _, r in df.iterrows():
                label = str(r.get("corrected_shape") or r.get("primary_shape") or "")
                if not label:
                    continue
                feats_raw = r.get("features")
                try:
                    obj = (
                        json.loads(feats_raw)
                        if isinstance(feats_raw, str)
                        else feats_raw
                    )
                    values = obj.get("values") if isinstance(obj, dict) else None
                    if not values or len(values) != len(FEATURE_NAMES):
                        continue
                except Exception:
                    continue
                row = {"label": label, "source": "store", "path": ""}
                for n, v in zip(FEATURE_NAMES, values):
                    row[n] = float(v)
                rows.append(row)

    if not rows:
        print("Tidak ada fitur. Pastikan data/merged terisi.")
        OUT.parent.mkdir(parents=True, exist_ok=True)
        with OUT.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(
                f, fieldnames=["label", "source", "path", *FEATURE_NAMES]
            )
            w.writeheader()
        return 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["label", "source", "path", *FEATURE_NAMES])
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {len(rows)} rows → {OUT}")
    print("Lanjut: python 03_train_export.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
