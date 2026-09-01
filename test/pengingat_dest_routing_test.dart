import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/apps/karyawan/pengingat_page.dart';
import 'package:optik_b_riski/shared/karyawan/karyawan_deep_link.dart';

void main() {
  test('jadwal decide notif opens pengajuan', () {
    expect(
      KaryawanDeepLink.destFor(
        tipe: 'SHIFT',
        judul: 'Pengajuan disetujui',
        isi: 'IJIN · 2026-08-27',
      ).dest,
      PengingatDest.pengajuan,
    );
    expect(
      KaryawanDeepLink.destFor(
        tipe: 'SHIFT',
        judul: 'Pengajuan ditolak',
        isi: 'CUTI',
      ).dest,
      PengingatDest.pengajuan,
    );
  });

  test('pengaduan reply opens pengaduan', () {
    expect(
      KaryawanDeepLink.destFor(
        tipe: 'PENGADUAN',
        judul: 'Balasan pengaduan',
        isi: 'Status DONE: sudah ditindak',
      ).dest,
      PengingatDest.pengaduan,
    );
  });

  test('order online / booking / pickup / antrian → antrian', () {
    expect(
      KaryawanDeepLink.destFor(
        tipe: 'INFO',
        judul: 'Order online baru',
        isi: 'Budi · paid',
      ).dest,
      PengingatDest.antrian,
    );
    expect(
      KaryawanDeepLink.destFor(
        tipe: 'INFO',
        judul: 'Booking baru',
        isi: 'cek mata · +6281',
      ).dest,
      PengingatDest.antrian,
    );
    expect(
      KaryawanDeepLink.destFor(
        tipe: 'INFO',
        judul: 'Pickup online',
        isi: 'ready',
      ).dest,
      PengingatDest.antrian,
    );
    expect(
      KaryawanDeepLink.destFor(
        tipe: 'ANTRIAN',
        judul: 'Antrian toko',
        isi: 'Ada pekerjaan baru',
      ).dest,
      PengingatDest.antrian,
    );
  });

  test('lab job notif → lab + job id', () {
    const job = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    final nav = KaryawanDeepLink.destFor(
      tipe: 'LAB',
      judul: 'Job lab baru',
      isi: 'INV-1 LAB_JOB:$job',
    );
    expect(nav.dest, PengingatDest.lab);
    expect(nav.labJobId, job);
  });

  test('deep link encode/parse roundtrip', () {
    final raw = KaryawanDeepLink.encode(
      dest: PengingatDest.antrian,
    );
    expect(KaryawanDeepLink.parse(raw)?.dest, PengingatDest.antrian);

    final lab = KaryawanDeepLink.encode(
      dest: PengingatDest.lab,
      labJobId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    );
    final parsed = KaryawanDeepLink.parse(lab);
    expect(parsed?.dest, PengingatDest.lab);
    expect(parsed?.labJobId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });
}
