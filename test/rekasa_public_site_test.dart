import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/brand/rekasa_public_host.dart';
import 'package:optik_b_riski/shared/invoice/invoice_link.dart';
import 'package:optik_b_riski/shared/tenant/tenant_billing.dart';

void main() {
  test('situs publik Rekasa siap kolom link Midtrans', () {
    final html = File('site/index.html').readAsStringSync();
    expect(html, contains('REKASA KARYA INDONESIA'));
    expect(html, contains('rekasakaryaindonesia@gmail.com'));
    expect(html, isNot(contains('optikbriski.apps@gmail.com')));
    expect(html, contains('Perseroan Perorangan'));
    expect(html, contains('AHU-A011645.AH.01.31.Tahun 2026'));
    expect(html, contains('id="plan-cards"'));
    expect(html, contains('id="checkout-holder"'));
    expect(html, contains('Bayar via Midtrans'));
    expect(html, contains('perangkat lunak'));
    expect(html, isNot(contains('PT Biasa')));
    expect(html, isNot(contains('/admin/')));
    expect(html, isNot(contains('Konsol')));
    expect(File('site/syarat.html').existsSync(), isTrue);
    expect(File('site/kebijakan.html').existsSync(), isTrue);
    expect(File('site/kontak.html').existsSync(), isTrue);
    expect(File('site/sw-kill.js').existsSync(), isTrue);
    expect(File('site/store.js').existsSync(), isTrue);
    expect(File('site/catalog.js').readAsStringSync(), contains('Paket C'));
    expect(
      File('supabase/functions/rekasa-midtrans-create/index.ts').existsSync(),
      isTrue,
    );
  });

  test('host Rekasa diarahkan ke /perusahaan, bukan login Admin', () {
    expect(isRekasaPublicHost('rekasa-karya-indonesia.vercel.app'), isTrue);
    expect(shouldRedirectRekasaPublicPath('/'), isTrue);
    expect(shouldRedirectRekasaPublicPath(null), isTrue);
    expect(shouldRedirectRekasaPublicPath('/perusahaan/'), isFalse);
    expect(isRekasaPublicHost('optik-briski-apps.vercel.app'), isFalse);

    final boot = File('web/index.html').readAsStringSync();
    expect(boot, contains("location.replace('/perusahaan/'"));
    expect(boot, contains('rekasa-karya-indonesia.vercel.app'));
  });

  test('Vercel keeps Admin at / so invoice and contract links still resolve', () {
    final vercel = File('vercel.json').readAsStringSync();
    expect(vercel, contains('"/perusahaan"'));
    expect(vercel, contains('"/(.*)"'));
    expect(vercel, contains('"/index.html"'));
    expect(vercel, contains('rekasa-karya-indonesia.vercel.app'));
    expect(vercel, contains('"redirects"'));
    expect(vercel, contains('/perusahaan/sw-kill.js'));
    expect(vercel, isNot(contains('/admin/index.html')));

    final build = File('scripts/vercel_build.sh').readAsStringSync();
    expect(build, contains('build/web/perusahaan'));
    expect(build, contains('-t lib/main_admin.dart'));
    expect(build, isNot(contains('--base-href /admin/')));

    expect(
      InvoiceLink.httpsBase,
      'https://optik-briski-apps.vercel.app/i',
    );
    expect(
      TenantBilling.publicSignUrl('tokentest', origin: 'https://optik-briski-apps.vercel.app'),
      'https://optik-briski-apps.vercel.app/?kontrak=tokentest',
    );
  });
}
