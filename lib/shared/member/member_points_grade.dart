import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Grade Member:
/// Basic 0–249 · Silver 250–499 · Gold 500–999 · Platinum 1000–1999 · Diamond 2000+.
enum MemberGrade {
  basic,
  silver,
  gold,
  platinum,
  diamond,
}

/// Format angka poin Member (locale id → 80000 → `80.000`).
String formatMemberPoints(int value) =>
    NumberFormat.decimalPattern('id').format(value);

/// Label riwayat ledger (hindari raw reason key di UI).
String memberPointsLedgerTitle(String reason, {String invoice = ''}) {
  final r = reason.trim();
  final inv = invoice.trim();
  switch (r) {
    case 'purchase_10pct':
      return inv.isEmpty ? 'Belanja (invoice lunas)' : 'Invoice $inv';
    case 'voucher_redeem':
      return inv.isEmpty ? 'Tukar voucher' : 'Tukar voucher · $inv';
    case 'voucher_release_online':
      return 'Pengembalian poin voucher';
    case '':
      return 'Mutasi poin';
    default:
      return r.replaceAll('_', ' ');
  }
}

class MemberGradeBenefit {
  const MemberGradeBenefit(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}

class MemberGradePalette {
  const MemberGradePalette({
    required this.grade,
    required this.label,
    required this.unlockAt,
    required this.heroTop,
    required this.heroBottom,
    required this.cardTop,
    required this.cardMid,
    required this.cardBottom,
    required this.panel,
    required this.accent,
    required this.glow,
    required this.onCard,
    required this.onCardMuted,
    required this.progressFill,
    required this.badgeBg,
    required this.benefits,
  });

  final MemberGrade grade;
  final String label;
  final int unlockAt;
  final Color heroTop;
  final Color heroBottom;
  final Color cardTop;
  final Color cardMid;
  final Color cardBottom;
  final Color panel;
  final Color accent;
  final Color glow;
  final Color onCard;
  final Color onCardMuted;
  final Color progressFill;
  final Color badgeBg;
  final List<MemberGradeBenefit> benefits;

  static const basic = MemberGradePalette(
    grade: MemberGrade.basic,
    label: 'Basic',
    unlockAt: 0,
    heroTop: Color(0xFF053A8C),
    heroBottom: Color(0xFFEAF3FF),
    cardTop: Color(0xFF4DA3FF),
    cardMid: Color(0xFF0D6EFD),
    cardBottom: Color(0xFF04327A),
    panel: Color(0xFF061E45),
    accent: Color(0xFF0D6EFD),
    glow: Color(0xFF5BB8FF),
    onCard: Color(0xFFFFFFFF),
    onCardMuted: Color(0xD9FFFFFF),
    progressFill: Color(0xFF0D6EFD),
    badgeBg: Color(0xFFD6E8FF),
    benefits: [
      MemberGradeBenefit(
        Icons.percent_rounded,
        'Poin 10% per invoice',
        'Otomatis masuk setelah nota LUNAS',
      ),
      MemberGradeBenefit(
        Icons.card_giftcard_rounded,
        'Tukar voucher Member',
        'Pakai Poin Reward di promo aktif',
      ),
      MemberGradeBenefit(
        Icons.receipt_long_rounded,
        'Lacak pesanan & garansi',
        'Semua invoice terhubung di APK Member',
      ),
    ],
  );

  static const silver = MemberGradePalette(
    grade: MemberGrade.silver,
    label: 'Silver',
    unlockAt: 250,
    heroTop: Color(0xFF1B2A44),
    heroBottom: Color(0xFFEEF3FA),
    cardTop: Color(0xFFE8F0FA),
    cardMid: Color(0xFF7E95B8),
    cardBottom: Color(0xFF2A3D5C),
    panel: Color(0xFF121C2E),
    accent: Color(0xFF4A6FA5),
    glow: Color(0xFFB8CBF0),
    onCard: Color(0xFFFFFFFF),
    onCardMuted: Color(0xE6FFFFFF),
    progressFill: Color(0xFF4A6FA5),
    badgeBg: Color(0xFFE2EAF6),
    benefits: [
      MemberGradeBenefit(
        Icons.percent_rounded,
        'Poin 10% per invoice',
        'Sama seperti Basic, tetap otomatis',
      ),
      MemberGradeBenefit(
        Icons.local_offer_rounded,
        'Promo Silver eksklusif',
        'Voucher khusus grade Silver ke atas',
      ),
      MemberGradeBenefit(
        Icons.event_available_rounded,
        'Prioritas booking kontrol',
        'Jadwal lebih mudah dikonfirmasi',
      ),
      MemberGradeBenefit(
        Icons.support_agent_rounded,
        'Bantuan Member prioritas',
        'Respon lebih cepat via chat/WA toko',
      ),
    ],
  );

