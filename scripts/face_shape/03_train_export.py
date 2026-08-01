#!/usr/bin/env python3
"""Train logistic regression + centroids → assets/models/face_shape_weights.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report
from sklearn.model_selection import train_test_split
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import LabelEncoder, StandardScaler

ROOT = Path(__file__).resolve().parent
FEATURES = ROOT / "data" / "features.csv"
OUT = ROOT.parents[1] / "assets" / "models" / "face_shape_weights.json"

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

CLASS_ORDER = ["oval", "round", "square", "heart", "diamond", "oblong"]

BOOT_CENTROIDS = {
    "oval": [1.28, 0.96, 0.92, 1.05, 0.96, 0.08, 0.96, 1.08, 0.33, 0.62],
    "round": [1.05, 0.97, 0.96, 1.01, 0.98, 0.04, 0.97, 1.04, 0.34, 0.64],
    "square": [1.18, 0.98, 0.97, 1.02, 0.97, 0.03, 0.98, 1.03, 0.32, 0.60],
    "heart": [1.30, 1.08, 0.82, 1.28, 0.94, 0.18, 1.08, 1.22, 0.33, 0.58],
    "diamond": [1.32, 0.88, 0.80, 1.10, 1.02, 0.20, 0.88, 1.25, 0.34, 0.56],
    "oblong": [1.52, 0.97, 0.93, 1.04, 0.95, 0.07, 0.97, 1.07, 0.31, 0.60],
}


def main() -> int:
    if not FEATURES.exists():
        print("Missing", FEATURES)
        return 1

    df = pd.read_csv(FEATURES)
    if df.empty:
        print("features.csv kosong — export bootstrap centroids saja.")
        _write(BOOT_CENTROIDS, None, None, {
            "pasupa": False, "kaggle": False, "roboflow": False, "store": False,
        })
        return 0

    df = df[df["label"].isin(CLASS_ORDER)].dropna(subset=FEATURE_NAMES).copy()
    present = sorted(df["label"].unique().tolist())
    print("Kelas di data:", present)
    print("Jumlah baris:", len(df))

    if len(df) < 30 or len(present) < 2:
        print("Sample terlalu sedikit; export centroid saja.")
        centroids = _centroids_with_bootstrap(df)
        _write(centroids, None, None, trained_flags(df))
        return 0

    X = df[FEATURE_NAMES].to_numpy(dtype=np.float64)
    y_raw = df["label"].to_numpy()

    # Encode HANYA kelas yang ada di data (publik biasanya 5, tanpa diamond)
    le = LabelEncoder()
    le.fit(present)
    y = le.transform(y_raw)

    Xtr, Xte, ytr, yte = train_test_split(
        X,
        y,
        test_size=0.2,
        random_state=42,
        stratify=y if len(set(y)) > 1 else None,
    )

    pipe = make_pipeline(
        StandardScaler(),
        LogisticRegression(
            max_iter=3000,
            multi_class="multinomial",
            class_weight="balanced",
            solver="lbfgs",
        ),
    )
    pipe.fit(Xtr, ytr)
    pred = pipe.predict(Xte)

    labels = list(range(len(le.classes_)))
    print(
        classification_report(
            yte,
            pred,
            labels=labels,
            target_names=list(le.classes_),
            zero_division=0,
        )
    )

    clf = pipe.named_steps["logisticregression"]
    scaler = pipe.named_steps["standardscaler"]

    # Ekspor bobot di ruang fitur ASLI (setelah “membuka” StandardScaler):
    # z = W_scaled @ ((x - mean) / scale) + b
    #   = (W_scaled / scale) @ x + (b - (W_scaled/scale) @ mean)
    coef_by_label = {}
    intercept_by_label = {}
    for i, coef_scaled in enumerate(clf.coef_):
        label = le.inverse_transform([clf.classes_[i]])[0]
        w = coef_scaled / scaler.scale_
        b = float(clf.intercept_[i] - np.dot(w, scaler.mean_))
        coef_by_label[label] = w.tolist()
        intercept_by_label[label] = b

    weights = []
    bias = []
    for lab in CLASS_ORDER:
        if lab in coef_by_label:
            weights.append(coef_by_label[lab])
            bias.append(intercept_by_label[lab])
        else:
            # Kelas tanpa data (diamond) — zero linear; andalkan rules+centroid
            weights.append([0.0] * len(FEATURE_NAMES))
            bias.append(0.0)

    centroids = _centroids_with_bootstrap(df)
    _write(centroids, weights, bias, trained_flags(df))
    print("Exported →", OUT)
    return 0


def _centroids_with_bootstrap(df: pd.DataFrame) -> dict:
    out = dict(BOOT_CENTROIDS)
    for lab in CLASS_ORDER:
        sub = df[df["label"] == lab]
        if sub.empty:
            continue
        out[lab] = [float(sub[c].mean()) for c in FEATURE_NAMES]
    return out


def trained_flags(df: pd.DataFrame) -> dict:
    src = set(df.get("source", pd.Series(dtype=str)).astype(str))
    # merged = hasil 3 dataset publik
    merged = "merged" in src
    return {
        "pasupa": merged or any("pasupa" in s for s in src),
        "kaggle": merged or any("kaggle" in s for s in src),
        "roboflow": merged or any("roboflow" in s for s in src),
        "store": "store" in src,
    }


def _write(centroids, weights, bias, trained_on) -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "feature_names": FEATURE_NAMES,
        "class_order": CLASS_ORDER,
        "datasets_planned": [
            "pasupa_dsmlr",
            "kaggle_niten19",
            "roboflow_face_shape",
            "optik_store",
        ],
        "note": "Diamond biasanya absen di dataset publik — diisi centroid bootstrap + rules on-device.",
        "centroids": centroids,
        "linear_weights": weights,
        "linear_bias": bias,
        "trained_on": trained_on,
    }
    OUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print("Wrote", OUT)


if __name__ == "__main__":
    sys.exit(main())
