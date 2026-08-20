import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/brand/brand_chrome.dart';
import 'package:optik_b_riski/shared/config.dart';

void main() {
  tearDown(() {
    BrandChrome.roleSuffix = '';
  });

  test('windowTitle uses role suffix when set', () {
    BrandChrome.roleSuffix = 'Admin';
    expect(BrandChrome.windowTitle.contains('Admin'), isTrue);
    expect(BrandChrome.windowTitle.contains('—'), isTrue);
  });

  test('roleForFlavor matches product shells', () {
    expect(BrandChrome.roleForFlavor(AppFlavor.admin), 'Admin');
    expect(BrandChrome.roleForFlavor(AppFlavor.member), 'Member');
    expect(BrandChrome.roleForFlavor(AppFlavor.karyawan), 'Karyawan');
  });
}
