import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_home_models.dart';

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
  });
}
