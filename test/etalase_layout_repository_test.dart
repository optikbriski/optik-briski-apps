import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/stock/etalase_layout.dart';
import 'package:optik_b_riski/shared/stock/etalase_layout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EtalaseLayoutRepository local', () {
    test('save then load roundtrip per toko, isolated', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = EtalaseLayoutRepository(tenantId: null);

      final a = EtalaseUnit.create(name: 'Depan A', layerWidths: const [3, 2]);
      a.boxAt(0, 0)!.products.add(const EtalaseBoxProduct(
        productId: 'p1',
        sku: 'SKU1',
        name: 'Frame',
        qty: 11,
      ));
      await repo.save('CABANG-A', [a]);

      final b = EtalaseUnit.create(name: 'Depan B', layerWidths: const [2]);
      await repo.save('CABANG-B', [b]);

      final loadedA = await repo.load('cabang-a');
      expect(loadedA.length, 1);
      expect(loadedA.first.name, 'Depan A');
      expect(loadedA.first.layerWidths, [3, 2]);
      expect(loadedA.first.boxAt(0, 0)?.products.first.sku, 'SKU1');
      // qty tidak di persist
      expect(loadedA.first.boxAt(0, 0)?.products.first.qty, 0);

      final loadedB = await repo.load('CABANG-B');
      expect(loadedB.length, 1);
      expect(loadedB.first.name, 'Depan B');
      expect(loadedB.first.boxes.length, 2);

      final pusat1 = await repo.load('CABANG-PUSAT');
      expect(pusat1, isEmpty);
      await repo.save('PUSAT', [
        EtalaseUnit.create(name: 'Pusat', layerWidths: const [1]),
      ]);
      final pusat2 = await repo.load('cabang-pusat');
      expect(pusat2.single.name, 'Pusat');
    });

    test('local newer timestamp survives reload without remote', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = EtalaseLayoutRepository(tenantId: null);
      await repo.save('CABANG-X', [
        EtalaseUnit.create(name: 'Lokal', layerWidths: const [2]),
      ]);
      final again = await repo.load('CABANG-X');
      expect(again.single.name, 'Lokal');
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString('etalase_layout_v2_CABANG-X_updated_at');
      expect(ts, isNotNull);
      expect(DateTime.tryParse(ts!), isNotNull);
    });
  });
}
