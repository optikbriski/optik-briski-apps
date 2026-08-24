import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/garansi/garansi_rules.dart';
import 'package:optik_b_riski/shared/garansi/garansi_service.dart';

void main() {
  group('GaransiRules', () {
    test('lunas JSON 150000.0 sisa is not treated as lunas', () {
      expect(
        GaransiRules.isSaleLunas({
          'status_pembayaran': 'lunas',
          'sisa_tagihan': '150000.0',
        }),
        isFalse,
      );
      expect(
        GaransiRules.isSaleLunas({
          'status_pembayaran': 'lunas',
          'sisa_tagihan': 0.0,
        }),
        isTrue,
      );
      expect(
        GaransiService.isSaleLunas({
          'status_pembayaran': 'lunas',
          'sisa_tagihan': '0.0',
        }),
        isTrue,
      );
    });

    test('PUSAT staff sees CABANG-PUSAT; cabang does not see other cabang', () {
      expect(
        GaransiRules.canViewAllStores(tokoId: 'PUSAT', role: 'admin_toko'),
        isTrue,
      );
      expect(
        GaransiRules.canViewAllStores(tokoId: 'CABANG-A', role: 'owner'),
        isTrue,
      );
      expect(
        GaransiRules.canViewAllStores(tokoId: 'CABANG-A', role: 'admin_toko'),
        isFalse,
      );
      expect(GaransiRules.sameStore('PUSAT', 'CABANG-PUSAT'), isTrue);
      expect(GaransiRules.storeAliases('PUSAT'), ['PUSAT', 'CABANG-PUSAT']);
    });

    test('empty toko on sale is rejected', () {
      expect(() => GaransiRules.requireTokoId(null), throwsStateError);
      expect(() => GaransiRules.requireTokoId('  '), throwsStateError);
      expect(GaransiRules.requireTokoId('CABANG-A'), 'CABANG-A');
    });

    test('jenis frame vs lensa from item', () {
      expect(GaransiService.jenisFromItem('frame', 'Rayban'), 'frame');
      expect(GaransiService.jenisFromItem('lensa', 'Bluechromic'), 'lensa');
      expect(GaransiService.jenisFromItem('', 'Lensa progresif'), 'lensa');
      expect(GaransiService.jenisFromItem('aksesoris', 'Cairan'), isNull);
    });
  });
}
