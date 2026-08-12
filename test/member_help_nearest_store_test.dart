import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_help_nearest_store.dart';

void main() {
  group('memberHelpHasValidStorePhone', () {
    test('rejects empty / placeholder', () {
      expect(memberHelpHasValidStorePhone(null), isFalse);
      expect(memberHelpHasValidStorePhone(''), isFalse);
      expect(memberHelpHasValidStorePhone('-'), isFalse);
      expect(memberHelpHasValidStorePhone('123'), isFalse);
    });

    test('accepts normal ID phones', () {
      expect(memberHelpHasValidStorePhone('081234567890'), isTrue);
      expect(memberHelpHasValidStorePhone('+62 812-8880-1697'), isTrue);
    });
  });

  group('pickNearestStoreWithPhone', () {
    final stores = <Map<String, dynamic>>[
      {
        'toko_id': 'CABANG-A',
        'shop_name': 'Far',
        'phone': '081111111111',
        'latitude': -6.3,
        'longitude': 106.9,
      },
      {
        'toko_id': 'CABANG-B',
        'shop_name': 'Near',
        'phone': '082222222222',
        'latitude': -6.2001,
        'longitude': 106.8167,
      },
      {
        'toko_id': 'CABANG-C',
        'shop_name': 'Closer but no phone',
        'phone': '-',
        'latitude': -6.20005,
        'longitude': 106.8166,
      },
      {
        'toko_id': 'CABANG-D',
        'shop_name': 'No coords',
        'phone': '083333333333',
      },
    ];

    test('picks nearest with valid phone (skips closer no-phone)', () {
      // User near Jakarta (-6.2, 106.8166)
      final picked = pickNearestStoreWithPhone(
        userLat: -6.2,
        userLng: 106.8166,
        stores: stores,
      );
      expect(picked, isNotNull);
      expect(picked!['toko_id'], 'CABANG-B');
    });

    test('returns null when no store has geo+phone', () {
      final picked = pickNearestStoreWithPhone(
        userLat: -6.2,
        userLng: 106.8,
        stores: const [
          {'toko_id': 'X', 'phone': '-', 'latitude': -6.2, 'longitude': 106.8},
          {'toko_id': 'Y', 'phone': '081234567890'},
        ],
      );
      expect(picked, isNull);
    });

    test('haversine ranks nearer store first', () {
      final dNear =
          memberHelpHaversineMeters(-6.2, 106.8166, -6.2001, 106.8167);
      final dFar = memberHelpHaversineMeters(-6.2, 106.8166, -6.3, 106.9);
      expect(dNear, lessThan(dFar));
      expect(dNear, lessThan(200));
    });
  });

  group('matchStoresByStatedLocation', () {
    final stores = <Map<String, dynamic>>[
      {
        'toko_id': 'CABANG-CIKARANG',
        'shop_name': 'Optik B. Riski Cikarang',
        'address': 'Jl. Raya Industri Cikarang, Bekasi',
        'phone': '081111111111',
      },
      {
        'toko_id': 'CABANG-KARAWANG',
        'shop_name': 'Optik B. Riski Karawang',
        'address': 'Jl. Ahmad Yani Karawang',
        'phone': '082222222222',
      },
      {
        'toko_id': 'CABANG-BEKASI',
        'shop_name': 'Optik B. Riski Bekasi Kota',
        'address': 'Bekasi Timur',
        'phone': '083333333333',
        'kota': 'Bekasi',
      },
      {
        'toko_id': 'PUSAT',
        'shop_name': 'Optik B. Riski Pusat',
        'address': 'Jakarta',
        'phone': '-',
      },
    ];

    test('matches city token in address / name', () {
      final matches = matchStoresByStatedLocation('Cikarang', stores);
      expect(matches, isNotEmpty);
      expect(matches.first.tokoId, 'CABANG-CIKARANG');
      expect(matches.first.score, greaterThan(0));
    });

    test('matches kota field', () {
      final matches = matchStoresByStatedLocation('bekasi', stores);
      expect(matches.map((m) => m.tokoId), contains('CABANG-BEKASI'));
      // Cikarang address also mentions Bekasi — both may match; Bekasi should rank high.
      expect(matches.first.score, greaterThan(0));
    });

    test('skips stores without valid phone when requirePhone', () {
      final matches = matchStoresByStatedLocation('Jakarta', stores);
      expect(matches.every((m) => m.tokoId != 'PUSAT'), isTrue);
    });

    test('pickBest auto-selects dominant single area', () {
      final matches = matchStoresByStatedLocation('Karawang', stores);
      final best = pickBestStatedLocationMatch(matches);
      expect(best, isNotNull);
      expect(best!.tokoId, 'CABANG-KARAWANG');
    });

    test('ambiguous close scores → null best (UI chips)', () {
      final ambiguous = <Map<String, dynamic>>[
        {
          'toko_id': 'A',
          'shop_name': 'Store Alpha Bekasi',
          'address': 'Bekasi',
          'phone': '081111111111',
        },
        {
          'toko_id': 'B',
          'shop_name': 'Store Beta Bekasi',
          'address': 'Bekasi',
          'phone': '082222222222',
        },
      ];
      final matches = matchStoresByStatedLocation('Bekasi', ambiguous);
      expect(matches.length, greaterThanOrEqualTo(2));
      // Similar scores → do not auto-pick.
      expect(pickBestStatedLocationMatch(matches), isNull);
    });

    test('empty / nonsense query → no matches', () {
      expect(matchStoresByStatedLocation('', stores), isEmpty);
      expect(matchStoresByStatedLocation('zzzznotacity', stores), isEmpty);
    });

    test('topStoresWithPhone skips invalid phones', () {
      final top = topStoresWithPhone(stores, limit: 10);
      expect(top.map((s) => s['toko_id']), isNot(contains('PUSAT')));
      expect(top.length, 3);
    });

    test('scoreStoreStatedLocationMatch ranks exact toko_id highest', () {
      final s = stores.first;
      final byId = scoreStoreStatedLocationMatch('CABANG-CIKARANG', s);
      final byCity = scoreStoreStatedLocationMatch('Cikarang', s);
      expect(byId, greaterThan(byCity));
    });
  });

  group('memberHelpExtractAreaQuery / XOR escalate CTA', () {
    test('strips bare WA requests to empty (GPS/ask path)', () {
      expect(memberHelpExtractAreaQuery('bagi wa dong'), isEmpty);
      expect(memberHelpExtractAreaQuery('bagi nomor wa'), isEmpty);
      expect(memberHelpExtractAreaQuery('minta nomor whatsapp'), isEmpty);
      expect(memberHelpHasExplicitAreaHint('bagi wa dong'), isFalse);
    });

    test('keeps named city/cabang from WA request', () {
      expect(
        memberHelpExtractAreaQuery('bagi wa cabang banyuwangi'),
        'banyuwangi',
      );
      expect(memberHelpExtractAreaQuery('wa cikarang'), 'cikarang');
      expect(
        memberHelpExtractAreaQuery('minta nomor wa karawang selatan'),
        'karawang selatan',
      );
      expect(memberHelpHasExplicitAreaHint('bagi wa banyuwangi'), isTrue);
    });

    test('explicit area match uses extracted query against directory', () {
      final stores = <Map<String, dynamic>>[
        {
          'toko_id': 'CABANG-BANYUWANGI',
          'shop_name': 'Optik B. Riski Banyuwangi',
          'address': 'Jl. Raya Banyuwangi',
          'phone': '081111111111',
        },
        {
          'toko_id': 'CABANG-BANDUNG',
          'shop_name': 'Optik B. Riski Bandung',
          'address': 'Bandung',
          'phone': '082222222222',
        },
      ];
      final area = memberHelpExtractAreaQuery('bagi wa cabang banyuwangi');
      final matches = matchStoresByStatedLocation(area, stores);
      final best = pickBestStatedLocationMatch(matches);
      expect(best, isNotNull);
      expect(best!.tokoId, 'CABANG-BANYUWANGI');
    });

    test('XOR: auto-resolving contact WA hides escalate CTA', () {
      expect(
        memberHelpShouldShowWaEscalateCta(
          escalateWaFlag: true,
          autoResolvingContactWa: true,
        ),
        isFalse,
      );
      expect(
        memberHelpShouldShowWaEscalateCta(
          escalateWaFlag: true,
          autoResolvingContactWa: false,
        ),
        isTrue,
      );
      expect(
        memberHelpShouldShowWaEscalateCta(
          escalateWaFlag: false,
          autoResolvingContactWa: false,
        ),
        isFalse,
      );
    });
  });

  group('findStoreByTokoId / pickSelectedStoreWithPhone', () {
    final stores = <Map<String, dynamic>>[
      {
        'toko_id': 'DEPOK',
        'shop_name': 'Optik Depok',
        'phone': '081234567890',
      },
      {
        'toko_id': 'BEKASI',
        'shop_name': 'Optik Bekasi',
        'phone': '-',
      },
    ];

    test('findStoreByTokoId is case-insensitive', () {
      final s = findStoreByTokoId('depok', stores);
      expect(s, isNotNull);
      expect(s!['toko_id'], 'DEPOK');
      expect(findStoreByTokoId('', stores), isNull);
      expect(findStoreByTokoId('XYZ', stores), isNull);
    });

    test('pickSelectedStoreWithPhone requires dialable phone', () {
      expect(
        pickSelectedStoreWithPhone(selectedTokoId: 'DEPOK', stores: stores),
        isNotNull,
      );
      expect(
        pickSelectedStoreWithPhone(selectedTokoId: 'BEKASI', stores: stores),
        isNull,
      );
      expect(
        pickSelectedStoreWithPhone(selectedTokoId: null, stores: stores),
        isNull,
      );
    });
  });

  group('resolveMemberHelpSessionStore / named toko guard', () {
    final stores = <Map<String, dynamic>>[
      {
        'toko_id': 'CABANG-SINGAPARNA',
        'shop_name': 'Optik B. Riski Singaparna',
        'address': 'Jl. Raya yang menuju pasar Singaparna',
        'phone': '081111111111',
      },
      {
        'toko_id': 'CABANG-WONOSOBO',
        'shop_name': 'Optik B. Riski Wonosobo',
        'address': 'Jl. Ahmad Yani Wonosobo',
        'phone': '082222222222',
      },
    ];

    test('stock keywords do not override selected toko', () {
      final focus = resolveMemberHelpSessionStore(
        stores: stores,
        selectedTokoId: 'CABANG-WONOSOBO',
        message: 'stock apa yang ready?',
      );
      expect(focus, isNotNull);
      expect(focus!['toko_id'], 'CABANG-WONOSOBO');
    });

    test('frame/ready filler keeps selected toko', () {
      final focus = resolveMemberHelpSessionStore(
        stores: stores,
        selectedTokoId: 'CABANG-WONOSOBO',
        message: 'frame yang ready apa?',
      );
      expect(focus!['toko_id'], 'CABANG-WONOSOBO');
    });

    test('explicit named cabang still overrides selection', () {
      final focus = resolveMemberHelpSessionStore(
        stores: stores,
        selectedTokoId: 'CABANG-WONOSOBO',
        message: 'stok di Singaparna',
      );
      expect(focus, isNotNull);
      expect(focus!['toko_id'], 'CABANG-SINGAPARNA');
    });

    test('selected toko never falls back to first directory row', () {
      final focus = resolveMemberHelpSessionStore(
        stores: stores,
        selectedTokoId: 'CABANG-WONOSOBO',
        message: 'cek stok',
      );
      expect(focus!['toko_id'], 'CABANG-WONOSOBO');
      expect(focus['toko_id'], isNot('CABANG-SINGAPARNA'));
    });

    test('extractNamedTokoQuery strips stock filler to empty', () {
      expect(memberHelpExtractNamedTokoQuery('stock apa yang ready?'), isEmpty);
      expect(memberHelpExtractNamedTokoQuery('frame yang ready apa?'), isEmpty);
      expect(
        memberHelpExtractNamedTokoQuery('stok di Singaparna'),
        'singaparna',
      );
    });
  });
}
