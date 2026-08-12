import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_catalog_kategori.dart';

void main() {
  group('canonicalizeMemberCatalogKategori', () {
    test('maps aliases and clears Semua', () {
      expect(canonicalizeMemberCatalogKategori('Frame'), 'Frame');
      expect(canonicalizeMemberCatalogKategori('FRAME'), 'Frame');
      expect(canonicalizeMemberCatalogKategori(' frame '), 'Frame');
      expect(canonicalizeMemberCatalogKategori('lensa'), 'Lensa');
      expect(canonicalizeMemberCatalogKategori('Lainnya'), 'Lainnya');
      expect(canonicalizeMemberCatalogKategori('LAINNYA'), 'Lainnya');
      expect(canonicalizeMemberCatalogKategori(' lainnya '), 'Lainnya');
      expect(canonicalizeMemberCatalogKategori('Semua'), isNull);
      expect(canonicalizeMemberCatalogKategori(''), isNull);
      expect(canonicalizeMemberCatalogKategori(null), isNull);
      expect(canonicalizeMemberCatalogKategori('Aksesoris'), isNull);
    });
  });

  group('memberCatalogIsLainnya', () {
    test('bucket = non-empty and not Frame/Lensa', () {
      expect(memberCatalogIsLainnya('Lainnya'), isTrue);
      expect(memberCatalogIsLainnya('Aksesoris'), isTrue);
      expect(memberCatalogIsLainnya(' softlens '), isTrue);
      expect(memberCatalogIsLainnya('Frame'), isFalse);
      expect(memberCatalogIsLainnya('FRAME'), isFalse);
      expect(memberCatalogIsLainnya('Lensa'), isFalse);
      expect(memberCatalogIsLainnya(' lensa '), isFalse);
      expect(memberCatalogIsLainnya(''), isFalse);
      expect(memberCatalogIsLainnya('  '), isFalse);
      expect(memberCatalogIsLainnya(null), isFalse);
    });
  });

  group('memberCatalogMatchesKategori', () {
    test('Frame filter is case/trim robust', () {
      expect(memberCatalogMatchesKategori('Frame', 'Frame'), isTrue);
      expect(memberCatalogMatchesKategori('FRAME', 'frame'), isTrue);
      expect(memberCatalogMatchesKategori(' Frame ', 'FRAME'), isTrue);
      expect(memberCatalogMatchesKategori('Lensa', 'Frame'), isFalse);
      expect(memberCatalogMatchesKategori('Lainnya', 'Frame'), isFalse);
    });

    test('Lensa filter is case/trim robust and excludes Frame', () {
      expect(memberCatalogMatchesKategori('Lensa', 'Lensa'), isTrue);
      expect(memberCatalogMatchesKategori('LENSA', 'lensa'), isTrue);
      expect(memberCatalogMatchesKategori(' lensa ', 'LENSA'), isTrue);
      expect(memberCatalogMatchesKategori('Frame', 'Lensa'), isFalse);
      expect(memberCatalogMatchesKategori('Lainnya', 'Lensa'), isFalse);
      expect(memberCatalogMatchesKategori('Aksesoris', 'Lensa'), isFalse);
    });

    test('Lainnya excludes Frame/Lensa and empty', () {
      expect(memberCatalogMatchesKategori('Lainnya', 'Lainnya'), isTrue);
      expect(memberCatalogMatchesKategori('Aksesoris', 'lainnya'), isTrue);
      expect(memberCatalogMatchesKategori(' Soft Case ', 'LAINNYA'), isTrue);
      expect(memberCatalogMatchesKategori('Frame', 'Lainnya'), isFalse);
      expect(memberCatalogMatchesKategori('LENSA', 'Lainnya'), isFalse);
      expect(memberCatalogMatchesKategori('', 'Lainnya'), isFalse);
      expect(memberCatalogMatchesKategori('  ', 'Lainnya'), isFalse);
    });

    test('null/Semua matches all', () {
      expect(memberCatalogMatchesKategori('Frame', null), isTrue);
      expect(memberCatalogMatchesKategori('Lensa', 'Semua'), isTrue);
      expect(memberCatalogMatchesKategori('', null), isTrue);
    });
  });

  group('memberCatalogServerKategoriParam', () {
    test('Frame/Lensa/Lainnya go to RPC; Semua does not', () {
      expect(memberCatalogServerKategoriParam('Frame'), 'Frame');
      expect(memberCatalogServerKategoriParam('FRAME'), 'Frame');
      expect(memberCatalogServerKategoriParam('lensa'), 'Lensa');
      expect(memberCatalogServerKategoriParam('Lainnya'), 'Lainnya');
      expect(memberCatalogServerKategoriParam('LAINNYA'), 'Lainnya');
      expect(memberCatalogServerKategoriParam(' lainnya '), 'Lainnya');
      expect(memberCatalogServerKategoriParam('Semua'), isNull);
      expect(memberCatalogServerKategoriParam(null), isNull);
      expect(memberCatalogServerKategoriParam('Aksesoris'), isNull);
    });
  });
}
