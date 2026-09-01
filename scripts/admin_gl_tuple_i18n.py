#!/usr/bin/env python3
"""Replace enterprise_gl tuple row labels with .tr() keys."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GL = ROOT / "lib/apps/admin/enterprise_gl_page.dart"
ID_PATH = ROOT / "assets/translations/id.json"
EN_PATH = ROOT / "assets/translations/en.json"

EN: dict[str, str] = {
    "Referensi": "Reference",
    "Nama": "Name",
    "Toko": "Store",
    "Tanggal": "Date",
    "Umur": "Age",
    "Nominal": "Amount",
    "Jenis": "Type",
    "Pendapatan": "Revenue",
    "Beban": "Expense",
    "Laba": "Profit",
    "ID": "ID",
    "Bank": "Bank",
    "Akun GL": "GL account",
    "Aktif": "Active",
    "Mutasi termuat": "Transactions loaded",
    "Deskripsi": "Description",
    "Debit": "Debit",
    "Kredit": "Credit",
    "Status": "Status",
    "Match journal": "Match journal",
    "Bank account": "Bank account",
    "Akun": "Account",
    "Anggaran": "Budget",
    "Aktual": "Actual",
    "Selisih": "Variance",
    "Konteks": "Context",
    "Invoice": "Invoice",
    "Pembeli": "Buyer",
    "NPWP": "Tax ID",
    "DPP": "Tax base",
    "PPN": "VAT",
    "Sale ID": "Sale ID",
    "Bulan": "Month",
    "Closed at": "Closed at",
    "Closed by": "Closed by",
    "ID periode": "Period ID",
    "Laba bersih": "Net profit",
    "Jumlah akun": "Account count",
    "Laba berjalan": "Retained earnings",
    "Jumlah akun neraca": "Balance sheet accounts",
    "Aset lines": "Asset lines",
    "Kewajiban lines": "Liability lines",
    "Ekuitas lines": "Equity lines",
    "Jumlah cabang": "Branch count",
    "Total laba": "Total profit",
    "Periode": "Period",
    "Cabang": "Branch",
    "Ref": "Ref",
    "Detail": "Detail",
    "Kode": "Code",
    "Catatan": "Notes",
    "Muat ulang COA atau cek migrasi seed.": "Reload COA or check seed migration.",
    "Tidak ada di bagan akun lokal": "Not in local chart of accounts",
    "Sumber": "Source",
    "Total debit": "Total debit",
    "Total kredit": "Total credit",
    "Jumlah baris": "Line count",
    "No. rekening": "Account number",
    "Memo": "Memo",
    "Memo baris": "Line memo",
    "Memo jurnal": "Journal memo",
    "Entry ID": "Entry ID",
    "Line ID": "Line ID",
    "Saldo": "Balance",
    "Header": "Header",
    "Nonaktif": "Inactive",
    "Beban (+HPP)": "Expense (+COGS)",
    "Kas/Bank": "Cash/Bank",
    "Omzet bruto": "Gross revenue",
    "Omzet DPP": "Net revenue (tax base)",
    "Catatan HPP": "COGS notes",
    "Pengeluaran (FT vs MANUAL)": "Spending (FT vs MANUAL)",
    "% pakai": "% used",
    "Akun turunan": "Child accounts",
    "Mutasi periode": "Period movements",
    "Audit E2E General Ledger": "GL end-to-end audit",
    "Ya": "Yes",
    "Tidak": "No",
    "Temuan": "Findings",
    "Scope": "Scope",
    "Ringkasan": "Summary",
}


def slug(label: str) -> str:
    h = hashlib.md5(label.encode()).hexdigest()[:10]
    return f"admin_gl_row_{h}"


def main() -> None:
    id_d = json.loads(ID_PATH.read_text(encoding="utf-8"))
    en_d = json.loads(EN_PATH.read_text(encoding="utf-8"))
    content = GL.read_text(encoding="utf-8")
    original = content

    pat = re.compile(r"\(\s*'([^'$\\][^']{1,120})'\s*,")
    labels = sorted(set(m.group(1) for m in pat.finditer(content)))
    id_by_val = {v: k for k, v in id_d.items() if isinstance(v, str)}
    mapping: dict[str, str] = {}
    for label in labels:
        if label.startswith("admin_"):
            continue
        key = id_by_val.get(label)
        if not key:
            key = slug(label)
            if key not in id_d:
                id_d[key] = label
                en_d[key] = EN.get(label, label)
        mapping[label] = key

    for label, key in sorted(mapping.items(), key=lambda x: -len(x[0])):
        old = f"('{label}',"
        new = f"('{key}'.tr(),"
        if old in content:
            content = content.replace(old, new)

    # Multi-line tuple second elements with Indonesian prose
    prose_pat = [
        (
            "'Periode belum ada di tabel fiscal_periods.'",
            "'admin_gl_msg_period_missing'.tr()",
        ),
        (
            "'Setelah ditutup, tidak ada jurnal baru yang bisa diposting ke bulan ini.'",
            "'admin_gl_msg_period_closed'.tr()",
        ),
        (
            "'Draft siap unggah ke DJP. Integrasi API Coretax/e-Faktur tetap manual di portal.'",
            "'admin_gl_msg_efaktur_draft'.tr()",
        ),
    ]
    extras = {
        "admin_gl_msg_period_missing": (
            "Periode belum ada di tabel fiscal_periods.",
            "Period not in fiscal_periods table yet.",
        ),
        "admin_gl_msg_period_closed": (
            "Setelah ditutup, tidak ada jurnal baru yang bisa diposting ke bulan ini.",
            "After close, no new journals can post to this month.",
        ),
        "admin_gl_msg_efaktur_draft": (
            "Draft siap unggah ke DJP. Integrasi API Coretax/e-Faktur tetap manual di portal.",
            "Draft ready for DJP upload. Coretax/e-Invoice API integration remains manual on portal.",
        ),
    }
    for old, new in prose_pat:
        content = content.replace(old, new)
    for k, (idv, env) in extras.items():
        id_d.setdefault(k, idv)
        en_d.setdefault(k, env)

    if content != original:
        GL.write_text(content, encoding="utf-8")
        print("updated", GL.relative_to(ROOT), "labels", len(mapping))

    ID_PATH.write_text(json.dumps(id_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    EN_PATH.write_text(json.dumps(en_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("json keys", len(id_d))


if __name__ == "__main__":
    main()
