import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'training_mode.dart';

/// Persistent banner shown only while Training Mode is active.
class TrainingBanner extends StatelessWidget {
  const TrainingBanner({
    super.key,
    this.onExitRequested,
  });

  /// Called when user taps exit; parent should confirm then call [TrainingMode.exit].
  final VoidCallback? onExitRequested;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TrainingMode.instance,
      builder: (context, _) {
        if (!TrainingMode.instance.isActive) {
          return const SizedBox.shrink();
        }
        return Material(
          color: OptikAdminTokens.training,
          elevation: 2,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.school_rounded,
                      color: OptikAdminTokens.snow, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'training_banner_title'.tr(),
                          style: const TextStyle(
                            color: OptikAdminTokens.snow,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'training_banner_subtitle'.tr(),
                          style: TextStyle(
                            color: OptikAdminTokens.snow.withOpacity(0.9),
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onExitRequested,
                    style: TextButton.styleFrom(
                      foregroundColor: OptikAdminTokens.snow,
                      backgroundColor: OptikAdminTokens.bg.withOpacity(0.26),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'training_btn_exit'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Kartu dialog latihan: kanvas terang, teks gelap.
/// Dipakai Admin Optik dan Admin Rekasa (satu overlay).
abstract final class TrainingDialogSkin {
  static const Color surface = OptikAdminTokens.card;
  static const Color title = OptikAdminTokens.navy;
  static const Color body = OptikAdminTokens.textSecondary;
  static const Color muted = OptikAdminTokens.slate;
  static const Color accent = OptikAdminTokens.training;
  static const Color accentSoft = OptikAdminTokens.trainingSoft;
  static const Color chipFill = OptikAdminTokens.bgMid;
  static const Color onAccent = OptikAdminTokens.snow;
}

/// Premium confirm + enter-loading experience for Training Mode.
class TrainingModeDialogs {
  TrainingModeDialogs._();

  static const _amber = TrainingDialogSkin.accent;
  static const _amberSoft = TrainingDialogSkin.accentSoft;

  static const _moduleKeys = <String>[
    'training_mod_pos',
    'training_mod_logistics',
    'training_mod_history',
    'training_mod_warranty',
    'training_mod_finance',
    'training_mod_master',
  ];

  static const _moduleIcons = <IconData>[
    Icons.point_of_sale_rounded,
    Icons.local_shipping_rounded,
    Icons.history_edu_rounded,
    Icons.verified_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.dataset_rounded,
  ];

  /// Premium enter confirmation. Returns `true` if user confirms.
  static Future<bool> confirmEnter(BuildContext context) async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: OptikAdminTokens.navy.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, sec) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (ctx, anim, sec, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: _EnterConfirmSheet(
              amber: _amber,
              amberSoft: _amberSoft,
              moduleKeys: _moduleKeys,
              moduleIcons: _moduleIcons,
            ),
          ),
        );
      },
    );
    return ok == true;
  }

  /// Full-screen loading (≥2s) while [enterFn] prepares the sandbox.
  static Future<void> runEnterWithLoading(
    BuildContext context,
    Future<void> Function() enterFn,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'training-loading',
        barrierColor: OptikAdminTokens.navy.withOpacity(0.72),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, a, b) => const SizedBox.shrink(),
        transitionBuilder: (ctx, anim, sec, child) {
          return FadeTransition(
            opacity: anim,
            child: const _EnteringLoadingOverlay(),
          );
        },
      ),
    );

    try {
      await Future.wait<void>([
        enterFn(),
        Future<void>.delayed(const Duration(seconds: 2)),
      ]);
    } finally {
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  static Future<bool> confirmExit(BuildContext context) async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: OptikAdminTokens.navy.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, a, b) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, sec, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: _TrainingDialogCard(
              maxWidth: 420,
              accentBorder: OptikAdminTokens.danger,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: OptikAdminTokens.danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.delete_forever_rounded,
                          color: OptikAdminTokens.danger,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'training_exit_title'.tr(),
                          style: const TextStyle(
                            color: TrainingDialogSkin.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _TrainingBodyText('training_exit_body'),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            foregroundColor: TrainingDialogSkin.muted,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text('sop_batal'.tr()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OptikAdminTokens.danger,
                            foregroundColor: TrainingDialogSkin.onAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            'training_btn_exit_confirm'.tr(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
      },
    );
    return ok == true;
  }
}

