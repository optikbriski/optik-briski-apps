# Face Shape Training Pipeline

Pipeline lengkap: **3 dataset publik** + data toko Optik → ekstrak fitur landmark → train → export JSON ke Flutter.

## Senjata yang dipakai

| Sumber | Path / cara dapat | Kelas |
|--------|-------------------|--------|
| Pasupa (paper ESWA) | https://github.com/dsmlr/faceshape | 5 |
| Kaggle Niten Lama | https://www.kaggle.com/datasets/niten19/face-shape-dataset | 5 |
| Roboflow face-shape | https://universe.roboflow.com/yes-ripdh/face-shape-detection | 5 |
| Data toko | export `member_face_shape_scans` (koreksi staff/user) | 6 (+ diamond) |

Diamond hampir tidak ada di dataset publik → diisi dari **aturan rasio** + koreksi toko.

## Setup

```bash
cd scripts/face_shape
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Kaggle CLI (opsional, untuk download otomatis):

```bash
pip install kaggle
# taruh credentials di ~/.kaggle/kaggle.json
```

## Urutan jalan

```bash
# 1) Download / clone semua sumber ke data/raw/
python 01_download_datasets.py

# 2) Merge + dedup (penting: Roboflow sering overlap Kaggle)
python 04_merge_dedup.py

# 3) Ekstrak fitur MediaPipe Face Landmarker (Tasks API) → CSV rasio
#    Model .task diunduh otomatis ke scripts/face_shape/models/
python 02_extract_features.py

# 4) Train logistic + centroids → assets/models/face_shape_weights.json
python 03_train_export.py
```

Output Flutter:

`../../assets/models/face_shape_weights.json`

App Member memuat file itu lewat `FaceShapeModelStore` dan mem-fuse dengan aturan geometri on-device (ML Kit contours).

## Export koreksi toko (Supabase)

```sql
copy (
  select primary_shape, corrected_shape, features, engine, created_at
  from member_face_shape_scans
  where corrected_shape is not null
) to stdout with csv header;
```

Simpan sebagai `data/store/corrections.csv` lalu jalankan ulang `02` + `03`.
