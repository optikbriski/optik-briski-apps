import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_points_grade.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_layout.dart';
import 'member_grade_wah_card.dart';

class MemberPointsPage extends StatefulWidget {
  const MemberPointsPage({super.key});

  @override
  State<MemberPointsPage> createState() => _MemberPointsPageState();
}

class _MemberPointsPageState extends State<MemberPointsPage> {
  /// PREVIEW: buka semua grade supaya konsep "wah" tiap level bisa dilihat.
  /// Set `false` sebelum rilis produksi.
  static const bool kPreviewUnlockAllGrades = true;

  final _repo = MemberRepository();
  PageController? _pageCtrl;
  double _viewportFraction = 0.9;

  MemberPointsSnapshot _snap =
      const MemberPointsSnapshot(rewardPoints: 0, statusPoints: 0);
  List<Map<String, dynamic>> _promos = const [];
  List<Map<String, dynamic>> _ledger = const [];
  bool _loading = true;
  int _page = 0;

  static final _num = NumberFormat.decimalPattern('id');

  MemberGradePalette get _viewed => MemberGradePalette.all[_page];

  /// Status Poin efektif untuk UI (preview = Diamond max).
  int get _effectiveStatus => kPreviewUnlockAllGrades
      ? MemberGradeThresholds.diamondAt
      : _snap.statusPoints;

