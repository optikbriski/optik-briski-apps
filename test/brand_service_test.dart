import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/brand/brand_service.dart';

void main() {
  tearDown(() {
    BrandService.bind(AppBrand.shellFallback);
  });

  test('bind locks storefront to Rekasa; Optik fallback is skin-only', () {
    BrandService.bind(AppBrand.fallback);
    expect(BrandService.name, 'Optik B. Riski');

    BrandService.bind(AppBrand.rekasaShell);
    expect(BrandService.name, 'Rekasa');
    expect(BrandService.shortName, 'RKS');
    expect(BrandService.assistantName, 'Asisten');
  });

  test('new branded slug does not inherit the Optik fallback', () {
    final warung = AppBrand.fallbackForSlug('warung-sari');
    expect(warung.displayName, 'warung-sari');
    expect(AppBrand.looksLikeOptikName(warung.displayName), isFalse);
    expect(AppBrand.fallbackForSlug('optik-briski').displayName, 'Optik B. Riski');
    expect(AppBrand.fallbackForSlug('').displayName, 'Rekasa');
  });

  test('guest hello is generic unless the running brand is Optik', () {
    BrandService.bind(AppBrand.rekasaShell);
    expect(BrandService.guestHelloFallback(), 'Hi!');
    BrandService.bind(AppBrand.fallbackForSlug('klinik-sari'));
    expect(BrandService.guestHelloFallback(), 'Hi!');
    BrandService.bind(AppBrand.fallback);
    expect(BrandService.guestHelloFallback(), 'Hi, Teman Optik!');
  });
}
