import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/optik_brand_logo.dart';
import 'member_layout.dart';

/// Scaffold putih–biru premium — dipakai di semua halaman Member.
class MemberPremiumScaffold extends StatelessWidget {
  const MemberPremiumScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.leading,
    this.subtitle,
    this.resizeToAvoidBottomInset,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? leading;
  final String? subtitle;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: AppBar(
        leading: leading,
        title: subtitle == null || subtitle!.isEmpty
            ? Text(
                title,
                style: TextStyle(
                  color: OptikMemberTokens.blueDeep,
                  fontSize: m.isTablet ? 19 : 17,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: OptikMemberTokens.blueDeep,
                      fontSize: m.isTablet ? 19 : 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: OptikMemberTokens.inkMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar == null
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                color: OptikMemberTokens.white,
                border: Border(
                  top: BorderSide(color: OptikMemberTokens.lineSoft),
                ),
              ),
              child: bottomNavigationBar,
            ),
    );
  }
}

class MemberHeroHeader extends StatelessWidget {
  const MemberHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            OptikMemberTokens.blueDeep,
            OptikMemberTokens.blue,
            OptikMemberTokens.blueMid,
          ],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(OptikMemberTokens.radiusXl),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const OptikBrandLogo.white(height: 28),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class MemberSectionLabel extends StatelessWidget {
  const MemberSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: m.isTablet ? 12 : 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: OptikMemberTokens.blueDeep,
          fontSize: m.isTablet ? 12.5 : 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class MemberFeatureTile extends StatelessWidget {
  const MemberFeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final iconBox = m.isTablet ? 52.0 : 46.0;
    return Material(
      color: OptikMemberTokens.white,
      borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        child: Container(
          padding: EdgeInsets.all(m.isTablet ? 16 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
            border: Border.all(color: OptikMemberTokens.lineSoft),
            boxShadow: OptikMemberTokens.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: OptikMemberTokens.blueSoft,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusSm),
                ),
                child: Icon(icon, color: OptikMemberTokens.blue, size: m.iconSize),
              ),
              SizedBox(width: m.isTablet ? 14 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: OptikMemberTokens.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: m.menuTitleSize,
                            ),
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: OptikMemberTokens.blueSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                color: OptikMemberTokens.blueDeep,
                                fontSize: m.isTablet ? 11 : 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: m.menuSubtitleSize,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: OptikMemberTokens.blue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MemberEmptyState extends StatelessWidget {
  const MemberEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: OptikMemberTokens.blueSoft,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 34, color: OptikMemberTokens.blue),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: OptikMemberTokens.blueDeep,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Halaman dasar fitur (isi logic menyusul) — visual seragam.
class MemberBaseFeaturePage extends StatelessWidget {
  const MemberBaseFeaturePage({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.bullets,
    this.icon = Icons.auto_awesome_outlined,
    this.footerNote,
  });

  final String title;
  final String eyebrow;
  final String description;
  final List<String> bullets;
  final IconData icon;
  final String? footerNote;

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: OptikMemberTokens.white,
              borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
              border: Border.all(color: OptikMemberTokens.lineSoft),
              boxShadow: OptikMemberTokens.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blueSoft,
                    borderRadius:
                        BorderRadius.circular(OptikMemberTokens.radiusSm),
                  ),
                  child: Icon(icon, color: OptikMemberTokens.blue),
                ),
                const SizedBox(height: 14),
                Text(
                  eyebrow.toUpperCase(),
                  style: const TextStyle(
                    color: OptikMemberTokens.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: OptikMemberTokens.blueDeep,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: OptikMemberTokens.inkSecondary,
                    height: 1.45,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const MemberSectionLabel('Yang akan tersedia'),
          ...bullets.map(
            (b) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: OptikMemberTokens.white,
                borderRadius: BorderRadius.circular(OptikMemberTokens.radiusSm),
                border: Border.all(color: OptikMemberTokens.lineSoft),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: OptikMemberTokens.blue,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        color: OptikMemberTokens.ink,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (footerNote != null) ...[
            const SizedBox(height: 12),
            Text(
              footerNote!,
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Countdown batas bayar 15 menit (stok di-hold sampai lunas / habis waktu).
class MemberPaymentCountdownBanner extends StatelessWidget {
  const MemberPaymentCountdownBanner({
    super.key,
    required this.remaining,
    this.compact = false,
  });

  final Duration remaining;
  final bool compact;

  static DateTime? expiresAtFromOrder(Map<String, dynamic>? order) {
    if (order == null) return null;
    final raw = order['expires_at'];
    final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
    if (parsed != null) return parsed.toLocal();
    final created = DateTime.tryParse('${order['created_at'] ?? ''}');
    if (created == null) return null;
    return created.toLocal().add(const Duration(minutes: 15));
  }

  static String formatMmSs(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final expired = remaining <= Duration.zero;
    final tone = expired
        ? OptikMemberTokens.danger
        : remaining.inMinutes < 3
            ? const Color(0xFFB45309)
            : OptikMemberTokens.blueDeep;
    final bg = expired
        ? OptikMemberTokens.danger.withOpacity(0.08)
        : tone.withOpacity(0.08);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        border: Border.all(color: tone.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(
            expired ? Icons.timer_off_outlined : Icons.timer_outlined,
            color: tone,
            size: compact ? 20 : 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expired
                      ? 'Waktu bayar habis'
                      : 'Selesaikan bayar dalam ${formatMmSs(remaining)}',
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 13.5 : 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  expired
                      ? 'Pesanan dibatalkan, stok dikembalikan. Buat pesanan baru.'
                      : 'Stok produk di-hold 15 menit sampai pembayaran selesai.',
                  style: TextStyle(
                    color: OptikMemberTokens.inkSecondary,
                    fontSize: compact ? 11.5 : 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
