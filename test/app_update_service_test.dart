import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/app_update_service.dart';
import 'package:optik_b_riski/shared/brand/brand_slug_rules.dart';

void main() {
  const host = 'ualqiiprtjysdmtqkpzr.supabase.co';

  String apk(String name) =>
      'https://$host/storage/v1/object/public/app-releases/$name';

  test('compareSemver: patch dan build number', () {
    expect(AppUpdateService.compareSemver('1.3.2', '1.3.1'), greaterThan(0));
    expect(AppUpdateService.compareSemver('1.3.1', '1.3.2'), lessThan(0));
    expect(AppUpdateService.compareSemver('1.3.1', '1.3.1'), 0);
    expect(AppUpdateService.compareSemver('1.3.1+18', '1.3.1+17'), greaterThan(0));
    expect(AppUpdateService.compareSemver('1.3.1+17', '1.3.1+18'), lessThan(0));
    expect(AppUpdateService.compareSemver('1.3.2', '1.3.1+99'), greaterThan(0));
  });

  test('URL rilis: host + flavor + saluran harus cocok', () {
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        apk('optik-karyawan-1.3.1.apk'),
        flavor: 'karyawan',
        channel: 'optik-briski',
        supabaseHost: host,
      ),
      isTrue,
    );
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        apk('rekasa-admin-1.3.1.apk'),
        flavor: 'admin',
        channel: 'rekasa',
        supabaseHost: host,
      ),
      isTrue,
    );
    // Flavor beda — Admin tidak boleh unduh Karyawan.
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        apk('optik-karyawan-1.3.1.apk'),
        flavor: 'admin',
        channel: 'optik-briski',
        supabaseHost: host,
      ),
      isFalse,
    );
    // Saluran beda — Rekasa tidak boleh unduh Optik.
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        apk('optik-karyawan-1.3.1.apk'),
        flavor: 'karyawan',
        channel: 'rekasa',
        supabaseHost: host,
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        'http://$host/storage/v1/object/public/app-releases/optik-karyawan-1.3.1.apk',
        flavor: 'karyawan',
        channel: 'optik-briski',
        supabaseHost: host,
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        'https://evil.example/storage/v1/object/public/app-releases/optik-karyawan-1.3.1.apk',
        flavor: 'karyawan',
        channel: 'optik-briski',
        supabaseHost: host,
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        apk('note.html'),
        flavor: 'karyawan',
        channel: 'optik-briski',
        supabaseHost: host,
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        '${apk('optik-karyawan-1.3.1.apk')}?next=https://evil.example',
        flavor: 'karyawan',
        channel: 'optik-briski',
        supabaseHost: host,
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        apk('optik-karyawan-1.3.1.apk'),
        flavor: 'karyawan',
        channel: 'optik-briski',
        supabaseHost: host,
        expectedVersion: '1.3.2',
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedReleaseUrl(
        apk('optik-karyawan-1.3.1.apk'),
        flavor: 'karyawan',
        channel: 'optik-briski',
        supabaseHost: host,
        expectedVersion: '1.3.1+18',
      ),
      isTrue,
    );
  });

  test('HTTP 200/206 dianggap OK; 404 bukan', () {
    expect(AppUpdateService.isHttpOk(200), isTrue);
    expect(AppUpdateService.isHttpOk(206), isTrue);
    expect(AppUpdateService.isHttpOk(404), isFalse);
    expect(AppUpdateService.isHttpOk(null), isFalse);
  });

  test('flavor dinormalisasi ke saluran yang dikenal', () {
    expect(AppUpdateFlavor.normalize('ADMIN'), AppUpdateFlavor.admin);
    expect(AppUpdateFlavor.normalize('member'), AppUpdateFlavor.member);
  });

  test('nama file rilis: slug + flavor; owner ditolak', () {
    final ok = BrandSlugRules.parseReleaseFilename('optik-karyawan-1.3.1.apk');
    expect(ok?.slug, 'optik-briski');
    expect(ok?.flavor, 'karyawan');
    expect(ok?.versi, '1.3.1');
    expect(
      BrandSlugRules.parseReleaseFilename('rekasa-admin-1.3.1.apk')?.flavor,
      'admin',
    );
    expect(BrandSlugRules.parseReleaseFilename('evil-owner-1.0.0.apk'), isNull);
    expect(BrandSlugRules.parseReleaseFilename('optik-karyawan-1.3.1.apk.exe'), isNull);
  });
}
