import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import 'lab_job_service.dart';

/// Display-time localization for Karyawan UI data that is stored in one language
/// (DB notifikasi, jadwal cards, pengajuan codes, SOP seed titles) so locale stays consistent.
class KaryawanI18nDisplay {
  KaryawanI18nDisplay._();

  static String notifJudul(String? raw) {
    final j = (raw ?? '').trim();
    switch (j) {
      case 'SOP belum selesai':
        return 'pengingat_judul_sop'.tr();
      case 'Jadwal hari ini':
        return 'pengingat_judul_jadwal'.tr();
      case 'Job lab baru':
        return 'pengingat_judul_lab'.tr();
      case 'SOP selesai':
        return 'pengingat_judul_sop_selesai'.tr();
      default:
        return j.isEmpty ? '-' : j;
    }
  }

  static String notifIsi(String? raw) {
    final isi = (raw ?? '').trim();
    if (isi.isEmpty) return '';

    final sop = RegExp(r'^Masih ada (\d+) tugas SOP hari ini\.$').firstMatch(isi);
    if (sop != null) {
      return 'pengingat_isi_sop'.tr(namedArgs: {'count': sop.group(1)!});
    }

    final shift = RegExp(r'^Shift:\s*(.+)$').firstMatch(isi);
    if (shift != null) {
      return 'pengingat_isi_jadwal'.tr(
        namedArgs: {'shift': shiftLabel(shift.group(1)!)},
      );
    }

    final lab = RegExp(
      r'^Invoice (.+) menunggu dikerjakan\. Ketuk Kerjakan di Antrian lab\. LAB_JOB:(.+)$',
    ).firstMatch(isi);
    if (lab != null) {
      final jobId = LabJobService.jobIdFromNotifikasiIsi(isi) ?? lab.group(2)!;
      return 'pengingat_isi_lab'.tr(namedArgs: {
        'invoice': lab.group(1)!,
        'job': jobId,
      });
    }

    final poin = RegExp(r'^Poin \+(\d+) berhasil diklaim hari ini\.$').firstMatch(isi);
    if (poin != null) {
      return 'pengingat_isi_sop_selesai'.tr(namedArgs: {'poin': poin.group(1)!});
    }

    return isi;
  }

  static String shiftLabel(String raw) {
    final s = raw.trim();
    switch (s) {
      case 'Belum dijadwalkan':
        return 'jadwal_belum'.tr();
      case 'Libur':
        return 'jadwal_libur'.tr();
      default:
        return s;
    }
  }

  static String hariLabel(String raw) {
    switch (raw.trim()) {
      case 'Senin':
        return 'hari_senin'.tr();
      case 'Selasa':
        return 'hari_selasa'.tr();
      case 'Rabu':
        return 'hari_rabu'.tr();
      case 'Kamis':
        return 'hari_kamis'.tr();
      case 'Jumat':
        return 'hari_jumat'.tr();
      case 'Sabtu':
        return 'hari_sabtu'.tr();
      case 'Minggu':
        return 'hari_minggu'.tr();
      default:
        return raw;
    }
  }

  /// Formats `yyyy-MM-dd` with the UI locale (avoids hardcoded `id_ID` month names).
  static String tanggalLabel({
    String? dateKey,
    String? fallback,
    Locale? locale,
  }) {
    final key = (dateKey ?? '').trim();
    if (key.isNotEmpty) {
      try {
        final d = DateTime.parse(key);
        final lang = (locale?.languageCode ?? 'en').toLowerCase();
        final months = switch (lang) {
          'id' => _monthsId,
          'ms' => _monthsMs,
          'zh' => _monthsZh,
          'ja' => _monthsJa,
          _ => _monthsEn,
        };
        return '${d.day} ${months[d.month - 1]}';
      } catch (_) {}
    }
    return (fallback ?? '').trim();
  }

  static const _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthsId = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  static const _monthsMs = [
    'Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun',
    'Jul', 'Ogo', 'Sep', 'Okt', 'Nov', 'Dis',
  ];
  static const _monthsZh = [
    '1月', '2月', '3月', '4月', '5月', '6月',
    '7月', '8月', '9月', '10月', '11月', '12月',
  ];
  static const _monthsJa = [
    '1月', '2月', '3月', '4月', '5月', '6月',
    '7月', '8月', '9月', '10月', '11月', '12月',
  ];

