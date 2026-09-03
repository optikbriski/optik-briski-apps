import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/stock/etalase_layout.dart';

void main() {
  group('EtalaseUnit stacking', () {
    test('create with free per-layer widths', () {
      final u = EtalaseUnit.create(
        name: 'Depan',
        layerWidths: const [4, 3, 2],
      );
      expect(u.layerWidths, [4, 3, 2]);
      expect(u.boxes.length, 9);
      expect(u.boxAt(0, 3)?.code, 'A4');
      expect(u.boxAt(1, 2)?.code, 'B3');
      expect(u.boxAt(2, 1)?.code, 'C2');
      expect(u.boxAt(1, 3), isNull);
    });

    test('createUniform fills equal widths', () {
      final u = EtalaseUnit.createUniform(name: 'X', layers: 3, columns: 4);
      expect(u.layerWidths, [4, 4, 4]);
      expect(u.boxes.length, 12);
    });

    test('upper layer cannot exceed lower width', () {
      final u = EtalaseUnit.createUniform(name: 'X', layers: 3, columns: 4);
      expect(u.setLayerWidth(1, 5), isFalse);
      expect(u.setLayerWidth(2, 2), isTrue);
      expect(u.layerWidths, [4, 4, 2]);
      expect(u.setLayerWidth(1, 3), isTrue);
      expect(u.layerWidths, [4, 3, 2]);
      expect(u.setLayerWidth(0, 2), isFalse);
    });

    test('widthsValid enforces bottom >= above', () {
      expect(EtalaseUnit.widthsValid([4, 3, 2]), isTrue);
      expect(EtalaseUnit.widthsValid([4, 4, 4]), isTrue);
      expect(EtalaseUnit.widthsValid([3, 4]), isFalse);
      expect(EtalaseUnit.widthsValid([2, 2, 3]), isFalse);
    });

    test('sanitizeWidths clamps illegal upper layers', () {
      expect(EtalaseUnit.sanitizeWidths([3, 5, 9]), [3, 3, 3]);
      expect(EtalaseUnit.sanitizeWidths([0, -1]), [1, 1]);
      expect(EtalaseUnit.sanitizeWidths([]), [4]);
    });

    test('fromJson reconciles orphan boxes after width shrink', () {
      final json = {
        'id': 'e1',
        'name': 'Depan',
        'layerWidths': [2, 4], // illegal → sanitize to [2, 2]
        'align': 'center',
        'boxes': [
          {
            'layer': 0,
            'col': 0,
            'products': [
              {'productId': '1', 'sku': 'A', 'name': 'Frame', 'qty': 9},
            ],
          },
          {
            'layer': 1,
            'col': 3,
            'products': [
              {'productId': '2', 'sku': 'B', 'name': 'Lost', 'qty': 1},
            ],
          },
        ],
      };
      final u = EtalaseUnit.fromJson(json);
      expect(u.layerWidths, [2, 2]);
      expect(u.align, EtalaseAlign.center);
      expect(u.boxAt(0, 0)?.products.first.sku, 'A');
      expect(u.boxAt(1, 3), isNull);
      expect(u.boxes.length, 4);
    });

    test('toJson omits qty so master remains source of truth', () {
      final u = EtalaseUnit.create(name: 'X', layerWidths: const [1]);
      u.boxAt(0, 0)!.products.add(const EtalaseBoxProduct(
        productId: '1',
        sku: 'SKU',
        name: 'Frame',
        qty: 12,
      ));
      final encoded = u.toJson();
      final products = (encoded['boxes'] as List).first['products'] as List;
      expect((products.first as Map).containsKey('qty'), isFalse);
    });

    test('setLayerWidth keeps products and drops overflow cols', () {
      final u = EtalaseUnit.createUniform(name: 'X', layers: 2, columns: 3);
      u.boxAt(0, 2)!.products.add(const EtalaseBoxProduct(
        productId: '1',
        sku: 'SKU1',
        name: 'Frame A',
        qty: 3,
      ));
      expect(u.setLayerWidth(0, 2), isFalse);
      expect(u.setLayerWidth(1, 2), isTrue);
      expect(u.layerWidths, [3, 2]);
      expect(u.boxAt(0, 2)?.products.first.sku, 'SKU1');
      expect(u.boxAt(1, 2), isNull);
    });

    test('align offsets', () {
      final u = EtalaseUnit.create(name: 'X', layerWidths: const [4, 2]);
      u.align = EtalaseAlign.left;
      expect(u.colOffset(1), 0);
      u.align = EtalaseAlign.right;
      expect(u.colOffset(1), 2);
      u.align = EtalaseAlign.center;
      expect(u.colOffset(1), 1);
    });

    test('box name follows products, max 2', () {
      final b = EtalaseBox(layer: 0, col: 0);
      expect(b.displayName, 'A1');
      b.products.add(const EtalaseBoxProduct(
        productId: '1',
        sku: 'A',
        name: 'Aviator',
        qty: 2,
      ));
      expect(b.displayName, 'Aviator');
      expect(b.canAddProduct, isTrue);
      b.products.add(const EtalaseBoxProduct(
        productId: '2',
        sku: 'B',
        name: 'Crosslink',
        qty: 0,
      ));
      expect(b.displayName, 'Aviator · Crosslink');
      expect(b.canAddProduct, isFalse);
    });

    test('stock flags', () {
      expect(EtalaseStockRules.flagFor(0), EtalaseStockFlag.empty);
      expect(EtalaseStockRules.flagFor(5), EtalaseStockFlag.low);
      expect(EtalaseStockRules.flagFor(6), EtalaseStockFlag.ok);
      expect(EtalaseStockRules.flagFor(-1), EtalaseStockFlag.empty);
    });

    test('prefKey normalizes pusat aliases', () {
      expect(
        EtalaseLayoutStore.prefKey('cabang-pusat'),
        EtalaseLayoutStore.prefKey('PUSAT'),
      );
      expect(
        EtalaseLayoutStore.prefKey('CABANG-A'),
        'etalase_layout_v2_CABANG-A',
      );
    });

    test('syncFromMaster refreshes stock and drops missing SKUs', () {
      final u = EtalaseUnit.create(name: 'X', layerWidths: const [1]);
      u.boxAt(0, 0)!.products.addAll([
        const EtalaseBoxProduct(
          productId: '1',
          sku: 'KEEP',
          name: 'Old Name',
          qty: 99,
        ),
        const EtalaseBoxProduct(
          productId: 'gone',
          sku: 'GONE',
          name: 'Deleted',
          qty: 5,
        ),
      ]);
      final changed = EtalaseLayoutStore.syncFromMaster([u], [
        {'id': '1', 'sku': 'KEEP', 'nama': 'New Name', 'stock': 7},
      ]);
      expect(changed, isTrue);
      final box = u.boxAt(0, 0)!;
      expect(box.products.length, 1);
      expect(box.products.first.name, 'New Name');
      expect(box.products.first.qty, 7);

      final again = EtalaseLayoutStore.syncFromMaster([u], [
        {'id': '1', 'sku': 'KEEP', 'nama': 'New Name', 'stock': 3},
      ]);
      expect(again, isFalse);
      expect(box.products.first.qty, 3);
    });
    test('syncFromMaster ignores blank SKU collisions', () {
      final u = EtalaseUnit.create(name: 'X', layerWidths: const [1]);
      u.boxAt(0, 0)!.products.add(const EtalaseBoxProduct(
        productId: '1',
        sku: 'KEEP',
        name: 'Frame',
        qty: 1,
      ));
      final changed = EtalaseLayoutStore.syncFromMaster([u], [
        {'id': '1', 'sku': 'KEEP', 'nama': 'Frame', 'stock': 4},
        {'id': '2', 'sku': '', 'nama': 'NoSku', 'stock': 9},
        {'id': '3', 'sku': '  ', 'nama': 'Blank', 'stock': 8},
      ]);
      expect(changed, isFalse);
      expect(u.boxAt(0, 0)!.products.single.qty, 4);
    });
  });
}