  static const gold = MemberGradePalette(
    grade: MemberGrade.gold,
    label: 'Gold',
    unlockAt: 500,
    heroTop: Color(0xFF5C3B0A),
    heroBottom: Color(0xFFFFF8E8),
    cardTop: Color(0xFFFFE08A),
    cardMid: Color(0xFFD4A017),
    cardBottom: Color(0xFF7A4E08),
    panel: Color(0xFF2A1A05),
    accent: Color(0xFFC9970A),
    glow: Color(0xFFFFE7A3),
    onCard: Color(0xFFFFFDF6),
    onCardMuted: Color(0xE6FFF8E1),
    progressFill: Color(0xFFD4A017),
    badgeBg: Color(0xFFFFF0C2),
    benefits: [
      MemberGradeBenefit(
        Icons.percent_rounded,
        'Poin 10% per invoice',
        'Kredit Status + Reward Poin',
      ),
      MemberGradeBenefit(
        Icons.workspace_premium_rounded,
        'Promo Gold eksklusif',
        'Diskon & bundling grade Gold',
      ),
      MemberGradeBenefit(
        Icons.schedule_rounded,
        'Antrian prioritas di toko',
        'Layanan lebih cepat saat kunjungan',
      ),
      MemberGradeBenefit(
        Icons.cleaning_services_rounded,
        'Gratis cek & bersihkan frame',
        '1x per periode keanggotaan Gold',
      ),
      MemberGradeBenefit(
        Icons.support_agent_rounded,
        'Bantuan prioritas 24 jam',
        'Channel khusus Member Gold+',
      ),
    ],
  );

  static const platinum = MemberGradePalette(
    grade: MemberGrade.platinum,
    label: 'Platinum',
    unlockAt: 1000,
    heroTop: Color(0xFF1A1D24),
    heroBottom: Color(0xFFF4F5F7),
    cardTop: Color(0xFFF5F7FA),
    cardMid: Color(0xFFB8C0CC),
    cardBottom: Color(0xFF4A5160),
    panel: Color(0xFF12151C),
    accent: Color(0xFF8E98A8),
    glow: Color(0xFFE8EDF5),
    onCard: Color(0xFFFFFFFF),
    onCardMuted: Color(0xF0FFFFFF),
    progressFill: Color(0xFF9AA3B2),
    badgeBg: Color(0xFFECEFF4),
    benefits: [
      MemberGradeBenefit(
        Icons.percent_rounded,
        'Poin 10% per invoice',
        'Kredit Status + Reward Poin',
      ),
      MemberGradeBenefit(
        Icons.diamond_rounded,
        'Promo Platinum eksklusif',
        'Penawaran terbaik & limited',
      ),
      MemberGradeBenefit(
        Icons.priority_high_rounded,
        'Prioritas penuh di semua layanan',
        'Booking, klaim, dan pickup diutamakan',
      ),
      MemberGradeBenefit(
        Icons.visibility_rounded,
        'Gratis cek mata berkala',
        '1x pemeriksaan dasar per tahun',
      ),
      MemberGradeBenefit(
        Icons.card_membership_rounded,
        'Undangan event & preview produk',
        'Akses lebih awal katalog baru',
      ),
      MemberGradeBenefit(
        Icons.support_agent_rounded,
        'Personal assistance',
        'Dedicated support Member Platinum',
      ),
    ],
  );

