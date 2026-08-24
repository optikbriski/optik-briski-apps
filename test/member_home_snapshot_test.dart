import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/brand/brand_service.dart';
import 'package:optik_b_riski/shared/member/member_home_models.dart';
import 'package:optik_b_riski/shared/member/member_home_rules.dart';

void main() {
  group('MemberHomeSnapshot', () {
    test('orderedSections falls back and hides invisible', () {
      final snap = MemberHomeSnapshot(
        content: {
          'sections': [
            {'key': 'hero', 'visible': true, 'order': 2},
            {'key': 'greeting', 'visible': false, 'order': 0},
            {'key': 'reminders', 'visible': true, 'order': 1},
          ],
        },
        points: 0,
        activeOrders: 0,
        garansiCount: 0,
        reminders: const [],
        totalReminders: 0,
        promos: const [],
        loadedAt: DateTime.now(),
        loggedIn: false,
      );

      final keys = snap.orderedSections().map((s) => s['key']).toList();
      expect(keys, ['reminders', 'hero']);
    });

    test('flag defaults true and respects false', () {
      final snap = MemberHomeSnapshot(
        content: {
          'feature_flags': {'katalog': false, 'rating': true},
        },
        points: 0,
        activeOrders: 0,
        garansiCount: 0,
        reminders: const [],
        totalReminders: 0,
        promos: const [],
        loadedAt: DateTime.now(),
        loggedIn: true,
      );

      expect(snap.flag('katalog'), isFalse);
      expect(snap.flag('rating'), isTrue);
      expect(snap.flag('resep'), isTrue);
    });

    test('heroSlides skips empty titles and falls back', () {
      final empty = MemberHomeSnapshot.emptyGuest(content: {
        'slides': [
          {'title': '', 'subtitle': 'x'},
        ],
      });
      expect(empty.heroSlides(), isNotEmpty);
      expect(empty.heroSlides().first['title'], isNotEmpty);

      final filled = MemberHomeSnapshot.emptyGuest(content: {
        'slides': [
          {
            'title': 'Promo lensa',
            'subtitle': 'Diskon',
            'image_url': 'https://example.com/a.jpg',
          },
        ],
      });
      expect(filled.heroSlides().length, 1);
      expect(filled.heroSlides().first['title'], 'Promo lensa');
    });

    test('reminder sortRank prioritizes unpaid then ready', () {
      const unpaid = MemberHomeReminder(
        kind: MemberHomeReminderKind.onlinePending,
        title: 'a',
        body: 'b',
        cta: 'c',
      );
      const ready = MemberHomeReminder(
        kind: MemberHomeReminderKind.ready,
        title: 'a',
        body: 'b',
        cta: 'c',
      );
      const processing = MemberHomeReminder(
        kind: MemberHomeReminderKind.processing,
        title: 'a',
        body: 'b',
        cta: 'c',
      );
      final list = [processing, ready, unpaid]..sort(
          (a, b) => a.sortRank.compareTo(b.sortRank),
        );
      expect(list.map((e) => e.kind).toList(), [
        MemberHomeReminderKind.onlinePending,
        MemberHomeReminderKind.ready,
        MemberHomeReminderKind.processing,
      ]);
    });

    test('empty CMS uses BrandService, not silent Optik', () {
      BrandService.bind(AppBrand.rekasaShell);
      final snap = MemberHomeSnapshot.emptyGuest();
      expect(snap.brandLabel(), 'Rekasa');
      expect(snap.greetingGuest(), 'Hi!');

      BrandService.bind(AppBrand.fallback);
      expect(MemberHomeSnapshot.emptyGuest().greetingGuest(), 'Hi, Teman Optik!');
      BrandService.bind(AppBrand.shellFallback);
    });

    test('promoDiscountLabel parses JSON money', () {
      expect(
        MemberHomeSnapshot.promoDiscountLabel({
          'discount_type': 'nominal',
          'discount_value': 150000.0,
        }),
        'Potongan Rp 150.000',
      );
      expect(
        MemberHomeSnapshot.promoDiscountLabel({
          'discount_type': 'nominal',
          'discount_value': '150.000',
        }),
        'Potongan Rp 150.000',
      );
      expect(
        MemberHomeSnapshot.promoDiscountLabel({
          'discount_type': 'percent',
          'discount_value': '10.0',
        }),
        'Diskon 10%',
      );
    });
  });

  group('MemberHomeRules', () {
    test('CABANG-PUSAT is Pusat on the home chip', () {
      expect(MemberHomeRules.storeChipLabel(null), 'Belum dipilih');
      expect(MemberHomeRules.storeChipLabel('PUSAT'), 'Pusat');
      expect(MemberHomeRules.storeChipLabel('CABANG-PUSAT'), 'Pusat');
      expect(MemberHomeRules.storeChipLabel('CABANG-A'), 'A');
    });

    test('banner path is tenant-prefixed', () {
      expect(
        MemberHomeRules.bannerObjectPath(
          tenantId: '00000000-0000-0000-0000-000000000001',
          fileName: 'Hero Foto.jpg',
          nowMs: 1,
        ),
        '00000000-0000-0000-0000-000000000001/banners/1_Hero_Foto.jpg',
      );
      expect(
        () => MemberHomeRules.bannerObjectPath(tenantId: '  ', fileName: 'a.jpg'),
        throwsStateError,
      );
    });

    test('promoStillAvailable keeps float qty and drops zero/expired', () {
      expect(
        MemberHomeRules.promoStillAvailable({'quantity_remaining': 7.0}),
        isTrue,
      );
      expect(
        MemberHomeRules.promoStillAvailable({'quantity_remaining': '0.0'}),
        isFalse,
      );
      expect(
        MemberHomeRules.promoStillAvailable({'quantity_remaining': null}),
        isTrue,
      );
      expect(
        MemberHomeRules.promoStillAvailable(
          {'valid_until': '2020-01-01'},
          now: DateTime(2026, 8, 24),
        ),
        isFalse,
      );
      expect(
        MemberHomeRules.promoStillAvailable(
          {'valid_until': '2026-08-24'},
          now: DateTime(2026, 8, 24),
        ),
        isTrue,
      );
    });

    test('optionalCount empty is unlimited, not zero', () {
      expect(MemberHomeRules.optionalCount(null), isNull);
      expect(MemberHomeRules.optionalCount(''), isNull);
      expect(MemberHomeRules.optionalCount('7.0'), 7);
      expect(MemberHomeRules.moneyOf('150000.0'), 150000);
    });

    test('promo form accepts JSON money that int.tryParse would reject', () {
      expect(MemberHomeRules.promoDiscountValueOk('info', ''), isTrue);
      expect(MemberHomeRules.promoDiscountValueOk('nominal', '150000.0'), isTrue);
      expect(MemberHomeRules.promoDiscountValueOk('nominal', '150.000'), isTrue);
      expect(MemberHomeRules.promoDiscountValueOk('percent', '10.0'), isTrue);
      expect(MemberHomeRules.promoDiscountValueOk('nominal', '0'), isFalse);
      expect(MemberHomeRules.promoDiscountValueOk('percent', ''), isFalse);
    });
  });
}
