import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_cart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemberCart cart;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cart = MemberCart.instance;
    await cart.debugResetForTest();
  });

  Map<String, dynamic> product({
    required String sku,
    int harga = 100000,
    String nama = 'Frame A',
    String kategori = 'Frame',
    String? id,
    String imageUrl = '',
  }) =>
      {
        'sku': sku,
        'id': id ?? 'p-$sku',
        'nama': nama,
        'kategori': kategori,
        'harga': harga,
        'image_url': imageUrl,
      };

  test('isOnlineBlocked only for kategori lensa (aliases)', () {
    expect(MemberCart.isOnlineBlocked(product(sku: 'F1')), isFalse);
    expect(
      MemberCart.isOnlineBlocked(product(sku: 'F2', kategori: 'FRAME')),
      isFalse,
    );
    expect(
      MemberCart.isOnlineBlocked(product(sku: 'F3', kategori: ' Frame ')),
      isFalse,
    );
    expect(
      MemberCart.isOnlineBlocked(product(sku: 'L1', kategori: 'Lensa')),
      isTrue,
    );
    expect(
      MemberCart.isOnlineBlocked(product(sku: 'L2', kategori: 'lensa')),
      isTrue,
    );
    expect(
      MemberCart.isOnlineBlocked(product(sku: 'L3', kategori: 'LENSA')),
      isTrue,
    );
    expect(
      MemberCart.isOnlineBlocked(product(sku: 'L4', kategori: ' Lensa ')),
      isTrue,
    );
    expect(MemberCart.isOnlineBlockedKategori('Lainnya'), isFalse);
    expect(MemberCart.isOnlineBlockedKategori('Aksesoris'), isFalse);
    expect(MemberCart.isOnlineBlockedKategori(''), isFalse);
  });

  test('addProduct accepts Frame (not lensa-blocked)', () async {
    final err = await cart.addProduct(
      product(sku: 'FR-1', nama: 'Rayban', kategori: 'Frame', harga: 250000),
    );
    expect(err, isNull);
    expect(cart.items.single.sku, 'FR-1');
    expect(cart.items.single.kategori, 'Frame');
    expect(cart.subtotal, 250000);
  });

  test('addProduct accepts Lainnya / legacy accessory labels', () async {
    expect(
      await cart.addProduct(
        product(
          sku: 'ACC-1',
          nama: 'Hard Case',
          kategori: 'Lainnya',
          harga: 35000,
        ),
      ),
      isNull,
    );
    expect(
      await cart.addProduct(
        product(
          sku: 'ACC-2',
          nama: 'Cairan',
          kategori: 'Aksesoris',
          harga: 20000,
        ),
      ),
      isNull,
    );
    expect(cart.items.map((e) => e.sku), ['ACC-1', 'ACC-2']);
    expect(cart.subtotal, 55000);
  });

  test('addProduct selects new line; subtotal respects selection', () async {
    expect(await cart.addProduct(product(sku: 'A', harga: 1000)), isNull);
    expect(await cart.addProduct(product(sku: 'B', harga: 2000), qty: 2), isNull);

    expect(cart.totalQty, 3);
    expect(cart.subtotal, 5000);
    expect(cart.selectedSubtotal, 5000);
    expect(cart.allSelected, isTrue);

    cart.setSelected('A', false);
    expect(cart.hasSelection, isTrue);
    expect(cart.selectedSubtotal, 4000);
    expect(cart.toCheckoutItems().single['sku'], 'B');

    cart.setAllSelected(false);
    expect(cart.hasSelection, isFalse);
    expect(cart.selectedSubtotal, 0);
    expect(cart.toCheckoutItems(), isEmpty);
  });

  test('badge totalQty counts all lines even when none selected', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000), qty: 2);
    await cart.addProduct(product(sku: 'B', harga: 2000), qty: 3);
    cart.setAllSelected(false);
    expect(cart.hasSelection, isFalse);
    expect(cart.selectedSubtotal, 0);
    expect(cart.totalQty, 5); // badge shell = all lines
  });

  test('removeSelected keeps unchecked lines', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000));
    await cart.addProduct(product(sku: 'B', harga: 2000));
    cart.setSelected('B', false);

    await cart.removeSelected();

    expect(cart.items.map((e) => e.sku), ['B']);
    expect(cart.hasSelection, isFalse);
    expect(cart.selectedSubtotal, 0);
  });

  test('re-add same SKU refreshes harga from master', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000));
    expect(cart.items.single.harga, 1000);

    await cart.addProduct(product(sku: 'A', harga: 1500, nama: 'Frame A+'));
    expect(cart.items.single.qty, 2);
    expect(cart.items.single.harga, 1500);
    expect(cart.items.single.nama, 'Frame A+');
    expect(cart.selectedSubtotal, 3000);
  });

  test('blocked lensa and invalid harga rejected', () async {
    expect(
      await cart.addProduct(product(sku: 'L1', kategori: 'Lensa')),
      kMemberOnlineBlockedLensaMessage,
    );
    expect(
      await cart.addProduct(product(sku: 'L2', kategori: 'LENSA')),
      kMemberOnlineBlockedLensaMessage,
    );
    expect(
      await cart.addProduct(product(sku: 'Z', harga: 0)),
      isNotNull,
    );
    expect(cart.isEmpty, isTrue);
  });

  test('ensureLoaded purges sneaked-in lensa from prefs', () async {
    SharedPreferences.setMockInitialValues({
      'member_cart_v1': '''
[{"sku":"L1","product_id":"p-L1","nama":"Lensa A","kategori":"Lensa","harga":100000,"qty":1,"image_url":""},
 {"sku":"F1","product_id":"p-F1","nama":"Frame A","kategori":"Frame","harga":200000,"qty":1,"image_url":""}]
''',
    });
    await cart.debugResetForTest();
    // Re-seed after reset clears prefs.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'member_cart_v1',
      '[{"sku":"L1","product_id":"p-L1","nama":"Lensa A","kategori":"LENSA","harga":100000,"qty":1,"image_url":""},'
      '{"sku":"F1","product_id":"p-F1","nama":"Frame A","kategori":"Frame","harga":200000,"qty":1,"image_url":""}]',
    );

    await cart.ensureLoaded();
    expect(cart.items.map((e) => e.sku), ['F1']);
    expect(cart.hasOnlineBlockedSelection, isFalse);
    expect(cart.onlineBlockedSelectionError, isNull);
  });

  test('purgeOnlineBlocked clears lensa lines', () async {
    await cart.addProduct(product(sku: 'F1', harga: 1000));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'member_cart_v1',
      '[{"sku":"L9","product_id":"p-L9","nama":"Lensa","kategori":"lensa","harga":90000,"qty":2,"image_url":""},'
      '{"sku":"F1","product_id":"p-F1","nama":"Frame A","kategori":"Frame","harga":1000,"qty":1,"image_url":""}]',
    );
    await cart.debugResetForTest();
    await prefs.setString(
      'member_cart_v1',
      '[{"sku":"L9","product_id":"p-L9","nama":"Lensa","kategori":"lensa","harga":90000,"qty":2,"image_url":""},'
      '{"sku":"F1","product_id":"p-F1","nama":"Frame A","kategori":"Frame","harga":1000,"qty":1,"image_url":""}]',
    );
    await cart.ensureLoaded();
    // ensureLoaded already purged — purgeOnlineBlocked is no-op / 0.
    expect(cart.items.map((e) => e.sku), ['F1']);
    expect(await cart.purgeOnlineBlocked(), 0);
  });

  test('persist survives reload (guest / app restart)', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000), qty: 2);
    await cart.addProduct(product(sku: 'B', harga: 2500));
    cart.setSelected('A', false);

    // Simulate process death: in-memory selection resets; lines reload.
    await cart.debugResetForTest();
    final prefs = await SharedPreferences.getInstance();
    // debugReset clears prefs — re-seed as a real restart would keep them.
    // Instead: add again then soft-reset load flag via second cart load path.
    await cart.addProduct(product(sku: 'A', harga: 1000), qty: 2);
    await cart.addProduct(product(sku: 'B', harga: 2500));
    final raw = prefs.getString('member_cart_v1');
    expect(raw, isNotNull);

    await cart.debugResetForTest();
    await prefs.setString('member_cart_v1', raw!);
    await cart.ensureLoaded();

    expect(cart.items.length, 2);
    expect(cart.totalQty, 3);
    expect(cart.allSelected, isTrue); // selection not persisted
    expect(cart.selectedSubtotal, 1000 * 2 + 2500);
  });

  test('setQty clamps; qty 0 deletes; selection pruned', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000), qty: 2);
    await cart.setQty('A', 1);
    expect(cart.items.single.qty, 1);
    expect(cart.isSelected('A'), isTrue);

    await cart.setQty('A', 0);
    expect(cart.isEmpty, isTrue);
    expect(cart.hasSelection, isFalse);

    await cart.addProduct(product(sku: 'B', harga: 500), qty: 1);
    await cart.setQty('B', 500); // above max
    expect(cart.items.single.qty, kMemberCartMaxQtyPerLine);
  });

  test('addProduct refuses past max qty per line', () async {
    await cart.addProduct(
      product(sku: 'A', harga: 1000),
      qty: kMemberCartMaxQtyPerLine,
    );
    expect(cart.items.single.qty, kMemberCartMaxQtyPerLine);
    final err = await cart.addProduct(product(sku: 'A', harga: 1000));
    expect(err, contains('$kMemberCartMaxQtyPerLine'));
    expect(cart.items.single.qty, kMemberCartMaxQtyPerLine);
  });

  test('sanitize drops empty sku / zero harga / merges duplicate SKUs', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'member_cart_v1',
      '['
      '{"sku":"","product_id":"x","nama":"Bad","kategori":"Frame","harga":1000,"qty":1,"image_url":""},'
      '{"sku":"A","product_id":"p1","nama":"A1","kategori":"Frame","harga":0,"qty":1,"image_url":""},'
      '{"sku":"A","product_id":"p2","nama":"A2","kategori":"Frame","harga":1000,"qty":2,"image_url":""},'
      '{"sku":"a","product_id":"p3","nama":"A3","kategori":"Frame","harga":1200,"qty":3,"image_url":"img"},'
      '{"sku":"B","product_id":"pB","nama":"B","kategori":"Frame","harga":500,"qty":0,"image_url":""}'
      ']',
    );
    await cart.ensureLoaded();
    expect(cart.items.length, 1);
    expect(cart.items.single.sku.toUpperCase(), 'A');
    expect(cart.items.single.qty, 5); // 2+3 merged
    expect(cart.items.single.harga, 1200); // last wins
    expect(cart.items.single.nama, 'A3');
    expect(cart.items.single.imageUrl, 'img');
  });

  test('toCheckoutItems is selected-only and excludes lensa', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000));
    await cart.addProduct(product(sku: 'B', harga: 2000), qty: 2);
    cart.setSelected('A', false);
    final items = cart.toCheckoutItems();
    expect(items.length, 1);
    expect(items.single['sku'], 'B');
    expect(items.single['qty'], 2);
    expect(items.single.containsKey('image_url'), isFalse);
  });

  test('rapid adjustQty applies every delta (UI +/- path)', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000), qty: 1);
    await Future.wait([
      cart.adjustQty('A', 1),
      cart.adjustQty('A', 1),
      cart.adjustQty('A', 1),
    ]);
    expect(cart.items.single.qty, 4);

    await Future.wait([
      cart.adjustQty('A', -1),
      cart.adjustQty('A', -1),
    ]);
    expect(cart.items.single.qty, 2);
  });

  test('remove deletes line', () async {
    await cart.addProduct(product(sku: 'A', harga: 1000));
    await cart.addProduct(product(sku: 'B', harga: 2000));
    await cart.remove('A');
    expect(cart.items.map((e) => e.sku), ['B']);
    expect(cart.totalQty, 1);
  });
}
