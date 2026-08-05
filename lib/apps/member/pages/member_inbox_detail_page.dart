import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/theme.dart';
import 'member_invoice_hub_page.dart';
import 'member_points_page.dart';

/// Detail pesan / promo Inbox — hero + judul + tanggal + isi (putih–biru premium).
class MemberInboxDetailPage extends StatelessWidget {
  const MemberInboxDetailPage({
    super.key,
    required this.title,
    required this.body,
    this.imageUrl,
    this.createdAt,
    this.isPromo = false,
    this.voucherCode,
    this.validUntil,
    this.terms,
    this.noInvoice,
    this.kind,
  });

  final String title;
  final String body;
  final String? imageUrl;
  final DateTime? createdAt;
  final bool isPromo;
  final String? voucherCode;
  final String? validUntil;
  final String? terms;
  final String? noInvoice;
  final String? kind;

  List<String> get _termLines {
    final raw = (terms ?? '').trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[\n\r]+|(?<=[.!?])\s+(?=[A-Z*•\-])'))
        .map((e) => e.trim().replaceFirst(RegExp(r'^[\*\-•]\s*'), ''))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _fmtDate(BuildContext context, DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd MMM yyyy', context.locale.toString())
        .format(dt.toLocal());
  }

  String _fmtUntil(BuildContext context) {
    final raw = (validUntil ?? '').trim();
    if (raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return DateFormat('dd MMM yyyy', context.locale.toString())
        .format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final dateLabel = _fmtDate(context, createdAt);
    final untilLabel = _fmtUntil(context);
    final termLines = _termLines;
    final hasImage = (imageUrl ?? '').trim().isNotEmpty;
    final summary = body.trim();
    final tagLabel = isPromo
        ? 'member_inbox_tag_promo'.tr()
        : 'member_inbox_tag_alert'.tr();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SizedBox(height: topPad + 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left_rounded, size: 32),
                  color: OptikMemberTokens.ink,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 36),
              children: [
                Text(
                  'member_inbox_detail_title'.tr(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: OptikMemberTokens.ink,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: OptikMemberTokens.blueDeep.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                      BoxShadow(
                        color: OptikMemberTokens.blue.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: hasImage
                          ? Image.network(
                              imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _HeroFallback(
                                isPromo: isPromo,
                                kind: kind,
                              ),
                            )
                          : _HeroFallback(isPromo: isPromo, kind: kind),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.blueMist,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: OptikMemberTokens.blue.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Text(
                      tagLabel.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: OptikMemberTokens.blueDeep,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: OptikMemberTokens.ink,
                    height: 1.22,
                    letterSpacing: -0.3,
                  ),
                ),
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                        color: OptikMemberTokens.inkMuted.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: OptikMemberTokens.inkMuted,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.blue.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    summary,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: OptikMemberTokens.ink.withValues(alpha: 0.88),
                      height: 1.55,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
                if ((voucherCode ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          OptikMemberTokens.blueMist,
                          OptikMemberTokens.blueSoft,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: OptikMemberTokens.blue.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.confirmation_number_outlined,
                            color: OptikMemberTokens.blueDeep,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'member_inbox_promo_code'.tr(
                              namedArgs: {'code': voucherCode!.trim()},
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: OptikMemberTokens.blueDeep,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (untilLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'member_inbox_promo_until'
                        .tr(namedArgs: {'date': untilLabel}),
                    style: const TextStyle(
                      fontSize: 13,
                      color: OptikMemberTokens.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (termLines.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text(
                    'member_inbox_terms_title'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: OptikMemberTokens.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...termLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: OptikMemberTokens.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              line,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: OptikMemberTokens.ink
                                    .withValues(alpha: 0.78),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (isPromo)
                  _PrimaryCta(
                    label: 'member_inbox_open_promos'.tr(),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MemberPointsPage(),
                        ),
                      );
                    },
                  )
                else if ((noInvoice ?? '').trim().isNotEmpty)
                  _PrimaryCta(
                    label: 'member_inbox_open_invoice'.tr(),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MemberInvoiceHubPage(
                            noInvoice: noInvoice!.trim(),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: OptikMemberTokens.blueDeep.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: OptikMemberTokens.blueDeep,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              letterSpacing: 0.15,
            ),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback({required this.isPromo, this.kind});

  final bool isPromo;
  final String? kind;

  IconData get _icon {
    if (isPromo) return Icons.local_offer_rounded;
    final k = (kind ?? '').toLowerCase();
    if (k.contains('ready') || k.contains('siap')) {
      return Icons.checkroom_rounded;
    }
    if (k.contains('payment') || k.contains('lunas')) {
      return Icons.payments_outlined;
    }
    if (k.contains('qr')) return Icons.qr_code_2_rounded;
    return Icons.mail_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final label = isPromo
        ? 'member_inbox_tag_promo'.tr()
        : 'member_inbox_tag_alert'.tr();

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0A2F6E),
                OptikMemberTokens.blueDeep,
                OptikMemberTokens.blue,
                Color(0xFF5B9BFF),
              ],
              stops: [0.0, 0.35, 0.72, 1.0],
            ),
          ),
        ),
        // Soft light wash
        Positioned(
          top: -40,
          right: -30,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
        ),
        Positioned(
          bottom: -50,
          left: -20,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        // Fine diagonal sheen
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.10),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(_icon, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 14),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
