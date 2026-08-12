import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_shop_address.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemberShopAddress addr;

  MemberShopAddressEntry entry({
    String id = 'a1',
    String label = 'Rumah',
    String display = 'Jl. Asia Afrika, Bandung',
    double lat = -6.9175,
    double lng = 107.6191,
    ShopAddressKind kind = ShopAddressKind.custom,
    String detail = '',
  }) =>
      MemberShopAddressEntry(
        id: id,
        label: label,
        displayName: display,
        lat: lat,
        lng: lng,
        kind: kind,
        savedAt: DateTime(2026, 1, 1),
        detail: detail,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    addr = MemberShopAddress.instance;
    await addr.debugResetForTest();
  });

  test('shortFromDisplay takes first comma segment', () {
    expect(MemberShopAddress.shortFromDisplay(''), 'Alamat');
    expect(
      MemberShopAddress.shortFromDisplay('  Jl. Merdeka, Bandung, Jawa Barat '),
      'Jl. Merdeka',
    );
  });

  test('isValidForShipping requires display + coords', () {
    expect(
      MemberShopAddressEntry.isValidForShipping(
        entry(display: '', lat: -6.9, lng: 107.6),
      ),
      isFalse,
    );
    expect(
      MemberShopAddressEntry.isValidForShipping(
        entry(display: 'X', lat: 0, lng: 0),
      ),
      isFalse,
    );
    expect(
      MemberShopAddressEntry.isValidForShipping(entry()),
      isTrue,
    );
  });

  test('confirm sets active and recent; isConfirmed true', () async {
    await addr.syncOwner('m_user_a');
    await addr.confirm(entry());
    expect(addr.isConfirmed, isTrue);
    expect(addr.shortLabel, 'Rumah');
    expect(addr.recent, hasLength(1));
  });

  test('savePlace updates active when same place edited', () async {
    await addr.syncOwner('m_user_a');
    final base = entry(detail: 'Lama');
    await addr.confirm(base);
    await addr.savePlace(
      base.copyWith(
        kind: ShopAddressKind.home,
        label: 'Rumah Baru',
        detail: 'Unit 12',
      ),
    );
    expect(addr.active?.label, 'Rumah Baru');
    expect(addr.active?.detail, 'Unit 12');
    expect(addr.displayWithDetail, contains('Unit 12'));
    expect(addr.home?.label, 'Rumah Baru');
  });

  test('owner buckets do not leak across accounts', () async {
    await addr.syncOwner('m_user_a');
    await addr.confirm(entry(label: 'Milik A', display: 'Alamat A'));
    expect(addr.shortLabel, 'Milik A');

    await addr.syncOwner('m_user_b');
    expect(addr.isConfirmed, isFalse);
    expect(addr.recent, isEmpty);

    await addr.confirm(entry(label: 'Milik B', display: 'Alamat B', lat: -6.91));
    expect(addr.shortLabel, 'Milik B');

    await addr.syncOwner('m_user_a');
    expect(addr.shortLabel, 'Milik A');
  });

  test('logout to guest clears active selection', () async {
    await addr.syncOwner('m_user_a');
    await addr.confirm(entry());
    expect(addr.isConfirmed, isTrue);

    await addr.syncOwner('guest');
    expect(addr.isConfirmed, isFalse);
    expect(addr.saved, isEmpty);
  });

  test('guest selection copies into empty member bucket on login', () async {
    await addr.syncOwner('guest');
    await addr.confirm(entry(label: 'Guest Pick', display: 'Alamat Guest'));
    expect(addr.isConfirmed, isTrue);

    await addr.syncOwner('m_new');
    expect(addr.shortLabel, 'Guest Pick');
    // Guest bucket wiped after copy — re-enter guest is empty.
    await addr.syncOwner('guest');
    expect(addr.isConfirmed, isFalse);
  });

  test('confirm rejects invalid entry', () async {
    await addr.syncOwner('m_user_a');
    await addr.confirm(entry(display: '', lat: 0, lng: 0));
    expect(addr.isConfirmed, isFalse);
  });
}
