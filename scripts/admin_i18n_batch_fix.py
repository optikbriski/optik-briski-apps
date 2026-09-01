#!/usr/bin/env python3
"""Targeted fix for remaining admin i18n violations flagged by audit test."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADMIN = ROOT / "lib/apps/admin"
ID_PATH = ROOT / "assets/translations/id.json"
EN_PATH = ROOT / "assets/translations/en.json"

# exact dart substring -> (key, id text, en text optional)
EXACT: list[tuple[str, str, str, str | None]] = [
    (
        "'Surat jalan dibuat. Siapkan barang, foto packing, lalu tampilkan QR.'",
        "admin_auto_do_created_qr",
        "Surat jalan dibuat. Siapkan barang, foto packing, lalu tampilkan QR.",
        "Delivery order created. Prepare goods, packing photo, then show QR.",
    ),
    (
        "'Kurir dihapus dari surat jalan.'",
        "admin_auto_courier_removed_do",
        "Kurir dihapus dari surat jalan.",
        "Courier removed from delivery order.",
    ),
    (
        "'Bisa isi resi manual lewat tombol Resi manual.'",
        "admin_auto_manual_resi_hint",
        "Bisa isi resi manual lewat tombol Resi manual.",
        "You can enter tracking manually via Manual tracking button.",
    ),
    (
        "'Setelah dikirim, lacak status di panel Tracking di atas.'",
        "admin_auto_ro_track_hint",
        "Setelah dikirim, lacak status di panel Tracking di atas.",
        "After sending, track status in the Tracking panel above.",
    ),
    (
        "'libur Lebaran atur manual.'",
        "admin_auto_lebaran_manual",
        "libur Lebaran atur manual.",
        "Set Lebaran holiday manually.",
    ),
    (
        "'Pengajuan disetujui.'",
        "admin_auto_schedule_approved",
        "Pengajuan disetujui.",
        "Request approved.",
    ),
    (
        "'Pengajuan ditolak.'",
        "admin_auto_schedule_rejected",
        "Pengajuan ditolak.",
        "Request rejected.",
    ),
    (
        "'Pelunasan OK · PENDING'",
        "admin_auto_settlement_pending",
        "Pelunasan OK · PENDING",
        "Settlement OK · PENDING",
    ),
    (
        "'Email/WA boleh gagal — QR tetap valid di sistem.'",
        "admin_auto_qr_still_valid",
        "Email/WA boleh gagal — QR tetap valid di sistem.",
        "Email/WhatsApp may fail — QR remains valid in the system.",
    ),
    (
        "' → READY'",
        "admin_auto_status_ready",
        " → READY",
        " → READY",
    ),
    (
        '"⚠️ Data administrasi belum lengkap!"',
        "admin_auto_admin_data_incomplete",
        "⚠️ Data administrasi belum lengkap!",
        "⚠️ Admin data incomplete!",
    ),
    (
        '"⚠️ Masukkan nominal biaya yang dibayarkan sekarang!"',
        "admin_auto_enter_payment_now",
        "⚠️ Masukkan nominal biaya yang dibayarkan sekarang!",
        "⚠️ Enter the expense amount paid now!",
    ),
    (
        "'setujui transaksi kas'",
        "admin_auto_approve_cash_tx",
        "setujui transaksi kas",
        "approve cash transaction",
    ),
    (
        "'tolak transaksi kas'",
        "admin_auto_reject_cash_tx",
        "tolak transaksi kas",
        "reject cash transaction",
    ),
    (
        "'Ini mengurangi stok rak dan tercatat ledger WRITE_OFF.'",
        "admin_auto_writeoff_ledger_note",
        "Ini mengurangi stok rak dan tercatat ledger WRITE_OFF.",
        "This reduces shelf stock and is recorded in WRITE_OFF ledger.",
    ),
    (
        "'Bukan cabang Optik.'",
        "admin_auto_not_optik_branch",
        "Bukan cabang Optik.",
        "Not an Optik branch.",
    ),
    (
        "'Kulit Rekasa + kode usaha.'",
        "admin_auto_rekasa_skin_code",
        "Kulit Rekasa + kode usaha.",
        "Rekasa skin + business code.",
    ),
    (
        "'Pembayaran Midtrans dibatalkan'",
        "admin_auto_midtrans_cancelled",
        "Pembayaran Midtrans dibatalkan",
        "Midtrans payment cancelled",
    ),
    (
        "'• Pilih produk lain?'",
        "admin_auto_pick_other_product",
        "• Pilih produk lain?",
        "• Pick another product?",
    ),
    (
        "'Keranjang transaksi berhasil dikosongkan'",
        "admin_auto_cart_cleared",
        "Keranjang transaksi berhasil dikosongkan",
        "Transaction cart cleared",
    ),
    (
        "'Voucher tidak valid'",
        "admin_auto_voucher_invalid",
        "Voucher tidak valid",
        "Invalid voucher",
    ),
    (
        "'Voucher info saja — tidak ada potongan otomatis. '",
        "admin_auto_voucher_info_only",
        "Voucher info saja — tidak ada potongan otomatis.",
        "Voucher info only — no automatic discount.",
    ),
    (
        "'Stok tidak cukup — sudah di-hold saluran lain / POS lain'",
        "admin_auto_stock_hold_conflict",
        "Stok tidak cukup — sudah di-hold saluran lain / POS lain",
        "Insufficient stock — already held by another channel / POS",
    ),
    (
        "'Disetujui → Disiapkan (reservasi aktif).'",
        "admin_auto_ro_approved_prepare",
        "Disetujui → Disiapkan (reservasi aktif).",
        "Approved → Preparing (reservation active).",
    ),
]

# multiline replacements (old block substring -> new)
MULTILINE: list[tuple[str, str]] = [
    (
        """content: Text(
            'Surat jalan dibuat. Siapkan barang, foto packing, lalu tampilkan QR.'),""",
        "content: Text('admin_auto_do_created_qr'.tr()),",
    ),
    (
        """'Ambil foto bukti fisik paket. Stok cabang akan bertambah'
            ' dan Request Order ditandai selesai.'""",
        "'admin_auto_receive_photo_stock'.tr()",
    ),
    (
        """'Modul ikut paket. Kulit APK: paket A = merek sendiri, '
            'B/C = Rekasa + kode usaha. Data lama tetap.'""",
        "'admin_auto_tenant_module_skin'.tr()",
    ),
    (
        """'Stok Real diubah lewat Master Produk (revisi + scan QR) '
            'atau mutasi RO/DO/Retur/POS. '
            'Daftar cabang tidak menambah qty stok.'""",
        "'admin_auto_stock_real_master_hint'.tr()",
    ),
    (
        """'Akses ditolak. Hanya Owner & Admin Pusat yang dapat mengatur layout invoice.'""",
        "'admin_auto_invoice_layout_denied'.tr()",
    ),
    (
        """'Gagal simpan: jalankan migrasi '""",
        "'admin_auto_save_run_migration'.tr() + '",
    ),
]


def main() -> None:
    id_d = json.loads(ID_PATH.read_text(encoding="utf-8"))
    en_d = json.loads(EN_PATH.read_text(encoding="utf-8"))

    extra_id = {
        "admin_auto_receive_photo_stock": (
            "Ambil foto bukti fisik paket. Stok cabang akan bertambah "
            "dan Request Order ditandai selesai."
        ),
        "admin_auto_tenant_module_skin": (
            "Modul ikut paket. Kulit APK: paket A = merek sendiri, "
            "B/C = Rekasa + kode usaha. Data lama tetap."
        ),
        "admin_auto_stock_real_master_hint": (
            "Stok Real diubah lewat Master Produk (revisi + scan QR) "
            "atau mutasi RO/DO/Retur/POS. "
            "Daftar cabang tidak menambah qty stok."
        ),
        "admin_auto_invoice_layout_denied": (
            "Akses ditolak. Hanya Owner & Admin Pusat yang dapat mengatur layout invoice."
        ),
        "admin_auto_save_run_migration": "Gagal simpan: jalankan migrasi ",
        "admin_auto_tx_approved": "Transaksi {category} disetujui.",
        "admin_auto_tx_rejected": "Transaksi {category} ditolak & dihapus.",
        "admin_auto_checkout_voucher_fail": "Checkout dibatalkan — voucher gagal di-redeem: ",
        "admin_auto_checkout_critical_fail": "KRITIS: voucher gagal redeem & nota gagal dibatalkan. ",
        "admin_auto_lens_not_in_catalog": "} tidak tersedia di katalog cabang. Silakan klik Lapor Pusat!",
        "admin_auto_lens_stock_report": "}. Silakan klik Lapor Pusat!",
        "admin_auto_stock_not_changed": "}. Stok tidak diubah.",
    }
    extra_en = {k: v for k, v in extra_id.items()}  # EN polish later

    for old, key, id_text, en_text in EXACT:
        id_d[key] = id_text
        en_d[key] = en_text or id_text
        tr = f"'{key}'.tr()"
        for f in ADMIN.rglob("*.dart"):
            text = f.read_text()
            if old in text:
                f.write_text(text.replace(old, tr))
                print("exact", f.name, key)

    for k, v in extra_id.items():
        id_d[k] = v
        en_d[k] = extra_en.get(k, v)

    for old, new in MULTILINE:
        for f in ADMIN.rglob("*.dart"):
            text = f.read_text()
            if old in text:
                f.write_text(text.replace(old, new))
                print("multi", f.name)

    # coa interpolation snacks
    for f in [ADMIN / "coa_approval_page.dart"]:
        text = f.read_text()
        text = text.replace(
            '"Transaksi ${item[\'kategori\']} disetujui."',
            "'admin_auto_tx_approved'.tr(namedArgs: {'category': \"${item['kategori']}\"})",
        )
        text = text.replace(
            '"Transaksi ${item[\'kategori\']} ditolak & dihapus."',
            "'admin_auto_tx_rejected'.tr(namedArgs: {'category': \"${item['kategori']}\"})",
        )
        f.write_text(text)
        print("coa", f.name)

    # sales fallbacks
    sales = ADMIN / "sales_page.dart"
    t = sales.read_text()
    t = t.replace(
        "(res['error'] ?? 'Voucher tidak valid')",
        "(res['error'] ?? 'admin_auto_voucher_invalid'.tr())",
    )
    t = t.replace(
        "(res['error'] ??\n                  'Stok tidak cukup — sudah di-hold saluran lain / POS lain')",
        "(res['error'] ?? 'admin_auto_stock_hold_conflict'.tr())",
    )
    t = t.replace(
        "'Keranjang transaksi berhasil dikosongkan'",
        "'admin_auto_cart_cleared'.tr()",
    )
    sales.write_text(t)

    ID_PATH.write_text(json.dumps(id_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    EN_PATH.write_text(json.dumps(en_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("json", len(id_d))


if __name__ == "__main__":
    main()
