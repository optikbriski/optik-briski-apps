import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/brand/brand_slug_rules.dart';

void main() {
  test('kode usaha lower-case; Optik hanya slug resmi', () {
    expect(BrandSlugRules.normalize('OPTIK-BRISKI'), 'optik-briski');
    expect(BrandSlugRules.isOptikSlug('OPTIK-BRISKI'), isTrue);
    expect(BrandSlugRules.isOptikSlug('optik-maju'), isFalse);
    expect(BrandSlugRules.isOptikDisplayName('Optik B. Riski'), isTrue);
    expect(BrandSlugRules.isOptikDisplayName('Optik Baru'), isFalse);
  });

  test('saluran APK bersama = rekasa; merek sendiri = slug pin', () {
    expect(
      BrandSlugRules.releaseChannel(branded: false, brandedSlug: 'warung-sari'),
      'rekasa',
    );
    expect(
      BrandSlugRules.releaseChannel(
        branded: true,
        brandedSlug: 'optik-briski',
      ),
      'optik-briski',
    );
    expect(
      BrandSlugRules.releaseChannel(branded: true, brandedSlug: 'warung-sari'),
      'warung-sari',
    );
  });

  test('nama file APK: optik- warisan, rekasa, dan slug merek baru', () {
    final optik = BrandSlugRules.parseReleaseFilename(
      'app-releases/optik-karyawan-1.3.1.apk',
    );
    expect(optik?.slug, 'optik-briski');
    expect(optik?.flavor, 'karyawan');
    expect(optik?.versi, '1.3.1');

    final shared = BrandSlugRules.parseReleaseFilename('rekasa-admin-1.0.0.apk');
    expect(shared?.slug, 'rekasa');
    expect(shared?.flavor, 'admin');

    final brand = BrandSlugRules.parseReleaseFilename(
      'warung-sari-member-2.0.1.apk',
    );
    expect(brand?.slug, 'warung-sari');
    expect(brand?.flavor, 'member');
    expect(BrandSlugRules.parseReleaseFilename('random.apk'), isNull);
  });
}
