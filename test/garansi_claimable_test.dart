import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/garansi/garansi_service.dart';

void main() {
  /// Diambil hari Jakarta 2026-08-11 → akhir inklusif 2026-08-18 (hari ke-7).
  Map<String, dynamic> kartuAktif({
    String mulai = '2026-08-11',
    String? akhir,
    String status = 'aktif',
    bool klaimDigunakan = false,
    String? diambilAt,
  }) {
    return {
      'status': status,
      'klaim_digunakan': klaimDigunakan,
      'tanggal_mulai': mulai,
      'tanggal_akhir': akhir ?? '2026-08-18',
      if (diambilAt != null) 'diambil_at': diambilAt,
    };
  }

  /// Instant yang jatuh pada kalender Jakarta [y]-[m]-[d] siang (aman dari midnight edge).
  DateTime jktNoon(int y, int m, int d) =>
      DateTime.utc(y, m, d, 5); // 12:00 WIB

  group('window math (Jakarta, inklusif hari 7)', () {
    test('tanggalAkhirDariMulai = mulai + 7', () {
      expect(
        GaransiService.formatDate(
          GaransiService.tanggalAkhirDariMulai(DateTime(2026, 8, 11)),
        ),
        '2026-08-18',
      );
    });

    test('jakartaDateOnly follows Asia/Jakarta across UTC midnight', () {
      // 2026-08-11 17:00 UTC = 2026-08-12 00:00 WIB
      expect(
        GaransiService.formatDate(
          GaransiService.jakartaDateOnly(DateTime.utc(2026, 8, 11, 17)),
        ),
        '2026-08-12',
      );
      // 2026-08-11 16:59 UTC = masih 2026-08-11 23:59 WIB
      expect(
        GaransiService.formatDate(
          GaransiService.jakartaDateOnly(DateTime.utc(2026, 8, 11, 16, 59)),
        ),
        '2026-08-11',
      );
    });
  });

  group('GaransiService.kartuBisaDiklaim / alasanTidakBisaKlaim', () {
    test('day 0 (hari diambil) is claimable', () {
      final kartu = kartuAktif();
      final now = jktNoon(2026, 8, 11);
      expect(GaransiService.kartuBisaDiklaim(kartu, now: now), isTrue);
      expect(GaransiService.alasanTidakBisaKlaim(kartu, now: now), isNull);
      expect(GaransiService.statusLabel(kartu, now: now), 'Aktif (7 hari lagi)');
    });

    test('day 7 (tanggal_akhir) is still claimable — inclusive', () {
      final kartu = kartuAktif();
      final now = jktNoon(2026, 8, 18);
      expect(GaransiService.kartuBisaDiklaim(kartu, now: now), isTrue);
      expect(GaransiService.alasanTidakBisaKlaim(kartu, now: now), isNull);
      expect(GaransiService.statusLabel(kartu, now: now), 'Aktif (0 hari lagi)');
    });

    test('day 8 is mati / not claimable', () {
      final kartu = kartuAktif();
      final now = jktNoon(2026, 8, 19);
      expect(GaransiService.kartuBisaDiklaim(kartu, now: now), isFalse);
      expect(
        GaransiService.alasanTidakBisaKlaim(kartu, now: now),
        contains('mati'),
      );
      expect(GaransiService.statusLabel(kartu, now: now), 'Mati');
      expect(GaransiService.isGaransiMati(kartu, now: now), isTrue);
    });

    test('hard cap: tanggal_akhir too long still dies after mulai+7', () {
      final kartu = kartuAktif(akhir: '2099-01-01');
      final now = jktNoon(2026, 8, 19);
      expect(GaransiService.kartuBisaDiklaim(kartu, now: now), isFalse);
      expect(GaransiService.statusLabel(kartu, now: now), 'Mati');
    });

    test('hard cap: sisaHari ignores inflated tanggal_akhir', () {
      final kartu = kartuAktif(akhir: '2099-01-01');
      final now = jktNoon(2026, 8, 11);
      expect(GaransiService.sisaHari(kartu, now: now), 7);
      expect(
        GaransiService.formatDate(GaransiService.tanggalAkhirKartu(kartu)!),
        '2026-08-18',
      );
    });

    test('menunggu_ambil is blocked', () {
      final kartu = {
        'status': 'menunggu_ambil',
        'klaim_digunakan': false,
      };
      expect(GaransiService.kartuBisaDiklaim(kartu), isFalse);
      expect(
        GaransiService.alasanTidakBisaKlaim(kartu),
        contains('Belum aktif'),
      );
      expect(GaransiService.statusLabel(kartu), 'Menunggu ambil');
    });

    test('already claimed is blocked', () {
      final kartu = kartuAktif(status: 'diklaim', klaimDigunakan: true);
      expect(GaransiService.kartuBisaDiklaim(kartu), isFalse);
      expect(
        GaransiService.alasanTidakBisaKlaim(kartu),
        contains('sudah dipakai'),
      );
    });

    test('status habis is blocked with mati copy', () {
      final kartu = kartuAktif(status: 'habis');
      expect(GaransiService.kartuBisaDiklaim(kartu), isFalse);
      expect(
        GaransiService.alasanTidakBisaKlaim(kartu),
        contains('mati'),
      );
      expect(GaransiService.statusLabel(kartu), 'Mati');
    });

    test('diambil_at ISO uses Jakarta day for window', () {
      // Diambil 2026-08-11 20:00 WIB = 2026-08-11 13:00 UTC
      final kartu = {
        'status': 'aktif',
        'klaim_digunakan': false,
        'diambil_at': '2026-08-11T13:00:00.000Z',
        // sengaja tanpa tanggal_akhir — dihitung dari diambil_at
      };
      expect(
        GaransiService.kartuBisaDiklaim(kartu, now: jktNoon(2026, 8, 18)),
        isTrue,
      );
      expect(
        GaransiService.kartuBisaDiklaim(kartu, now: jktNoon(2026, 8, 19)),
        isFalse,
      );
    });
  });

  group('GaransiService.statusLabel', () {
    test('maps known statuses', () {
      expect(
        GaransiService.statusLabel({'status': 'menunggu_ambil'}),
        'Menunggu ambil',
      );
      expect(
        GaransiService.statusLabel({
          'status': 'diklaim',
          'klaim_digunakan': true,
        }),
        'Sudah diklaim',
      );
      expect(
        GaransiService.statusLabel({'status': 'habis'}),
        'Mati',
      );
      expect(
        GaransiService.statusLabel({'status': 'batal'}),
        'Dibatalkan',
      );
    });

    test('soft-expired aktif (day 8+) shows Mati without claim tap', () {
      final kartu = kartuAktif(); // masih status aktif di payload
      final now = jktNoon(2026, 8, 19);
      expect(GaransiService.statusLabel(kartu, now: now), 'Mati');
      expect(GaransiService.isGaransiMati(kartu, now: now), isTrue);
      expect(GaransiService.kartuBisaDiklaim(kartu, now: now), isFalse);
      expect(GaransiService.sisaHari(kartu, now: now), lessThan(0));
    });

    test('klaim_digunakan alone maps to Sudah diklaim', () {
      expect(
        GaransiService.statusLabel({
          'status': 'aktif',
          'klaim_digunakan': true,
          'tanggal_mulai': '2026-08-11',
          'tanggal_akhir': '2026-08-18',
        }),
        'Sudah diklaim',
      );
    });

    test('sisaHari menunggu_ambil is sentinel', () {
      expect(
        GaransiService.sisaHari({'status': 'menunggu_ambil'}),
        -999,
      );
    });
  });

  group('GaransiService.claimRequestStatusLabel', () {
    test('maps request statuses', () {
      expect(GaransiService.claimRequestStatusLabel('diajukan'), 'Diajukan');
      expect(
        GaransiService.claimRequestStatusLabel('diproses_toko'),
        'Diproses toko',
      );
      expect(GaransiService.claimRequestStatusLabel('selesai'), 'Selesai');
      expect(
        GaransiService.claimRequestStatusLabel('dibatalkan'),
        'Dibatalkan',
      );
    });
  });

  group('GaransiService.isOpenClaimRequestStatus / filterClaimableKartu', () {
    test('open statuses are diajukan + diproses_toko only', () {
      expect(GaransiService.isOpenClaimRequestStatus('diajukan'), isTrue);
      expect(GaransiService.isOpenClaimRequestStatus('diproses_toko'), isTrue);
      expect(GaransiService.isOpenClaimRequestStatus('selesai'), isFalse);
      expect(GaransiService.isOpenClaimRequestStatus('dibatalkan'), isFalse);
    });

    test('fail-closed when open requests unknown → empty claimable', () {
      final kartu = [
        {
          ...kartuAktif(),
          'id': 'k1',
          'jenis_garansi': 'lensa',
          'nama_produk': 'Blue',
        },
      ];
      final filtered = GaransiService.filterClaimableKartu(
        kartu: kartu,
        requests: const [],
        openRequestsKnown: false,
        now: jktNoon(2026, 8, 11),
      );
      expect(filtered, isEmpty);
    });

    test('excludes kartu with open request; keeps selesai/dibatalkan', () {
      final kartu = [
        {
          ...kartuAktif(),
          'id': 'k-open',
          'jenis_garansi': 'frame',
          'nama_produk': 'A',
        },
        {
          ...kartuAktif(),
          'id': 'k-ok',
          'jenis_garansi': 'lensa',
          'nama_produk': 'B',
        },
        {
          ...kartuAktif(),
          'id': 'k-done',
          'jenis_garansi': 'lensa',
          'nama_produk': 'C',
        },
      ];
      final filtered = GaransiService.filterClaimableKartu(
        kartu: kartu,
        requests: const [
          {'kartu_id': 'k-open', 'status': 'diajukan'},
          {'kartu_id': 'k-done', 'status': 'selesai'},
        ],
        openRequestsKnown: true,
        now: jktNoon(2026, 8, 11),
      );
      expect(filtered.map((e) => e['id']).toList(), ['k-ok', 'k-done']);
    });

    test('excludes menunggu_ambil / mati / already claimed', () {
      final kartu = [
        {
          'id': 'wait',
          'status': 'menunggu_ambil',
          'klaim_digunakan': false,
          'jenis_garansi': 'lensa',
          'nama_produk': 'X',
        },
        {
          ...kartuAktif(status: 'habis'),
          'id': 'dead',
          'jenis_garansi': 'lensa',
          'nama_produk': 'Y',
        },
        {
          ...kartuAktif(status: 'diklaim', klaimDigunakan: true),
          'id': 'used',
          'jenis_garansi': 'frame',
          'nama_produk': 'Z',
        },
        {
          ...kartuAktif(),
          'id': 'ok',
          'jenis_garansi': 'lensa',
          'nama_produk': 'OK',
        },
      ];
      final softExpired = GaransiService.filterClaimableKartu(
        kartu: [
          {
            ...kartuAktif(),
            'id': 'soft',
            'jenis_garansi': 'lensa',
            'nama_produk': 'Soft',
          },
        ],
        requests: const [],
        openRequestsKnown: true,
        now: jktNoon(2026, 8, 19), // day 8 → mati
      );
      expect(softExpired, isEmpty);

      final stillOk = GaransiService.filterClaimableKartu(
        kartu: kartu,
        requests: const [],
        openRequestsKnown: true,
        now: jktNoon(2026, 8, 11),
      );
      expect(stillOk.map((e) => e['id']).toList(), ['ok']);
    });
  });
}
