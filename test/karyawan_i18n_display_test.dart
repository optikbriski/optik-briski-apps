import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/karyawan_i18n_display.dart';

void main() {
  test('known notif titles are routed to i18n keys (not left as ID raw)', () {
    // Without EasyLocalization assets, .tr() returns the key name.
    expect(KaryawanI18nDisplay.notifJudul('Job lab baru'), 'pengingat_judul_lab');
    expect(KaryawanI18nDisplay.notifJudul('SOP belum selesai'), 'pengingat_judul_sop');
    expect(KaryawanI18nDisplay.notifJudul('Jadwal hari ini'), 'pengingat_judul_jadwal');
  });

  test('shift and pengajuan codes map to i18n keys', () {
    expect(KaryawanI18nDisplay.shiftLabel('Belum dijadwalkan'), 'jadwal_belum');
    expect(KaryawanI18nDisplay.pengajuanStatus('APPROVED'), 'pengajuan_status_approved');
    expect(KaryawanI18nDisplay.pengajuanTipe('IJIN'), 'pengajuan_tipe_ijin');
  });

  test('lab isi maps to i18n key (runtime fills invoice/job args)', () {
    const isi =
        'Invoice INV-1 menunggu dikerjakan. Ketuk Kerjakan di Antrian lab. LAB_JOB:e4bab45a-bddd-4160-80d1-12a8112fe5cd';
    final out = KaryawanI18nDisplay.notifIsi(isi);
    expect(out, 'pengingat_isi_lab');
  });

  test('SOP seed titles and briefing pengumuman map to i18n keys', () {
    expect(
      KaryawanI18nDisplay.sopTugas('Foto kondisi toko pagi'),
      'sop_tugas_foto_kondisi_pagi',
    );
    expect(
      KaryawanI18nDisplay.sopTugas('Rapikan area kerja'),
      'sop_tugas_rapikan_area',
    );
    expect(
      KaryawanI18nDisplay.pengumumanJudul('Briefing pagi'),
      'pengumuman_briefing_pagi_judul',
    );
    expect(
      KaryawanI18nDisplay.pengumumanIsi(
        'Cek display & kebersihan area sebelum buka. Laporkan kendala ke Kepala Toko.',
      ),
      'pengumuman_briefing_pagi_isi',
    );
  });

  test('tanggalLabel uses locale month names from date_key', () {
    expect(
      KaryawanI18nDisplay.tanggalLabel(
        dateKey: '2026-08-25',
        locale: const Locale('en'),
      ),
      '25 Aug',
    );
    expect(
      KaryawanI18nDisplay.tanggalLabel(
        dateKey: '2026-08-25',
        locale: const Locale('id'),
      ),
      '25 Agu',
    );
  });
}
