import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/config.dart';
import 'package:optik_b_riski/shared/widgets/login_brand_header.dart';

void main() {
  test('unpinned Rekasa shell does not use Optik logo on login', () {
    expect(isBrandedStoreApk, isFalse);
    expect(LoginBrandHeader.showOptikLogo, isFalse);
  });
}
