import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/brand/brand_service.dart';
import 'package:optik_b_riski/shared/config.dart';
import 'package:optik_b_riski/shared/widgets/login_brand_header.dart';

void main() {
  test('unpinned Rekasa shell does not use Optik logo on login', () {
    expect(isBrandedStoreApk, isFalse);
    expect(LoginBrandHeader.showOptikLogo, isFalse);
    expect(LoginBrandHeader.tenantHeadline, isNull);
  });

  test('Rekasa fallback name is never used as a tenant headline', () {
    expect(BrandService.name.toUpperCase(), contains('REKASA'));
    expect(LoginBrandHeader.nameLooksLikeRekasa, isTrue);
    expect(LoginBrandHeader.tenantHeadline, isNull);
  });
}
