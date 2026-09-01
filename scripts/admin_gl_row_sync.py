#!/usr/bin/env python3
"""Ensure every admin_gl_row_* key used in admin dart exists in id.json / en.json."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADMIN = ROOT / "lib/apps/admin"
ID_PATH = ROOT / "assets/translations/id.json"
EN_PATH = ROOT / "assets/translations/en.json"

KEY_RE = re.compile(r"""['"](admin_gl_row_[a-z0-9_]+)['"]\.tr\(""")

# Recovered from git diff + hash brute-force + code context.
KNOWN: dict[str, tuple[str, str]] = {
    "admin_gl_row_0381714cf4": ("Masukkan kode voucher", "Enter voucher code"),
    "admin_gl_row_09486a6a82": ("Nilai diskon voucher 0", "Voucher discount is 0"),
    "admin_gl_row_1000bc2813": ("EEEE, d MMMM yyyy", "EEEE, MMMM d, yyyy"),
    "admin_gl_row_12da0e0ebd": (
        "Payroll dikunci — slip tersedia di APK Karyawan.",
        "Payroll locked — payslips available in Employee app.",
    ),
    "admin_gl_row_2bb698a77d": (
        "Ketuk peta untuk menaruh titik pusat.",
        "Tap the map to place the center point.",
    ),
    "admin_gl_row_2fd6a5b78c": ("Periode sudah dibayar.", "Period already paid."),
    "admin_gl_row_37ea28bca7": (
        "Masuk antrean tinjauan mencurigakan.",
        "Added to suspicious-attendance review queue.",
    ),
    "admin_gl_row_3d19aa47e8": (
        "Periode ditandai sudah dibayar.",
        "Period marked as paid.",
    ),
    "admin_gl_row_47e683f46f": (
        "Tidak ada baris payroll untuk diekspor.",
        "No payroll rows to export.",
    ),
    "admin_gl_row_4f4418f374": (
        "Owner Toko wajib pilih minimal 1 cabang.",
        "Store Owner must select at least 1 branch.",
    ),
    "admin_gl_row_5231b2d347": (
        "Hanya boleh atur geofence toko sendiri.",
        "You may only configure geofence for your own store.",
    ),
    "admin_gl_row_5e4b3cae7e": ("Persentase PPh", "Income tax (%)"),
    "admin_gl_row_6c55d78035": ("Nominal harus > 0.", "Amount must be > 0."),
    "admin_gl_row_6e51e7fc18": ("Tautan kontrak disalin", "Contract link copied"),
    "admin_gl_row_6e536f0165": ("Lembur tersimpan.", "Overtime saved."),
    "admin_gl_row_79e01c1296": ("Rp", "Rp"),
    "admin_gl_row_7b53b8eadd": ("Periode harus YYYY-MM.", "Period must be YYYY-MM."),
    "admin_gl_row_82e43f80b5": (
        "Nama, email, password (≥6) wajib.",
        "Name, email, and password (≥6) are required.",
    ),
    "admin_gl_row_87882bf29c": (
        "Isi keranjang dulu sebelum pakai voucher",
        "Fill the cart before applying a voucher",
    ),
    "admin_gl_row_8f309304d9": ("Nominal PPh", "Income tax amount"),
    "admin_gl_row_a2f8c79525": (
        "Akun karyawan bukan milik usaha ini.",
        "Employee account does not belong to this business.",
    ),
    "admin_gl_row_a3d58ac0e7": (
        "CSV bank disalin ke clipboard.",
        "Bank CSV copied to clipboard.",
    ),
    "admin_gl_row_a9c3fcf9b5": (
        "Isi nama pelanggan dulu sebelum buat QR.",
        "Enter customer name before generating QR.",
    ),
    "admin_gl_row_ab42f34873": (
        "Tautan disalin. Kirim via WA/email.",
        "Link copied. Send via WhatsApp/email.",
    ),
    "admin_gl_row_b019116111": (
        "Persentase harus jumlah 100.",
        "Percentages must total 100.",
    ),
    "admin_gl_row_bd5ca5dfe8": ("Periode sudah terkunci.", "Period already locked."),
    "admin_gl_row_c1df336d05": (
        "Tidak ada hasil untuk pencarian ini.",
        "No results for this search.",
    ),
    "admin_gl_row_c241d79f39": (
        "Isi jam dan rate lembur dengan benar.",
        "Enter valid overtime hours and rate.",
    ),
    "admin_gl_row_c98c868185": ("Mutasi saldo tercatat.", "Balance movement recorded."),
    "admin_gl_row_c9d49cfce6": ("Periode di-unlock (draft).", "Period unlocked (draft)."),
    "admin_gl_row_cffde148d9": (
        "Hanya Admin Pusat / Owner Utama.",
        "HQ Admin / Primary Owner only.",
    ),
    "admin_gl_row_d44c1425b8": ("Template dihapus.", "Template deleted."),
    "admin_gl_row_d7705cfa27": (
        "Tidak berhak menilai absensi toko ini.",
        "Not authorized to review attendance for this store.",
    ),
    "admin_gl_row_dd8132ddc1": (
        "Status sudah berubah. Muat ulang daftar.",
        "Status changed. Reload the list.",
    ),
    "admin_gl_row_e00217f90c": (
        "Data pelanggan terisi dari QR OBRCUS.",
        "Customer data filled from OBRCUS QR.",
    ),
    "admin_gl_row_f2c19b4d12": (
        "Belum ada karyawan di cabang ini.",
        "No employees in this branch yet.",
    ),
    "admin_gl_row_fdae65f210": ("Pilih cabang.", "Select a branch."),
}


def recover_from_git() -> dict[str, str]:
    diff = subprocess.run(
        ["git", "diff", "HEAD", "--", "lib/apps/admin"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    ).stdout
    mapping: dict[str, str] = {}
    lines = diff.split("\n")
    for i, line in enumerate(lines):
        if not line.startswith("+") or "admin_gl_row_" not in line or ".tr()" not in line:
            continue
        m = re.search(r"['\"](admin_gl_row_[a-z0-9_]+)['\"]\.tr\(\)", line)
        if not m:
            continue
        key = m.group(1)
        for j in range(i - 1, max(i - 20, -1), -1):
            prev = lines[j]
            if not prev.startswith("-") or prev.startswith("---"):
                continue
            sm = re.search(r"['\"]([^'\"\\]{2,})['\"]", prev[1:])
            if sm and not sm.group(1).startswith("admin_"):
                mapping[key] = sm.group(1)
                break
    return mapping


def main() -> None:
    id_d = json.loads(ID_PATH.read_text(encoding="utf-8"))
    en_d = json.loads(EN_PATH.read_text(encoding="utf-8"))
    git_map = recover_from_git()

    used: set[str] = set()
    for dart in ADMIN.rglob("*.dart"):
        used.update(KEY_RE.findall(dart.read_text(encoding="utf-8")))

    added = 0
    for key in sorted(used):
        if key in id_d and key in en_d:
            continue
        if key in KNOWN:
            id_val, en_val = KNOWN[key]
        elif key in git_map:
            id_val = git_map[key]
            en_val = en_d.get(key, id_val)
        else:
            id_val = key.replace("admin_gl_row_", "Missing: ")
            en_val = id_val
            print("WARN unknown", key)
        id_d[key] = id_val
        en_d[key] = en_val if isinstance(en_val, str) else id_val
        added += 1

    ID_PATH.write_text(json.dumps(id_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    EN_PATH.write_text(json.dumps(en_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("synced", added, "keys;", len(used), "admin_gl_row keys in dart")


if __name__ == "__main__":
    main()
