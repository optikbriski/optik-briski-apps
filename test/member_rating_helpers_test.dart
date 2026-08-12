import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_rating_helpers.dart';

void main() {
  group('MemberRatingHelpers', () {
    test('pending when taken and no ratings yet', () {
      final row = {
        'bisa_rating': true,
        'nama_kasir': 'A',
        'nama_pembuat_kacamata': 'B',
        'has_rating_kasir': false,
        'has_rating_pembuat': false,
      };
      expect(MemberRatingHelpers.isPendingToRate(row), isTrue);
      expect(MemberRatingHelpers.isComplete(row), isFalse);
    });

    test('complete when both assigned roles rated', () {
      final row = {
        'bisa_rating': true,
        'nama_kasir': 'A',
        'nama_pembuat_kacamata': 'B',
        'rating_kasir': {'skor': 5},
        'rating_pembuat': {'skor': 4},
        'has_rating_kasir': true,
        'has_rating_pembuat': true,
      };
      expect(MemberRatingHelpers.isPendingToRate(row), isFalse);
      expect(MemberRatingHelpers.isComplete(row), isTrue);
      expect(MemberRatingHelpers.isHistory(row), isTrue);
    });

    test('partial stays pending and history', () {
      final row = {
        'tracking_status': 'DIAMBIL',
        'nama_kasir': 'A',
        'nama_pembuat_kacamata': 'B',
        'rating_kasir': {'skor': 5},
        'has_rating_kasir': true,
        'has_rating_pembuat': false,
      };
      expect(MemberRatingHelpers.isPendingToRate(row), isTrue);
      expect(MemberRatingHelpers.isHistory(row), isTrue);
      expect(MemberRatingHelpers.isComplete(row), isFalse);
    });

    test('not taken is not pending', () {
      final row = {
        'bisa_rating': false,
        'tracking_status': 'SIAP_DIAMBIL',
        'nama_kasir': 'A',
      };
      expect(MemberRatingHelpers.isPendingToRate(row), isFalse);
    });

    test('filters pending vs history lists', () {
      final rows = [
        {
          'no_invoice': '1',
          'bisa_rating': true,
          'nama_kasir': 'A',
        },
        {
          'no_invoice': '2',
          'bisa_rating': true,
          'nama_kasir': 'A',
          'rating_kasir': {'skor': 5},
          'has_rating_kasir': true,
        },
        {
          'no_invoice': '3',
          'bisa_rating': false,
        },
      ];
      // #2: kasir sudah dinilai & pembuat belum assign → bukan pending (selesai utk peran terisi)
      expect(MemberRatingHelpers.pendingOnly(rows).map((e) => e['no_invoice']),
          ['1']);
      expect(MemberRatingHelpers.historyOnly(rows).map((e) => e['no_invoice']),
          ['2']);
      expect(MemberRatingHelpers.isComplete(rows[1]), isTrue);
    });
  });
}