  /// Diamond — di atas Platinum (2000+): hitam kristal + biru diamond.
  static const diamond = MemberGradePalette(
    grade: MemberGrade.diamond,
    label: 'Diamond',
    unlockAt: 2000,
    heroTop: Color(0xFF050814),
    heroBottom: Color(0xFFE8F4FF),
    cardTop: Color(0xFFB8E0FF),
    cardMid: Color(0xFF3D6FA8),
    cardBottom: Color(0xFF0A1020),
    panel: Color(0xFF03060F),
    accent: Color(0xFF6EC6FF),
    glow: Color(0xFFC9ECFF),
    onCard: Color(0xFFFFFFFF),
    onCardMuted: Color(0xE6FFFFFF),
    progressFill: Color(0xFF6EC6FF),
    badgeBg: Color(0xFFD9F0FF),
    benefits: [
      MemberGradeBenefit(
        Icons.percent_rounded,
        'Poin 10% per invoice',
        'Akumulasi Status Poin tertinggi',
      ),
      MemberGradeBenefit(
        Icons.auto_awesome_rounded,
        'Promo Diamond eksklusif',
        'Hadiah & penawaran langka Member Diamond',
      ),
      MemberGradeBenefit(
        Icons.priority_high_rounded,
        'VIP penuh semua layanan',
        'Antrian, klaim, pickup paling diutamakan',
      ),
      MemberGradeBenefit(
        Icons.visibility_rounded,
        'Paket cek mata premium',
        'Pemeriksaan berkala + konsultasi',
      ),
      MemberGradeBenefit(
        Icons.card_membership_rounded,
        'Akses early product & event',
        'Undangan private & preview merek',
      ),
      MemberGradeBenefit(
        Icons.support_agent_rounded,
        'Concierge Member Diamond',
        'Personal assistance prioritas tertinggi',
      ),
      MemberGradeBenefit(
        Icons.redeem_rounded,
        'Surprise reward tahunan',
        'Bonus spesial untuk Diamond aktif',
      ),
    ],
  );

  static final all = [basic, silver, gold, platinum, diamond];

  static MemberGradePalette of(MemberGrade g) {
    switch (g) {
      case MemberGrade.basic:
        return basic;
      case MemberGrade.silver:
        return silver;
      case MemberGrade.gold:
        return gold;
      case MemberGrade.platinum:
        return platinum;
      case MemberGrade.diamond:
        return diamond;
    }
  }

  static int indexOf(MemberGrade g) =>
      all.indexWhere((e) => e.grade == g).clamp(0, all.length - 1);
}

abstract final class MemberGradeThresholds {
  static const silverAt = 250;
  static const goldAt = 500;
  static const platinumAt = 1000;
  static const diamondAt = 2000;

  static MemberGrade fromStatusPoints(int statusPoints) {
    if (statusPoints >= diamondAt) return MemberGrade.diamond;
    if (statusPoints >= platinumAt) return MemberGrade.platinum;
    if (statusPoints >= goldAt) return MemberGrade.gold;
    if (statusPoints >= silverAt) return MemberGrade.silver;
    return MemberGrade.basic;
  }

  static int unlockAt(MemberGrade grade) =>
      MemberGradePalette.of(grade).unlockAt;

  static MemberGrade? nextGrade(MemberGrade grade) {
    switch (grade) {
      case MemberGrade.basic:
        return MemberGrade.silver;
      case MemberGrade.silver:
        return MemberGrade.gold;
      case MemberGrade.gold:
        return MemberGrade.platinum;
      case MemberGrade.platinum:
        return MemberGrade.diamond;
      case MemberGrade.diamond:
        return null;
    }
  }

  static bool isUnlocked(MemberGrade grade, int statusPoints) =>
      statusPoints >= unlockAt(grade);

  static int pointsToGrade(MemberGrade target, int statusPoints) {
    final need = unlockAt(target) - statusPoints;
    return need < 0 ? 0 : need;
  }

  static double trackProgress(int statusPoints) {
    const max = diamondAt;
    if (statusPoints <= 0) return 0;
    if (statusPoints >= max) return 1;
    return (statusPoints / max).clamp(0.0, 1.0);
  }

  static double progress(int statusPoints) {
    final grade = fromStatusPoints(statusPoints);
    final next = nextGrade(grade);
    if (next == null) return 1;
    final floor = unlockAt(grade);
    final ceil = unlockAt(next);
    if (ceil <= floor) return 1;
    return ((statusPoints - floor) / (ceil - floor)).clamp(0.0, 1.0);
  }

  static int pointsToNext(int statusPoints) {
    final grade = fromStatusPoints(statusPoints);
    final next = nextGrade(grade);
    if (next == null) return 0;
    return pointsToGrade(next, statusPoints);
  }
}

class MemberPointsSnapshot {
  const MemberPointsSnapshot({
    required this.rewardPoints,
    required this.statusPoints,
  });

  final int rewardPoints;
  final int statusPoints;

  MemberGrade get grade =>
      MemberGradeThresholds.fromStatusPoints(statusPoints);

  MemberGradePalette get palette => MemberGradePalette.of(grade);
}