  bool _isOpen(MemberGrade g) =>
      MemberGradeThresholds.isUnlocked(g, _effectiveStatus);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frac = MemberLayout.isTablet(context) ? 0.56 : 0.9;
    if (_pageCtrl == null) {
      _viewportFraction = frac;
      _pageCtrl = PageController(
        viewportFraction: frac,
        initialPage: _page,
      );
      return;
    }
    if ((frac - _viewportFraction).abs() > 0.01) {
      final page = _pageCtrl!.hasClients
          ? (_pageCtrl!.page?.round() ?? _page)
          : _page;
      _pageCtrl!.dispose();
      _viewportFraction = frac;
      _pageCtrl = PageController(
        viewportFraction: frac,
        initialPage: page,
      );
    }
  }

  @override
  void dispose() {
    _pageCtrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final mid = MemberSession.instance.memberId;
    final promos = await _repo.listPromos();
    MemberPointsSnapshot snap =
        const MemberPointsSnapshot(rewardPoints: 0, statusPoints: 0);
    List<Map<String, dynamic>> ledger = const [];
    if (mid != null && mid.isNotEmpty) {
      snap = await _repo.pointsSummary(mid);
      ledger = await _repo.pointsLedger(mid);
    }
    if (!mounted) return;
    final idx = MemberGradePalette.indexOf(snap.grade);
    setState(() {
      _promos = promos;
      _snap = snap;
      _ledger = ledger;
      _loading = false;
      _page = idx;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _pageCtrl;
      if (c != null && c.hasClients) {
        c.jumpToPage(idx);
      }
    });
  }

  String _discountLabel(Map<String, dynamic> p) {
    final type = (p['discount_type'] ?? 'nominal').toString();
    final value = int.tryParse('${p['discount_value'] ?? 0}') ?? 0;
    if (type == 'percent') return 'Diskon $value%';
    if (type == 'nominal' && value > 0) {
      return 'Potongan Rp ${_num.format(value)}';
    }
    return (p['title'] ?? 'Promo Member').toString();
  }

  void _openInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OptikMemberTokens.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: OptikMemberTokens.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Grade & Poin Member',
              style: TextStyle(
                color: OptikMemberTokens.blueDeep,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Grade terbuka otomatis sesuai Status Poin — tidak perlu klaim manual.\n'
              'Basic selalu aktif sejak daftar Member.\n\n'
              'Setiap 1 invoice LUNAS = 10% dari total harga sebagai poin.\n\n'
              'Ambang Status Poin:\n'
              '• Basic — 0–249 (langsung aktif)\n'
              '• Silver — 250–499\n'
              '• Gold — 500–999\n'
              '• Platinum — 1.000–1.999\n'
              '• Diamond — 2.000+',
              style: const TextStyle(
                color: OptikMemberTokens.inkSecondary,
                height: 1.45,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      ),
    );
  }

  void _openHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OptikMemberTokens.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Riwayat poin',
                      style: TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _ledger.isEmpty
                      ? const Center(
                          child: Text(
                            'Belum ada riwayat poin.',
                            style: TextStyle(color: OptikMemberTokens.inkMuted),
                          ),
                        )
                      : ListView.separated(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _ledger.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final row = _ledger[i];
                            final delta =
                                int.tryParse('${row['delta'] ?? 0}') ?? 0;
                            final reason = (row['reason'] ?? '').toString();
                            final meta = row['meta'];
                            var inv = '';
                            if (meta is Map) {
                              inv = (meta['no_invoice'] ?? '').toString();
                            }
                            final title = reason == 'purchase_10pct'
                                ? 'Invoice${inv.isEmpty ? '' : ' $inv'}'
                                : reason;
                            final at = (row['created_at'] ?? '').toString();
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: OptikMemberTokens.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: OptikMemberTokens.lineSoft),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (at.length >= 10)
                                          Text(
                                            at.substring(0, 10),
                                            style: const TextStyle(
                                              color: OptikMemberTokens.inkMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${delta >= 0 ? '+' : ''}${_num.format(delta)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: delta >= 0
                                          ? OptikMemberTokens.success
                                          : OptikMemberTokens.danger,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openAllRewards() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AllRewardsPage(
          promos: _promos,
          rewardPoints: _snap.rewardPoints,
          palette: _snap.palette,
          discountLabel: _discountLabel,
        ),
      ),
    );
  }

  void _goPage(int i) {
    final target = i.clamp(0, MemberGradePalette.all.length - 1);
    _pageCtrl?.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final viewed = _viewed;
    final unlocked = _isOpen(viewed.grade);
    final need = MemberGradeThresholds.pointsToGrade(
      viewed.grade,
      _effectiveStatus,
    );
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    final cardH = m.isTablet
        ? (screenH * 0.5).clamp(480.0, 580.0)
        : (screenH * 0.48).clamp(390.0, 460.0);
    // Preview: tiap slide tampil sebagai grade aktif supaya "wah"-nya kelihatan.
    final previewActiveGrade = kPreviewUnlockAllGrades
        ? viewed.grade
        : _snap.grade;
    final pageCtrl = _pageCtrl;
    if (pageCtrl == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: viewed.heroTop,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Ambient full-page — satu gradien grade, tidak belang
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          viewed.heroTop,
                          Color.lerp(viewed.heroTop, viewed.cardMid, 0.45)!,
                          viewed.heroBottom,
                          viewed.badgeBg,
                          Color.lerp(
                                viewed.glow,
                                OptikMemberTokens.canvas,
                                0.55,
                              ) ??
                              OptikMemberTokens.canvas,
                          OptikMemberTokens.canvas,
                        ],
                        stops: const [0, 0.18, 0.38, 0.55, 0.78, 1],
                      ),
                    ),
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  color: viewed.accent,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        backgroundColor: viewed.heroTop.withOpacity(0.92),
                        foregroundColor: Colors.white,
                        surfaceTintColor: Colors.transparent,
                        iconTheme: const IconThemeData(color: Colors.white),
                        title: Text(
                          'Member',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: m.isTablet ? 20 : 17,
                          ),
                        ),
                        actions: [
                          TextButton.icon(
                            onPressed: _openInfo,
                            icon: Icon(Icons.info_outline_rounded,
                                size: m.isTablet ? 20 : 18,
                                color: Colors.white),
                            label: Text('Info',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: m.isTablet ? 15 : 14,
                                )),
                          ),
                          IconButton(
                            tooltip: 'Riwayat',
                            onPressed: _openHistory,
                            icon: Icon(Icons.history_rounded,
                                size: m.isTablet ? 26 : 24,
                                color: Colors.white),
                          ),
                        ],
                      ),
                      SliverToBoxAdapter(
                        child: MemberLayout.constrain(
                          context,
                          Column(
                            children: [
                              SizedBox(height: m.isTablet ? 12 : 8),
                              if (kPreviewUnlockAllGrades)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      m.pagePadding, 0, m.pagePadding, 8),
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: m.isTablet ? 16 : 12,
                                        vertical: m.isTablet ? 10 : 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.35),
                                      ),
                                    ),
                                    child: Text(
                                      'PREVIEW · semua grade dibuka — geser untuk lihat konsep wah tiap level',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: m.isTablet ? 13 : 11.5,
                                      ),
                                    ),
                                  ),
                                ),
                              _GradeTrackBar(
                                viewedIndex: _page,
                                statusPoints: _effectiveStatus,
                                onTap: _goPage,
                                isTablet: m.isTablet,
                              ),
                              SizedBox(height: m.isTablet ? 16 : 12),
                              SizedBox(
                                height: cardH,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    PageView.builder(
                                      controller: pageCtrl,
                                      itemCount: MemberGradePalette.all.length,
                                      onPageChanged: (i) =>
                                          setState(() => _page = i),
                                      itemBuilder: (_, i) {
                                        final g = MemberGradePalette.all[i];
                                        final open = _isOpen(g.grade);
                                        final left =
                                            MemberGradeThresholds.pointsToGrade(
                                          g.grade,
                                          _effectiveStatus,
                                        );
                                        return Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: m.isTablet ? 10 : 6),
                                          child: MemberGradeWahCard(
                                            palette: g,
                                            unlocked: open,
                                            pointsNeeded: left,
                                            isCurrent:
                                                g.grade == previewActiveGrade,
                                            statusPoints:
                                                kPreviewUnlockAllGrades
                                                    ? g.unlockAt
                                                    : _snap.statusPoints,
                                            rewardPoints: _snap.rewardPoints,
                                          ),
                                        );
                                      },
                                    ),
                                    if (_page > 0)
                                      Positioned(
                                        left: m.isTablet ? 8 : 4,
                                        child: _NavChip(
                                          icon: Icons.chevron_left_rounded,
                                          onTap: () => _goPage(_page - 1),
                                          isTablet: m.isTablet,
                                        ),
                                      ),
                                    if (_page <
                                        MemberGradePalette.all.length - 1)
                                      Positioned(
                                        right: m.isTablet ? 8 : 4,
                                        child: _NavChip(
                                          icon: Icons.chevron_right_rounded,
                                          onTap: () => _goPage(_page + 1),
                                          isTablet: m.isTablet,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(height: m.isTablet ? 14 : 10),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: m.pagePadding + 4),
                                child: Text(
                                  unlocked
                                      ? (viewed.grade == previewActiveGrade
                                          ? 'Grade aktif · ${_num.format(kPreviewUnlockAllGrades ? viewed.unlockAt : _snap.statusPoints)} Status Poin'
                                          : '${viewed.label} sudah terbuka (poin cukup)')
                                      : '${_num.format(need)} Status Poin lagi untuk membuka ${viewed.label}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: viewed.panel,
                                    fontWeight: FontWeight.w800,
                                    fontSize: m.isTablet ? 15 : 13.5,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Grade terbuka otomatis sesuai Status Poin',
                                style: TextStyle(
                                  color: viewed.accent.withOpacity(0.9),
                                  fontSize: m.isTablet ? 13 : 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Geser untuk lihat grade & benefit lain',
                                style: TextStyle(
                                  color: viewed.accent.withOpacity(0.75),
                                  fontSize: m.isTablet ? 13.5 : 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: m.isTablet ? 28 : 22),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: m.pagePadding),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Nikmati ${viewed.benefits.length} benefit',
                                      style: TextStyle(
                                        color: viewed.panel,
                                        fontWeight: FontWeight.w900,
                                        fontSize: m.isTablet ? 22 : 20,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      viewed.grade == previewActiveGrade
                                          ? 'Benefit grade aktif (${viewed.label})'
                                          : unlocked
                                              ? 'Benefit ${viewed.label} · sudah terbuka'
                                              : 'Benefit setelah membuka ${viewed.label}',
                                      style: TextStyle(
                                        color: viewed.accent,
                                        fontSize: m.isTablet ? 14.5 : 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: m.isTablet ? 16 : 14),
                                    ...viewed.benefits.map(
                                      (b) => _BenefitTile(
                                        icon: b.icon,
                                        title: b.title,
                                        subtitle: b.subtitle,
                                        accent: viewed.accent,
                                        glow: viewed.glow,
                                        locked: !unlocked,
                                        isTablet: m.isTablet,
                                      ),
                                    ),
                                    SizedBox(
                                        height: (m.isTablet ? 110 : 100) +
                                            bottomPad),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: m.pagePadding,
                  right: m.pagePadding,
                  bottom: 14 + bottomPad,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: m.isTablet ? 420 : double.infinity,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [viewed.cardMid, viewed.cardBottom],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: viewed.glow.withOpacity(0.55),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: viewed.cardBottom.withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _openAllRewards,
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: m.isTablet ? 28 : 22,
                                vertical: m.isTablet ? 16 : 14,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.card_giftcard_rounded,
                                      color: Colors.white,
                                      size: m.isTablet ? 22 : 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Tukar Poin Reward sekarang!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: m.isTablet ? 15.5 : 14.5,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _GradeTrackBar extends StatelessWidget {
  const _GradeTrackBar({
    required this.viewedIndex,
    required this.statusPoints,
    required this.onTap,
    required this.isTablet,
  });

  final int viewedIndex;
  final int statusPoints;
  final ValueChanged<int> onTap;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final grades = MemberGradePalette.all;
    final progress = MemberGradeThresholds.trackProgress(statusPoints);
    final labelSize = isTablet ? 13.0 : 10.5;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 28 : 12),
      child: Column(
        children: [
          Row(
            children: List.generate(grades.length, (i) {
              final g = grades[i];
              final selected = i == viewedIndex;
              final open = MemberGradeThresholds.isUnlocked(
                g.grade,
                statusPoints,
              );
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (open)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  size: isTablet ? 13 : 10,
                                  color: selected
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.75),
                                ),
                              ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  g.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : open
                                            ? Colors.white.withOpacity(0.82)
                                            : Colors.white.withOpacity(0.42),
                                    fontWeight: selected
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    fontSize: labelSize,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.04, 1.0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFB8D9FF)],
                    ),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.55),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.icon,
    required this.onTap,
    required this.isTablet,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final size = isTablet ? 42.0 : 34.0;
    return Material(
      color: Colors.white.withOpacity(0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon,
              size: isTablet ? 26 : 22, color: OptikMemberTokens.blueDeep),
        ),
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.glow,
    required this.locked,
    required this.isTablet,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color glow;
  final bool locked;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final iconBox = isTablet ? 54.0 : 48.0;
    return Opacity(
      opacity: locked ? 0.7 : 1,
      child: Container(
        margin: EdgeInsets.only(bottom: isTablet ? 12 : 11),
        decoration: BoxDecoration(
          color: OptikMemberTokens.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.14)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [glow, accent],
                  ),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      isTablet ? 14 : 12, isTablet ? 16 : 14, 14, isTablet ? 16 : 14),
                  child: Row(
                    children: [
                      Container(
                        width: iconBox,
                        height: iconBox,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withOpacity(0.18),
                              glow.withOpacity(0.22),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon,
                            color: accent, size: isTablet ? 26 : 24),
                      ),
                      SizedBox(width: isTablet ? 14 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color.lerp(accent, Colors.black, 0.45),
                                fontSize: isTablet ? 16 : 14.5,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: OptikMemberTokens.inkMuted,
                                fontSize: isTablet ? 13.5 : 12.5,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        locked
                            ? Icons.lock_outline_rounded
                            : Icons.chevron_right_rounded,
                        color: accent.withOpacity(0.7),
                        size: isTablet ? 22 : 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllRewardsPage extends StatelessWidget {
  const _AllRewardsPage({
    required this.promos,
    required this.rewardPoints,
    required this.palette,
    required this.discountLabel,
  });

  final List<Map<String, dynamic>> promos;
  final int rewardPoints;
  final MemberGradePalette palette;
  final String Function(Map<String, dynamic>) discountLabel;

  static final _num = NumberFormat.decimalPattern('id');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      appBar: AppBar(
        title: const Text('Tukar hadiah'),
        backgroundColor: OptikMemberTokens.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OptikMemberTokens.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OptikMemberTokens.lineSoft),
              ),
              child: Row(
                children: [
                  Icon(Icons.stars_rounded, color: palette.accent),
                  const SizedBox(width: 10),
                  Text(
                    '${_num.format(rewardPoints)} Poin Reward',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: OptikMemberTokens.blueDeep,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: promos.isEmpty
                ? const Center(child: Text('Belum ada hadiah.'))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: promos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemBuilder: (_, i) => _RewardCard(
                      promo: promos[i],
                      rewardPoints: rewardPoints,
                      title: discountLabel(promos[i]),
                      accent: palette.accent,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.promo,
    required this.rewardPoints,
    required this.title,
    required this.accent,
  });

  final Map<String, dynamic> promo;
  final int rewardPoints;
  final String title;
  final Color accent;

  static final _num = NumberFormat.decimalPattern('id');

  @override
  Widget build(BuildContext context) {
    final cost = int.tryParse('${promo['points_cost'] ?? 0}') ?? 0;
    final can = rewardPoints >= cost;
    final code = (promo['voucher_code'] ?? '').toString();
    final sub = (promo['title'] ?? 'Promo').toString();

    return Container(
      decoration: BoxDecoration(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.local_offer_rounded, color: accent, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: OptikMemberTokens.inkMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: OptikMemberTokens.blueSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              cost > 0 ? '${_num.format(cost)} poin' : 'Gratis',
              style: const TextStyle(
                color: OptikMemberTokens.blueDeep,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton(
              onPressed: () async {
                if (cost > 0 && !can) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Poin kurang. Butuh ${_num.format(cost)} Poin Reward.',
                      ),
                    ),
                  );
                  return;
                }
                if (code.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tunjukkan promo ini ke kasir.'),
                    ),
                  );
                  return;
                }
                await Clipboard.setData(ClipboardData(text: code));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Kode $code disalin')),
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    can || cost == 0
                        ? Icons.card_giftcard_rounded
                        : Icons.lock_outline_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Text('Tukar', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