class _TrainingDialogCard extends StatelessWidget {
  const _TrainingDialogCard({
    required this.child,
    this.maxWidth = 460,
    this.accentBorder,
  });

  final Widget child;
  final double maxWidth;
  final Color? accentBorder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              color: TrainingDialogSkin.surface,
              elevation: 10,
              shadowColor: OptikAdminTokens.navy.withOpacity(0.22),
              borderRadius: BorderRadius.circular(22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: (accentBorder ?? TrainingDialogSkin.accent)
                        .withOpacity(0.28),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrainingBodyText extends StatelessWidget {
  const _TrainingBodyText(this.keyName);

  final String keyName;

  @override
  Widget build(BuildContext context) {
    return Text(
      keyName.tr(),
      style: const TextStyle(
        color: TrainingDialogSkin.body,
        fontSize: 13.5,
        height: 1.45,
      ),
    );
  }
}

class _EnterConfirmSheet extends StatelessWidget {
  const _EnterConfirmSheet({
    required this.amber,
    required this.amberSoft,
    required this.moduleKeys,
    required this.moduleIcons,
  });

  final Color amber;
  final Color amberSoft;
  final List<String> moduleKeys;
  final List<IconData> moduleIcons;

  @override
  Widget build(BuildContext context) {
    return _TrainingDialogCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [amberSoft, amber],
                  ),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: TrainingDialogSkin.onAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'training_enter_eyebrow'.tr(),
                      style: TextStyle(
                        color: amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'training_enter_title'.tr(),
                      style: const TextStyle(
                        color: TrainingDialogSkin.title,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _TrainingBodyText('training_enter_lead'),
          const SizedBox(height: 16),
          Text(
            'training_enter_modules_label'.tr(),
            style: const TextStyle(
              color: TrainingDialogSkin.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < moduleKeys.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: TrainingDialogSkin.chipFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: OptikAdminTokens.lineStrong,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(moduleIcons[i], size: 15, color: amber),
                      const SizedBox(width: 6),
                      Text(
                        moduleKeys[i].tr(),
                        style: const TextStyle(
                          color: TrainingDialogSkin.title,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: amber.withOpacity(0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_moon_rounded, color: amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'training_enter_safe_note'.tr(),
                    style: const TextStyle(
                      color: TrainingDialogSkin.body,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'training_enter_wipe_note'.tr(),
            style: const TextStyle(
              color: TrainingDialogSkin.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    foregroundColor: TrainingDialogSkin.muted,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('sop_batal'.tr()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: amber,
                    foregroundColor: TrainingDialogSkin.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    'training_btn_enter'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
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

class _EnteringLoadingOverlay extends StatefulWidget {
  const _EnteringLoadingOverlay();

  @override
  State<_EnteringLoadingOverlay> createState() =>
      _EnteringLoadingOverlayState();
}

class _EnteringLoadingOverlayState extends State<_EnteringLoadingOverlay>
    with SingleTickerProviderStateMixin {
  static const _steps = <String>[
    'training_loading_step_1',
    'training_loading_step_2',
    'training_loading_step_3',
  ];

  late final AnimationController _pulse;
  int _step = 0;
  Timer? _stepTimer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _stepTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) return;
      setState(() => _step = (_step + 1) % _steps.length);
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _TrainingDialogCard(
      maxWidth: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = _pulse.value;
              return Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color.lerp(
                        TrainingDialogSkin.accentSoft,
                        TrainingDialogSkin.accent,
                        t,
                      )!,
                      TrainingDialogSkin.accent,
                    ],
                  ),
                ),
                child: child,
              );
            },
            child: const Icon(
              Icons.school_rounded,
              color: TrainingDialogSkin.onAccent,
              size: 34,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'training_loading_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TrainingDialogSkin.title,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Text(
              _steps[_step].tr(),
              key: ValueKey(_step),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TrainingDialogSkin.muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: OptikAdminTokens.ice.withOpacity(0.45),
              color: TrainingDialogSkin.accent,
            ),
          ),
        ],
      ),
    );
  }
}
