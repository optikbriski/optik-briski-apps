#!/usr/bin/env python3
"""One-shot: replace hardcoded Admin UI strings with .tr() + sync id/en JSON."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADMIN = ROOT / "lib/apps/admin"
ID_PATH = ROOT / "assets/translations/id.json"
EN_PATH = ROOT / "assets/translations/en.json"

IMPORT = "import 'package:easy_localization/easy_localization.dart';\n"

# Exact Indonesian/English UI → existing key
EXISTING: dict[str, str] = {
    "Batal": "appr_btn_batal",
    "Simpan": "btn_simpan",
    "Hapus": "btn_hapus",
    "Tutup": "admin_btn_close",
    "Muat ulang": "admin_btn_refresh",
    "Coba lagi": "common_retry",
    "Refresh": "admin_btn_refresh",
    "Detail": "admin_btn_detail",
    "Tolak": "appr_btn_tolak",
    "Setujui": "appr_btn_setujui",
    "Lanjut": "admin_btn_lanjut",
    "Ya, catat": "admin_btn_ya_catat",
    "Retry": "common_retry",
    "BATAL": "appr_btn_batal",
    "OK": "admin_btn_ok",
    "Daftar": "admin_btn_daftar",
    "Cari": "admin_btn_cari",
    "Kirim": "admin_btn_kirim",
    "Catatan": "admin_lbl_catatan",
    "Alasan": "admin_lbl_alasan",
    "Nominal (Rp)": "admin_lbl_nominal_rp",
    "Lunasi": "admin_btn_lunasi",
    "Scan": "admin_btn_scan",
    "Naik": "admin_btn_naik",
    "Turun": "admin_btn_turun",
    "Fullscreen": "admin_btn_fullscreen",
    "Pilih": "admin_btn_pilih",
    "Aktif": "admin_lbl_aktif",
    "Update": "admin_btn_update",
    "Generate": "admin_btn_generate",
    "Rekening": "admin_lbl_rekening",
    "Mutasi": "admin_lbl_mutasi",
    "Anggaran": "admin_lbl_anggaran",
    "Sinkronkan": "admin_btn_sinkronkan",
    "Kunci": "admin_btn_kunci",
    "TIDAK": "admin_btn_tidak",
    "YA, BATALKAN": "admin_btn_ya_batalkan",
    "Ulang": "admin_btn_ulang",
    "Catat": "admin_btn_catat",
}

# Manual EN for generated keys (Indonesian source → English)
EN_MANUAL: dict[str, str] = {
    "Hanya Owner / Admin Pusat.": "Owner / HQ Admin only.",
    "Upload gagal: {error}": "Upload failed: {error}",
    "Simpan draft?": "Save draft?",
    "Simpan draft": "Save draft",
    "Buang draft?": "Discard draft?",
    "Buang draft": "Discard draft",
    "Keluar tanpa Update?": "Leave without updating?",
    "Lanjut edit": "Continue editing",
    "Buang & keluar": "Discard & leave",
    "Update ke APK Member?": "Push update to Member APK?",
    "Update APK": "Update APK",
    "Beranda Member diperbarui di APK.": "Member home updated on APK.",
    "Ada edit baru. Tekan Simpan dulu, lalu Update.": "Unsaved edits. Save first, then Update.",
    "Judul wajib diisi": "Title is required",
    "Nilai diskon harus > 0 untuk Nominal/Persen": "Discount must be > 0 for amount/percent",
    "Promo masuk draft. Simpan → Update untuk ke APK.": "Promo saved to draft. Save → Update for APK.",
    "Hapus promo dari draft?": "Remove promo from draft?",
    "Tampil di APK Member": "Show on Member APK",
    "Bisa dipakai di POS": "Usable in POS",
    "Tambah slide": "Add slide",
    "Buka tab Banner (panduan ukuran)": "Open Banner tab (size guide)",
    "Tambah banner": "Add banner",
    "Ganti gambar": "Change image",
    "Hapus gambar": "Remove image",
    "Lihat preview beranda lengkap": "View full home preview",
    "Belanja Online": "Online shopping",
    "Janji Kontrol": "Follow-up appointment",
    "Pilih bagian di preview HP.": "Pick a section in phone preview.",
    "Buka tab Promo lengkap": "Open full Promo tab",
    "Gambar": "Image",
    "Tambah": "Add",
    "Buang": "Discard",
    "Sinkronkan GL historis?": "Sync historical GL?",
    "Gagal sinkron GL: {error}": "GL sync failed: {error}",
    "Tutup periode {period}?": "Close period {period}?",
    "Periode berhasil ditutup": "Period closed successfully",
    "Gagal menutup periode: {error}": "Failed to close period: {error}",
    "Periode dibuka kembali": "Period reopened",
    "Gagal membuka periode: {error}": "Failed to reopen period: {error}",
    "Sinkronkan GL historis": "Sync historical GL",
    "Ekspor PDF": "Export PDF",
    "Gagal ekspor: {error}": "Export failed: {error}",
    "Aging piutang": "Receivables aging",
    "Tidak ada piutang terbuka.": "No open receivables.",
    "Aging hutang": "Payables aging",
    "Tidak ada hutang terbuka.": "No open payables.",
    "Rekonsiliasi bank": "Bank reconciliation",
    "Belum ada mutasi bank.": "No bank transactions yet.",
    "Tambah rekening bank": "Add bank account",
    "Tambah mutasi bank": "Add bank transaction",
    "Anggaran vs aktual": "Budget vs actual",
    "Set anggaran": "Set budget",
    "Draft e-Faktur": "e-Invoice draft",
    "Tandai ekspor": "Mark exported",
    "e-Faktur: {n} dibuat": "e-Invoice: {n} created",
    "Gagal generate e-Faktur: {error}": "Failed to generate e-Invoice: {error}",
    "Tidak ada draft siap ditandai ekspor": "No draft ready to mark exported",
    "Periode aktif: {period}": "Active period: {period}",
    "Status: {status}": "Status: {status}",
    "Riwayat periode": "Period history",
    "Laba berjalan": "Retained earnings",
    "Ref: {ref}": "Ref: {ref}",
    "Reset ke semua cabang": "Reset to all branches",
    "Gagal sinkron: {error}": "Sync failed: {error}",
    "Nama Produk Wajib Diisi!": "Product name is required!",
    "Barcode Bawaan Produk Wajib Diisi / Di-scan!": "Product barcode is required / must be scanned!",
    "Gagal: {error}": "Failed: {error}",
    "Stok baru tidak valid.": "Invalid new stock.",
    "Alasan revisi wajib.": "Revision reason is required.",
    "Tidak ada perubahan stok.": "No stock change.",
    "Gagal revisi: {error}": "Revision failed: {error}",
    "Revisi stok Real": "Revise real stock",
    "Pilih Semua": "Select all",
    "Konfirmasi daftar cabang": "Confirm branch list",
    "Ya, daftarkan": "Yes, register",
    "Grup tampilan": "Display group",
    "Gagal ambil footer Pusat: {error}": "Failed to load HQ footer: {error}",
    "Gagal menyimpan: {error}": "Save failed: {error}",
    "Setting PUSAT tidak boleh dihapus.": "HQ settings cannot be deleted.",
    "Buat tagihan": "Create invoice",
    "Buat kontrak online": "Create online contract",
    "Surat jalan dibatalkan. Booking dilepas.": "Delivery order cancelled. Booking released.",
    "Gagal mengekspor PDF: {error}": "PDF export failed: {error}",
    "Catat keuangan manual": "Record manual finance entry",
    "Gagal menyimpan entri: {error}": "Failed to save entry: {error}",
    "Simpan jurnal": "Save journal",
    "Tidak ada tindakan yang tersedia untuk transaksi ini.": "No actions available for this transaction.",
    "Hapus transaksi?": "Delete transaction?",
    "Gagal menghapus rekaman: {error}": "Failed to delete record: {error}",
    "DPP (omzet netto):": "Tax base (net revenue):",
    "PPN keluaran (11%):": "Output VAT (11%):",
    "Masuk: {amount}": "In: {amount}",
    "Keluar: {amount}": "Out: {amount}",
    "Netto: {amount}": "Net: {amount}",
    "Laba bersih harian": "Daily net profit",
    "Barang keluar & margin": "Goods out & margin",
    "Total": "Total",
    "Beban OPEX & mutasi operasional": "OPEX & operational movements",
    "Foto & terima": "Photo & receive",
    "Surat jalan tidak ditemukan.": "Delivery order not found.",
    "Paket ditujukan ke {dest}, bukan {toko}.": "Package addressed to {dest}, not {toko}.",
    "Paket sudah diterima sebelumnya.": "Package already received.",
    "Gagal terima paket: {error}": "Failed to receive package: {error}",
    "Panggil kurir Biteship?": "Call Biteship courier?",
    "Panggil kurir": "Call courier",
    "Memanggil Biteship…": "Calling Biteship…",
    "Menyimpan…": "Saving…",
    "Simpan pengaturan": "Save settings",
    "Cari invoice / nama / WA…": "Search invoice / name / phone…",
    "Gagal ambil data database PUSAT: {error}": "Failed to load HQ database: {error}",
    "Tidak ada saran restock untuk produk ini": "No restock suggestion for this product",
    "Gagal menyimpan draft: {error}": "Failed to save draft: {error}",
    "Buat surat jalan": "Create delivery order",
    "Ganti cabang": "Switch branch",
    "Approval ijin / tukar": "Leave / swap approval",
    "Belum ada data cabang di toko_id.": "No branch data in toko_id yet.",
    "Cari nama / kode toko…": "Search store name / code…",
    "Tidak ada cabang cocok.": "No matching branch.",
    "Pastikan migration toko_shift_settings sudah dijalankan.": "Ensure toko_shift_settings migration has been applied.",
    "Submit & kunci periode?": "Submit & lock period?",
    "Terapkan “{name}”?": "Apply “{name}”?",
    "Gagal muat daftar toko: {error}": "Failed to load store list: {error}",
    "Tolak request?": "Reject request?",
    "Kode usaha (≥3) dan nama merek wajib.": "Business code (≥3) and brand name required.",
    "APK & web merek sendiri": "Branded APK & web",
    "UMKM / Tenant": "SME / Tenant",
    "Gagal set kurir: {error}": "Failed to set courier: {error}",
    "Cari resi, cabang, kurir…": "Search tracking, branch, courier…",
    "Payroll & Saldo Owner": "Payroll & Owner balance",
    "Buka Payroll & bonus (fleksibel)": "Open Payroll & bonus (flexible)",
    "Kunci period setelah run": "Lock period after run",
    "Lunas & sistem dinyalakan.": "Paid & system enabled.",
    "Video & teks fitur": "Feature video & text",
    "Penjelasan fitur disimpan.": "Feature description saved.",
    "Hapus terakhir": "Delete last",
    "Gagal catat stok rusak: {error}": "Failed to record damaged stock: {error}",
    "Scan atau ketik lalu cari": "Scan or type then search",
    "Hanya admin toko/cabang ini yang boleh catat stok rusak.": "Only this store/branch admin may record damaged stock.",
    "Detail Transaksi": "Transaction detail",
    "Bukti foto": "Photo proof",
    "Tindakan Cepat": "Quick action",
    "Buat Owner": "Create Owner",
    "Owner Utama (semua cabang)": "Primary Owner (all branches)",
    "Owner Toko (franchise)": "Store Owner (franchise)",
    "Isi nama usaha dan WA/HP.": "Enter business name and phone.",
    "Detail (video + penjelasan)": "Details (video + description)",
    "Selisih tercatat. Cek ulang untuk pastikan AMAN.": "Variance recorded. Double-check to ensure SAFE.",
    "Invoice / pelanggan / resi / produk…": "Invoice / customer / tracking / product…",
    "Buka Verifikasi Terima": "Open Receive Verification",
    "Tinjauan Mencurigakan": "Suspicious review",
    "Detail Audit Pusat": "HQ audit detail",
    "Cetak / Bagikan Struk": "Print / share receipt",
    "Detail Internal Pusat": "HQ internal detail",
    "Putar video penjelasan": "Play feature video",
    "Pilih tanggal": "Pick date",
    "← Halaman utama": "← Main page",
    "Gagal memproses retur: {error}": "Failed to process return: {error}",
    "Stok di Cabang: {n} PCS": "Branch stock: {n} PCS",
    "Scan wedge atau ketik lalu Enter": "Scan wedge or type then Enter",
    "Contoh: PROMO50": "Example: PROMO50",
    "Detail Audit Pusat": "HQ audit detail",
    "Periode (YYYY-MM)": "Period (YYYY-MM)",
    "Tutup periode": "Close period",
    "Laba bersih harian": "Daily net profit",
}


def slug_key(text: str) -> str:
    if text in EXISTING:
        return EXISTING[text]
    h = hashlib.md5(text.encode()).hexdigest()[:10]
    return f"admin_auto_{h}"


def to_template(s: str) -> tuple[str, dict[str, str]]:
    """Convert Dart interpolation to namedArgs template."""
    repl = {
        r"\$e": "{error}",
        r"\$n": "{n}",
        r"\$nama": "{name}",
        r"\$_periodLabel": "{period}",
        r"\$_myToko": "{toko}",
        r"\$ke": "{dest}",
        r"\$maxStok": "{n}",
        r"\$totalHarga": "{amount}",
    }
    named: dict[str, str] = {}
    out = s
    for dart, ph in repl.items():
        if dart.replace("\\", "") in s or dart in s:
            pass
    # simpler: regex $identifier
    def sub(m: re.Match) -> str:
        var = m.group(1)
        key = {
            "e": "error",
            "n": "n",
            "nama": "name",
            "_periodLabel": "period",
            "_myToko": "toko",
            "ke": "dest",
            "maxStok": "n",
            "totalHarga": "amount",
        }.get(var, var.replace("_", ""))
        named[key] = f"${var}" if not var.startswith("_") else f"${var}"
        return "{" + key + "}"

    out = re.sub(r"\$(\w+)", sub, s)
    out = re.sub(r"\\?\$e", "{error}", out)
    return out, named


def tr_replacement(text: str, key: str, template: str, named: dict[str, str]) -> str:
    if not named:
        return f"'{key}'.tr()"
    args = ", ".join(f"'{k}': '{v}'" for k, v in named.items())
    return f"'{key}'.tr(namedArgs: {{{args}}})"


def main() -> None:
    id_d = json.loads(ID_PATH.read_text(encoding="utf-8"))
    en_d = json.loads(EN_PATH.read_text(encoding="utf-8"))

    # Build reverse map id value → key for exact matches
    id_by_val = {v: k for k, v in id_d.items() if isinstance(v, str)}

    replacements: list[tuple[str, str, str]] = []  # pattern prefix, old, new

    for f in sorted(ADMIN.rglob("*.dart")):
        original = f.read_text(encoding="utf-8")
        content = original
        changed = False

        def replace_literal(prefix: str, quote: str, s: str) -> None:
            nonlocal content, changed
            if ".tr(" in s:
                return
            template, named = to_template(s)
            key = EXISTING.get(s) or EXISTING.get(template)
            if not key:
                key = id_by_val.get(template) or id_by_val.get(s)
            if not key:
                key = slug_key(template)
                if key not in id_d:
                    id_d[key] = template
                    en_d[key] = EN_MANUAL.get(template) or EN_MANUAL.get(s) or template
            tr = tr_replacement(s, key, template, named)
            old = f"{prefix}({quote}{s}{quote}"
            new = f"{prefix}({tr}"
            if old in content:
                content = content.replace(old, new)
                changed = True

        for line in original.splitlines():
            if ".tr(" in line or "debugPrint" in line:
                continue
            for quote in ("'", '"'):
                for m in re.finditer(
                    rf"(Text|const Text|title: Text|content: Text|label: const Text|label: Text|child: const Text|child: Text)\(\s*{quote}([^{quote}\\]{{2,150}}){quote}",
                    line,
                ):
                    prefix, s = m.group(1), m.group(2)
                    if "${" in s:
                        continue
                    replace_literal(prefix, quote, s)
                for m in re.finditer(
                    rf"(tooltip|hintText|labelText|title|subtitle|message|label):\s*{quote}([^{quote}\\]{{2,150}}){quote}",
                    line,
                ):
                    prefix, s = m.group(1), m.group(2)
                    if "${" in s:
                        continue
                    template, named = to_template(s)
                    key = EXISTING.get(s) or id_by_val.get(s) or slug_key(template)
                    if key not in id_d:
                        id_d[key] = template if "{" in template else s
                        en_d[key] = EN_MANUAL.get(template) or EN_MANUAL.get(s) or id_d[key]
                    tr = tr_replacement(s, key, template, named)
                    old = f"{prefix}: {quote}{s}{quote}"
                    new = f"{prefix}: {tr}"
                    if old in content:
                        content = content.replace(old, new)
                        changed = True

        if changed:
            if "easy_localization" not in content:
                idx = content.find("import ")
                if idx >= 0:
                    end = content.find("\n", idx)
                    content = content[: end + 1] + IMPORT + content[end + 1 :]
            f.write_text(content, encoding="utf-8")
            print("updated", f.relative_to(ROOT))

    # Add small shared keys if missing
    extras_id = {
        "admin_btn_ok": "OK",
        "admin_btn_daftar": "Daftar",
        "admin_btn_kirim": "Kirim",
        "admin_lbl_catatan": "Catatan",
        "admin_lbl_alasan": "Alasan",
        "admin_lbl_nominal_rp": "Nominal (Rp)",
        "admin_btn_lunasi": "Lunasi",
        "admin_btn_scan": "Scan",
        "admin_btn_naik": "Naik",
        "admin_btn_turun": "Turun",
        "admin_btn_fullscreen": "Fullscreen",
        "admin_btn_pilih": "Pilih",
        "admin_lbl_aktif": "Aktif",
        "admin_btn_update": "Update",
        "admin_btn_generate": "Generate",
        "admin_lbl_rekening": "Rekening",
        "admin_lbl_mutasi": "Mutasi",
        "admin_lbl_anggaran": "Anggaran",
        "admin_btn_sinkronkan": "Sinkronkan",
        "admin_btn_kunci": "Kunci",
        "admin_btn_tidak": "TIDAK",
        "admin_btn_ya_batalkan": "YA, BATALKAN",
        "admin_btn_ulang": "Ulang",
        "admin_btn_catat": "Catat",
    }
    extras_en = {
        "admin_btn_ok": "OK",
        "admin_btn_daftar": "Register",
        "admin_btn_kirim": "Send",
        "admin_lbl_catatan": "Notes",
        "admin_lbl_alasan": "Reason",
        "admin_lbl_nominal_rp": "Amount (Rp)",
        "admin_btn_lunasi": "Pay balance",
        "admin_btn_scan": "Scan",
        "admin_btn_naik": "Up",
        "admin_btn_turun": "Down",
        "admin_btn_fullscreen": "Fullscreen",
        "admin_btn_pilih": "Select",
        "admin_lbl_aktif": "Active",
        "admin_btn_update": "Update",
        "admin_btn_generate": "Generate",
        "admin_lbl_rekening": "Account",
        "admin_lbl_mutasi": "Transactions",
        "admin_lbl_anggaran": "Budget",
        "admin_btn_sinkronkan": "Sync",
        "admin_btn_kunci": "Lock",
        "admin_btn_tidak": "NO",
        "admin_btn_ya_batalkan": "YES, CANCEL",
        "admin_btn_ulang": "Redo",
        "admin_btn_catat": "Record",
    }
    for k, v in extras_id.items():
        id_d.setdefault(k, v)
    for k, v in extras_en.items():
        en_d.setdefault(k, v)

    ID_PATH.write_text(json.dumps(id_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    EN_PATH.write_text(json.dumps(en_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("JSON updated", len(id_d), "keys")


if __name__ == "__main__":
    main()