  static String pengajuanTipe(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'IJIN':
        return 'pengajuan_tipe_ijin'.tr();
      case 'CUTI':
        return 'pengajuan_tipe_cuti'.tr();
      case 'TUKAR':
        return 'pengajuan_tipe_tukar'.tr();
      default:
        return (raw ?? '-').trim().isEmpty ? '-' : raw!.trim();
    }
  }

  static String pengajuanStatus(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'PENDING':
        return 'pengajuan_status_pending'.tr();
      case 'APPROVED':
        return 'pengajuan_status_approved'.tr();
      case 'REJECTED':
        return 'pengajuan_status_rejected'.tr();
      case 'CANCELLED':
      case 'CANCELED':
        return 'pengajuan_status_cancelled'.tr();
      default:
        return (raw ?? '-').trim().isEmpty ? '-' : raw!.trim();
    }
  }

  /// Maps known SOP seed titles (stored Indonesian) to locale strings.
  static String sopTugas(String? raw) {
    final t = (raw ?? '').trim();
    switch (t) {
      case 'Rapikan area kerja':
        return 'sop_tugas_rapikan_area'.tr();
      case 'Foto kondisi toko pagi':
        return 'sop_tugas_foto_kondisi_pagi'.tr();
      case 'Cek kebersihan area kasir':
        return 'sop_tugas_cek_kebersihan_kasir'.tr();
      case 'Hitung modal kas awal':
        return 'sop_tugas_hitung_modal_kas'.tr();
      case 'Foto display etalase depan':
        return 'sop_tugas_foto_display_etalase'.tr();
      case 'Scan penerimaan barang (jika ada)':
        return 'sop_tugas_scan_penerimaan_barang'.tr();
      case 'Siapkan alat RO & kalibrasi':
        return 'sop_tugas_siapkan_alat_ro'.tr();
      case 'Dokumentasi ruang periksa':
        return 'sop_tugas_dokumentasi_ruang_periksa'.tr();
      case 'Cek stok lensa trial':
        return 'sop_tugas_cek_stok_lensa_trial'.tr();
      case 'Scan penerimaan lensa':
        return 'sop_tugas_scan_penerimaan_lensa'.tr();
      case 'Briefing tim pagi':
        return 'sop_tugas_briefing_tim_pagi'.tr();
      case 'Cek stok kritis':
        return 'sop_tugas_cek_stok_kritis'.tr();
      case 'Scan penerimaan gudang':
        return 'sop_tugas_scan_penerimaan_gudang'.tr();
      case 'Catat target harian':
        return 'sop_tugas_catat_target_harian'.tr();
      case 'Buka toko: cek kebersihan & etalase':
        return 'sop_tugas_buka_cek_kebersihan'.tr();
      case 'Tutup toko: rapikan area & matikan perangkat':
        return 'sop_tugas_tutup_rapikan'.tr();
      case 'Buka toko: siapkan area kerja belakang':
        return 'sop_tugas_buka_area_belakang'.tr();
      case 'Tutup toko: amankan stok & dokumen':
        return 'sop_tugas_tutup_amankan_stok'.tr();
      case 'Buka toko: briefing & cek kesiapan tim':
        return 'sop_tugas_buka_briefing_tim'.tr();
      case 'Tutup toko: rekap harian & kunci toko':
        return 'sop_tugas_tutup_rekap_kunci'.tr();
      default:
        return t.isEmpty ? '-' : t;
    }
  }

  static String pengumumanJudul(String? raw) {
    final j = (raw ?? '').trim();
    switch (j) {
      case 'Briefing pagi':
        return 'pengumuman_briefing_pagi_judul'.tr();
      default:
        return j.isEmpty ? '-' : j;
    }
  }

  static String pengumumanIsi(String? raw) {
    final isi = (raw ?? '').trim();
    switch (isi) {
      case 'Cek display & kebersihan area sebelum buka. Laporkan kendala ke Kepala Toko.':
        return 'pengumuman_briefing_pagi_isi'.tr();
      default:
        return isi;
    }
  }
}
