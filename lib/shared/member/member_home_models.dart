import 'package:flutter/material.dart';

import '../theme.dart';

enum MemberHomeReminderKind {
  ready,
  booking,
  dp,
  processing,
  onlinePending,
  rating,
}

/// Reminder actionable di Beranda (data saja — navigasi di UI).
class MemberHomeReminder {
  const MemberHomeReminder({
    required this.kind,
    required this.title,
    required this.body,
    required this.cta,
    this.noInvoice,
    this.onlineOrderId,
  });

  final MemberHomeReminderKind kind;
  final String title;
  final String body;
  final String cta;
  final String? noInvoice;
  final String? onlineOrderId;

  Color get accent {
    switch (kind) {
      case MemberHomeReminderKind.ready:
        return OptikMemberTokens.success;
      case MemberHomeReminderKind.booking:
        return OptikMemberTokens.blueDeep;
      case MemberHomeReminderKind.dp:
      case MemberHomeReminderKind.onlinePending:
        return OptikMemberTokens.warning;
      case MemberHomeReminderKind.processing:
        return OptikMemberTokens.blue;
      case MemberHomeReminderKind.rating:
        return const Color(0xFFD97706);
    }
  }

  int get sortRank {
    switch (kind) {
      case MemberHomeReminderKind.onlinePending:
        return 0;
      case MemberHomeReminderKind.ready:
        return 1;
      case MemberHomeReminderKind.rating:
        return 2;
      case MemberHomeReminderKind.booking:
        return 3;
      case MemberHomeReminderKind.dp:
        return 4;
      case MemberHomeReminderKind.processing:
        return 5;
    }
  }
}

/// Snapshot lengkap Beranda Member (CMS + data live).
class MemberHomeSnapshot {
  const MemberHomeSnapshot({
    required this.content,
    required this.points,
    required this.activeOrders,
    required this.garansiCount,
    required this.reminders,
    required this.totalReminders,
    required this.promos,
    this.highlightToko,
    this.error,
    required this.loadedAt,
    required this.loggedIn,
  });

  final Map<String, dynamic>? content;
  final int points;
  final int activeOrders;
  final int garansiCount;
  final List<MemberHomeReminder> reminders;
  final int totalReminders;
  final List<Map<String, dynamic>> promos;
  final String? highlightToko;
  final String? error;
  final DateTime loadedAt;
  final bool loggedIn;

  static MemberHomeSnapshot emptyGuest({
    Map<String, dynamic>? content,
    String? error,
  }) {
    return MemberHomeSnapshot(
      content: content,
      points: 0,
      activeOrders: 0,
      garansiCount: 0,
      reminders: const [],
      totalReminders: 0,
      promos: const [],
      highlightToko: null,
      error: error,
      loadedAt: DateTime.now(),
      loggedIn: false,
    );
  }

  String brandLabel() =>
      (content?['brand_label'] ?? 'OPTIK B. RISKI').toString().trim();

  String greetingGuest() =>
      (content?['greeting_guest'] ?? 'Hi, Teman Optik!').toString();

  String greetingSubtitleGuest() => (content?['greeting_subtitle_guest'] ??
          'Login untuk lihat pesanan & garansi')
      .toString();

  String promoTitle() =>
      (content?['promo_title'] ?? 'Promo & poin').toString();

  String promoSubtitle() =>
      (content?['promo_subtitle'] ?? 'Voucher dan saldo poin kamu').toString();

  List<Map<String, String>> heroSlides() {
    final raw = content?['slides'];
    final out = <Map<String, String>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final title = (e['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        out.add({
          'title': title,
          'subtitle': (e['subtitle'] ?? '').toString(),
          'image_url': (e['image_url'] ?? '').toString(),
        });
      }
    }
    if (out.isEmpty) {
      return const [
        {
          'title': 'Kacamata siap?\nLangsung tahu di sini',
          'subtitle': 'Pantau status pesanan & ambil tanpa ribet',
          'image_url': '',
        },
        {
          'title': 'Garansi digital\nOptik B. Riski',
          'subtitle': 'Data asli sistem · klaim wajib cek di toko',
          'image_url': '',
        },
      ];
    }
    return out;
  }

  List<Map<String, dynamic>> orderedSections() {
    const fallback = [
      {'key': 'hero', 'visible': true, 'order': 0},
      {'key': 'greeting', 'visible': true, 'order': 1},
      {'key': 'promo', 'visible': true, 'order': 2},
      {'key': 'reminders', 'visible': true, 'order': 3},
      {'key': 'store', 'visible': true, 'order': 4},
      {'key': 'services_main', 'visible': true, 'order': 5},
      {'key': 'services_other', 'visible': true, 'order': 6},
    ];
    final raw = content?['sections'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }
    final src = list.isEmpty ? fallback : list;
    final sorted = [...src]
      ..sort((a, b) => ((a['order'] as num?)?.toInt() ?? 0)
          .compareTo((b['order'] as num?)?.toInt() ?? 0));
    return sorted.where((s) => s['visible'] != false).toList();
  }

  bool flag(String key) {
    final f = content?['feature_flags'];
    if (f is Map && f.containsKey(key)) return f[key] != false;
    return true;
  }

  static String promoDiscountLabel(Map<String, dynamic> p) {
    final type = (p['discount_type'] ?? 'nominal').toString();
    final value = int.tryParse('${p['discount_value'] ?? 0}') ?? 0;
    if (type == 'percent') return 'Diskon $value%';
    if (type == 'nominal' && value > 0) {
      final s = value.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]}.',
          );
      return 'Potongan Rp $s';
    }
    return (p['title'] ?? 'Promo Member').toString();
  }
}
