import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_points_grade.dart';
import '../member_layout.dart';

/// Kartu grade — unlocked: full foil premium; locked: redup + gembok.
class MemberGradeWahCard extends StatefulWidget {
  const MemberGradeWahCard({
    super.key,
    required this.palette,
    required this.unlocked,
    required this.pointsNeeded,
    required this.isCurrent,
    required this.statusPoints,
    required this.rewardPoints,
  });

  final MemberGradePalette palette;
  final bool unlocked;
  final int pointsNeeded;
  final bool isCurrent;
  final int statusPoints;
  final int rewardPoints;

  @override
  State<MemberGradeWahCard> createState() => _MemberGradeWahCardState();
}

class _MemberGradeWahCardState extends State<MemberGradeWahCard>
    with TickerProviderStateMixin {
  static final _num = NumberFormat.decimalPattern('id');
  late final AnimationController _pulse;
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (widget.unlocked) {
      _pulse.repeat();
      _shimmer.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MemberGradeWahCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unlocked && !_pulse.isAnimating) {
      _pulse.repeat();
      _shimmer.repeat();
    } else if (!widget.unlocked && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
      _shimmer
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  IconData get _heroIcon {
    switch (widget.palette.grade) {
      case MemberGrade.basic:
        return Icons.remove_red_eye_rounded;
      case MemberGrade.silver:
        return Icons.shield_rounded;
      case MemberGrade.gold:
        return Icons.workspace_premium_rounded;
      case MemberGrade.platinum:
        return Icons.hexagon_rounded;
      case MemberGrade.diamond:
        return Icons.diamond_rounded;
    }
  }

  String get _tagline {
    switch (widget.palette.grade) {
      case MemberGrade.basic:
        return 'Fresh Pulse';
      case MemberGrade.silver:
        return 'Steel Aura';
      case MemberGrade.gold:
        return 'Golden Prestige';
      case MemberGrade.platinum:
        return 'Platinum Elite';
      case MemberGrade.diamond:
        return 'Crystal Apex';
    }
  }

  String get _subTag {
    switch (widget.palette.grade) {
      case MemberGrade.basic:
        return 'Mulai perjalanan Member OBR';
      case MemberGrade.silver:
        return 'Lebih solid · prioritas naik';
      case MemberGrade.gold:
        return 'Emas berkilau · layanan unggul';
      case MemberGrade.platinum:
        return 'Platinum premium · akses elite';
      case MemberGrade.diamond:
        return 'Puncak Member · VIP penuh';
    }
  }

  String get _subEyebrow {
    switch (widget.palette.grade) {
      case MemberGrade.basic:
        return 'MEMBER JOURNEY';
      case MemberGrade.silver:
        return 'ELEVATED ACCESS';
      case MemberGrade.gold:
        return 'GOLD PRIVILEGE';
      case MemberGrade.platinum:
        return 'ELITE CIRCLE';
      case MemberGrade.diamond:
        return 'APEX TIER';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final unlocked = widget.unlocked;
    final tablet = MemberLayout.isTablet(context);
    final pad = tablet ? 20.0 : 12.0;
    final titleSize = tablet ? 24.0 : 18.0;
    final subSize = tablet ? 14.5 : 12.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _shimmer]),
      builder: (context, _) {
        final t = unlocked ? _pulse.value : 0.0;
        final s = unlocked ? _shimmer.value : 0.0;
        final breath = 0.9 + 0.1 * (0.5 + 0.5 * math.sin(t * math.pi * 2));

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tablet ? 36 : 32),
            boxShadow: unlocked
                ? [
                    BoxShadow(
                      color: p.glow.withOpacity(0.75 * breath),
                      blurRadius: tablet ? 48 : 42,
                      spreadRadius: 2,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: p.accent.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tablet ? 36 : 32),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // === BACKGROUND ===
                if (unlocked)
                  _UnlockedFoilBg(palette: p, shimmer: s)
                else
                  _LockedBg(palette: p),

                if (unlocked)
                  CustomPaint(
                    painter: GradeWahPainter(
                      grade: p.grade,
                      glow: p.glow,
                      accent: p.accent,
                      t: t,
                    ),
                  ),

                // Inner frame (premium border)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(29),
                        border: Border.all(
                          color: unlocked
                              ? Colors.white.withOpacity(0.45)
                              : Colors.white.withOpacity(0.08),
                          width: unlocked ? 1.4 : 1,
                        ),
                      ),
                    ),
                  ),
                ),

                // Corner ornaments when unlocked
                if (unlocked) ...[
                  Positioned(
                    top: 18,
                    left: 18,
                    child: _CornerStar(color: p.glow, size: 10),
                  ),
                  Positioned(
                    top: 18,
                    right: 18,
                    child: _CornerStar(color: p.glow, size: 10),
                  ),
                  Positioned(
                    bottom: 18,
                    left: 18,
                    child: _CornerStar(color: p.glow, size: 8),
                  ),
                  Positioned(
                    bottom: 18,
                    right: 18,
                    child: _CornerStar(color: p.glow, size: 8),
                  ),
                ],

                // === CONTENT ===
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final h = constraints.maxHeight;
                      // Skala hero supaya footer + header selalu muat.
                      final heroBudget = (h * (tablet ? 0.34 : 0.30))
                          .clamp(tablet ? 110.0 : 84.0, tablet ? 148.0 : 112.0);
                      final hero = unlocked ? heroBudget : heroBudget * 0.72;
                      final heroIcon = hero * (unlocked ? 0.47 : 0.42);

                      return Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: tablet ? 14 : 10,
                                          vertical: tablet ? 7 : 5),
                                      decoration: BoxDecoration(
                                        gradient: unlocked
                                            ? LinearGradient(
                                                colors: [
                                                  Colors.white.withOpacity(0.35),
                                                  p.glow.withOpacity(0.3),
                                                ],
                                              )
                                            : null,
                                        color: unlocked
                                            ? null
                                            : Colors.black.withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(
                                          color: unlocked
                                              ? Colors.white.withOpacity(0.65)
                                              : Colors.white24,
                                        ),
                                      ),
                                      child: Text(
                                        'OBR ${p.label.toUpperCase()}',
                                        style: TextStyle(
                                          color: unlocked
                                              ? p.onCard
                                              : Colors.white38,
                                          fontWeight: FontWeight.w900,
                                          fontSize: tablet ? 13.5 : 11,
                                          letterSpacing: 1.0,
                                          shadows: unlocked
                                              ? [
                                                  Shadow(
                                                    color: p.cardBottom
                                                        .withOpacity(0.45),
                                                    blurRadius: 8,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (unlocked) ...[
                                      SizedBox(height: tablet ? 6 : 4),
                                      Text(
                                        _tagline,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: p.onCard,
                                          fontWeight: FontWeight.w900,
                                          fontSize: titleSize,
                                          height: 1.05,
                                          letterSpacing: -0.4,
                                          shadows: [
                                            Shadow(
                                              color: p.cardBottom
                                                  .withOpacity(0.45),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusPill(
                                unlocked: unlocked,
                                isCurrent: widget.isCurrent,
                                palette: p,
                                isTablet: tablet,
                              ),
                            ],
                          ),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Transform.scale(
                                      scale: unlocked
                                          ? (0.97 + 0.05 * breath)
                                          : 0.85,
                                      child: Container(
                                        width: hero,
                                        height: hero,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            colors: unlocked
                                                ? [
                                                    Colors.white
                                                        .withOpacity(0.55),
                                                    p.glow.withOpacity(0.25),
                                                    Colors.transparent,
                                                  ]
                                                : [
                                                    Colors.white
                                                        .withOpacity(0.08),
                                                    Colors.transparent,
                                                  ],
                                          ),
                                          border: Border.all(
                                            color: unlocked
                                                ? Colors.white.withOpacity(0.85)
                                                : Colors.white24,
                                            width: unlocked ? 2.8 : 1.2,
                                          ),
                                          boxShadow: unlocked
                                              ? [
                                                  BoxShadow(
                                                    color: p.glow.withOpacity(
                                                        0.8 * breath),
                                                    blurRadius: 28,
                                                    spreadRadius: 2,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Icon(
                                          unlocked
                                              ? _heroIcon
                                              : Icons.lock_rounded,
                                          size: heroIcon,
                                          color: unlocked
                                              ? p.onCard
                                              : Colors.white.withOpacity(0.35),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: tablet ? 10 : 8),
                                    if (unlocked)
                                      _PremiumSubTag(
                                        eyebrow: _subEyebrow,
                                        text: _subTag,
                                        palette: p,
                                        isTablet: tablet,
                                        fontSize: subSize,
                                      )
                                    else
                                      Text(
                                        'Grade masih terkunci',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontWeight: FontWeight.w700,
                                          fontSize: subSize,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (unlocked)
                            _UnlockedFooter(
                              palette: p,
                              isCurrent: widget.isCurrent,
                              statusPoints: widget.statusPoints,
                              rewardPoints: widget.rewardPoints,
                              format: _num,
                              isTablet: tablet,
                              compact: !tablet && h < 420,
                            )
                          else
                            _LockedFooter(
                              unlockAt: p.unlockAt,
                              pointsNeeded: widget.pointsNeeded,
                              format: _num,
                              isTablet: tablet,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UnlockedFoilBg extends StatelessWidget {
  const _UnlockedFoilBg({required this.palette, required this.shimmer});
  final MemberGradePalette palette;
  final double shimmer;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(p.cardTop, Colors.white, 0.12)!,
                p.cardTop,
                p.cardMid,
                p.cardBottom,
                Color.lerp(p.cardBottom, p.accent, 0.25)!,
              ],
              stops: const [0, 0.22, 0.5, 0.78, 1],
            ),
          ),
        ),
        // Moving foil sheen
        Transform.translate(
          offset: Offset((shimmer * 2 - 1) * 180, 0),
          child: Transform.rotate(
            angle: -0.55,
            child: Container(
              width: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.22),
                    Colors.white.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Soft top light
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                Colors.white.withOpacity(0.28),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LockedBg extends StatelessWidget {
  const _LockedBg({required this.palette});
  final MemberGradePalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(p.cardMid, const Color(0xFF2A2A2A), 0.7)!,
                const Color(0xFF151515),
                const Color(0xFF0C0C0C),
              ],
            ),
          ),
        ),
        Container(color: Colors.black.withOpacity(0.35)),
        // Faint watermark of grade color
        Center(
          child: Icon(
            Icons.lock_outline_rounded,
            size: 140,
            color: Colors.white.withOpacity(0.04),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.unlocked,
    required this.isCurrent,
    required this.palette,
    required this.isTablet,
  });

  final bool unlocked;
  final bool isCurrent;
  final MemberGradePalette palette;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final label = !unlocked
        ? 'TERKUNCI'
        : isCurrent
            ? 'AKTIF'
            : 'TERBUKA';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        gradient: unlocked
            ? LinearGradient(
                colors: isCurrent
                    ? [Colors.white, p.glow]
                    : [p.glow, Colors.white.withOpacity(0.85)],
              )
            : null,
        color: unlocked ? null : Colors.black54,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: unlocked ? Colors.white : Colors.white24,
          width: unlocked ? 1.2 : 1,
        ),
        boxShadow: unlocked
            ? [
                BoxShadow(
                  color: p.glow.withOpacity(0.55),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: unlocked ? p.cardBottom : Colors.white54,
          fontWeight: FontWeight.w900,
          fontSize: isTablet ? 11 : 10,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _PremiumSubTag extends StatelessWidget {
  const _PremiumSubTag({
    required this.eyebrow,
    required this.text,
    required this.palette,
    required this.isTablet,
    required this.fontSize,
  });

  final String eyebrow;
  final String text;
  final MemberGradePalette palette;
  final bool isTablet;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      constraints: BoxConstraints(maxWidth: isTablet ? 320 : 260),
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 16 : 13,
        vertical: isTablet ? 10 : 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.22),
            p.glow.withOpacity(0.14),
            Colors.white.withOpacity(0.08),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.42),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: p.glow.withOpacity(0.35),
            blurRadius: 16,
            spreadRadius: -2,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.glow.withOpacity(0.95),
              fontWeight: FontWeight.w800,
              fontSize: isTablet ? 9.5 : 8.5,
              letterSpacing: 2.4,
              height: 1.1,
              shadows: [
                Shadow(
                  color: p.glow.withOpacity(0.55),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          SizedBox(height: isTablet ? 5 : 4),
          Text(
            '✧  $text  ✧',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.onCard,
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
              letterSpacing: 0.35,
              height: 1.25,
              shadows: [
                Shadow(
                  color: p.cardBottom.withOpacity(0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 1),
                ),
                Shadow(
                  color: p.glow.withOpacity(0.35),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerStar extends StatelessWidget {
  const _CornerStar({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.star_rounded, size: size, color: color.withOpacity(0.85));
  }
}

class _UnlockedFooter extends StatelessWidget {
  const _UnlockedFooter({
    required this.palette,
    required this.isCurrent,
    required this.statusPoints,
    required this.rewardPoints,
    required this.format,
    required this.isTablet,
    this.compact = false,
  });

  final MemberGradePalette palette;
  final bool isCurrent;
  final int statusPoints;
  final int rewardPoints;
  final NumberFormat format;
  final bool isTablet;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final pad = isTablet ? 16.0 : (compact ? 10.0 : 12.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.42),
                p.glow.withOpacity(0.38),
                Colors.white.withOpacity(0.22),
              ],
            ),
            borderRadius: BorderRadius.circular(compact ? 16 : 20),
            border: Border.all(
              color: Colors.white.withOpacity(0.7),
              width: 1.4,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isCurrent
                          ? 'Grade aktif kamu'
                          : '${p.label} sudah terbuka',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.cardBottom,
                        fontWeight: FontWeight.w900,
                        fontSize: isTablet ? 17 : (compact ? 13.5 : 14.5),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (!compact)
                    Container(
                      padding: EdgeInsets.all(isTablet ? 10 : 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Colors.white, p.glow],
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: isTablet ? 20 : 16,
                        color: p.cardBottom,
                      ),
                    ),
                ],
              ),
              SizedBox(height: isTablet ? 12 : (compact ? 6 : 8)),
              Row(
                children: [
                  Expanded(
                    child: _StatChip(
                      label: 'Status',
                      value: format.format(statusPoints),
                      palette: p,
                      isTablet: isTablet,
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  Expanded(
                    child: _StatChip(
                      label: 'Reward',
                      value: format.format(rewardPoints),
                      palette: p,
                      isTablet: isTablet,
                      compact: compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.palette,
    required this.isTablet,
    this.compact = false,
  });

  final String label;
  final String value;
  final MemberGradePalette palette;
  final bool isTablet;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 14 : (compact ? 8 : 10),
        vertical: isTablet ? 12 : (compact ? 6 : 8),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        border: Border.all(color: Colors.white.withOpacity(0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: p.accent,
              fontSize: isTablet ? 11 : (compact ? 9 : 10),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: compact ? 1 : 2),
          Text(
            value,
            style: TextStyle(
              color: p.cardBottom,
              fontSize: isTablet ? 20 : (compact ? 15 : 17),
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedFooter extends StatelessWidget {
  const _LockedFooter({
    required this.unlockAt,
    required this.pointsNeeded,
    required this.format,
    required this.isTablet,
  });

  final int unlockAt;
  final int pointsNeeded;
  final NumberFormat format;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 16 : 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded,
                  color: Colors.white24, size: isTablet ? 22 : 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Butuh ${format.format(unlockAt)} Status Poin',
                  style: TextStyle(
                    color: Colors.white38,
                    fontWeight: FontWeight.w700,
                    fontSize: isTablet ? 15.5 : 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 10 : 8),
          Text(
            '${format.format(pointsNeeded)} poin lagi untuk membuka',
            style: TextStyle(
              color: Colors.white.withOpacity(0.28),
              fontSize: isTablet ? 13.5 : 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class GradeWahPainter extends CustomPainter {
  GradeWahPainter({
    required this.grade,
    required this.glow,
    required this.accent,
    required this.t,
  });

  final MemberGrade grade;
  final Color glow;
  final Color accent;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.42);
    switch (grade) {
      case MemberGrade.basic:
        _basic(canvas, c);
        break;
      case MemberGrade.silver:
        _silver(canvas, size, c);
        break;
      case MemberGrade.gold:
        _gold(canvas, c);
        break;
      case MemberGrade.platinum:
        _platinum(canvas, c);
        break;
      case MemberGrade.diamond:
        _diamond(canvas, c);
        break;
    }
  }

  void _basic(Canvas canvas, Offset c) {
    for (var i = 0; i < 4; i++) {
      final phase = (t + i * 0.22) % 1.0;
      canvas.drawCircle(
        c,
        40 + phase * 100,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = glow.withOpacity((1 - phase) * 0.5),
      );
    }
  }

  void _silver(Canvas canvas, Size size, Offset c) {
    final band = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-1 + t * 2, -1),
        end: Alignment(t * 2, 1),
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.32),
          Colors.transparent,
        ],
        stops: const [0.35, 0.5, 0.65],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, band);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        c,
        44.0 + i * 18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = glow.withOpacity(0.4),
      );
    }
  }

  void _gold(Canvas canvas, Offset c) {
    for (var i = 0; i < 16; i++) {
      final a = t * math.pi * 2 + i * (math.pi * 2 / 16);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a) * 130, c.dy + math.sin(a) * 130);
      canvas.drawPath(
        path,
        Paint()
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..shader = LinearGradient(
            colors: [
              const Color(0xFFFFE08A).withOpacity(0.8),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: c, radius: 130)),
      );
    }
  }

  void _platinum(Canvas canvas, Offset c) {
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * (math.pi * 2 / 6) + t * 0.4;
      final p = c + Offset(math.cos(a), math.sin(a)) * 80;
      if (i == 0) {
        hex.moveTo(p.dx, p.dy);
      } else {
        hex.lineTo(p.dx, p.dy);
      }
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.white.withOpacity(0.75),
    );
    for (var i = 0; i < 6; i++) {
      final a = t * math.pi * 2 + i * (math.pi * 2 / 6);
      final p = c + Offset(math.cos(a), math.sin(a)) * 98;
      canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
    }
  }

  void _diamond(Canvas canvas, Offset c) {
    void hex(double r, double spin, Color col) {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final a = -math.pi / 2 + i * (math.pi * 2 / 6) + spin;
        final p = c + Offset(math.cos(a), math.sin(a)) * r;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = col,
      );
    }

    hex(88, t * 0.5, const Color(0xFFC9ECFF));
    hex(58, -t * 0.7, const Color(0xFF6EC6FF).withOpacity(0.8));
    for (var i = 0; i < 8; i++) {
      final a = t * math.pi * 2 + i * (math.pi / 4);
      final p = c + Offset(math.cos(a), math.sin(a)) * 105;
      canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant GradeWahPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.grade != grade;
}
