import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'shift_auto_assign.dart';
import 'sop_daily_service.dart';
import 'sop_score.dart';
import '../theme.dart';

/// Panel skor SOP ±25 + aksi komponen cabang.
class SopScorePanel extends StatelessWidget {
  const SopScorePanel({
    super.key,
    required this.state,
    required this.score,
    required this.layer,
    required this.isPagi,
    required this.busy,
    required this.onAddStory,
    required this.onCompleteDisplay,
    required this.onClaimSapu,
    required this.onClaimStok,
    required this.onSync,
  });

  final SopBranchState? state;
  final SopScoreResult? score;
  final OfficeLayer layer;
  final bool isPagi;
  final bool busy;
  final VoidCallback onAddStory;
  final ValueChanged<int> onCompleteDisplay;
  final VoidCallback onClaimSapu;
  final VoidCallback onClaimStok;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final sc = score;
    final poin = sc?.poin ?? 0;
    final fatal = sc?.fatalStory == true;
    final libur = sc?.liburOrInactive == true;
    final story = s?.storyCount ?? 0;
    final dispDone = s?.displayDone ?? 0;
    final dispReq = s?.displayRequired ?? SopScore.displaySlotsDefault;
    final sapu = s?.sapuDone == true;
    final stok = s?.stokDone == true;
    final doneSlots = s?.completedDisplaySlots ?? const <int>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: OptikKaryawanTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: fatal
                  ? OptikKaryawanTokens.danger.withOpacity(0.45)
                  : OptikKaryawanTokens.cyan.withOpacity(0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'sop_score_judul'.tr(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: OptikKaryawanTokens.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                libur
                    ? 'sop_score_libur'.tr()
                    : fatal
                        ? 'sop_score_fatal'.tr()
                        : 'sop_score_poin'.tr(namedArgs: {
                            'poin': poin >= 0 ? '+$poin' : '$poin',
                            'p': ((sc?.p ?? 0) * 100).round().toString(),
                          }),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: fatal
                      ? OptikKaryawanTokens.danger
                      : OptikKaryawanTokens.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                layer == OfficeLayer.front
                    ? (isPagi
                        ? 'sop_score_layer_front_pagi'.tr()
                        : 'sop_score_layer_front_siang'.tr())
                    : (isPagi
                        ? 'sop_score_layer_back_pagi'.tr()
                        : 'sop_score_layer_back_siang'.tr()),
                style: TextStyle(
                  color: OptikKaryawanTokens.muted.withOpacity(0.95),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _row(
          title: 'sop_comp_story'.tr(namedArgs: {
            'n': '$story',
            'target': '${SopScore.storyTarget}',
          }),
          done: story >= SopScore.storyTarget,
          actionLabel: layer == OfficeLayer.front ? 'sop_btn_story'.tr() : null,
          onAction: layer == OfficeLayer.front && !busy ? onAddStory : null,
        ),
        if (layer == OfficeLayer.front) ...[
          const SizedBox(height: 8),
          _row(
            title: 'sop_comp_display'.tr(namedArgs: {
              'n': '$dispDone',
              'target': '$dispReq',
            }),
            done: dispDone >= dispReq,
            child: Wrap(
              spacing: 6,
              children: List.generate(dispReq, (i) {
                final slot = i + 1;
                final ok = doneSlots.contains(slot);
                return ActionChip(
                  label: Text(ok ? '✓ $slot' : '$slot'),
                  onPressed: busy || ok
                      ? null
                      : () => onCompleteDisplay(slot),
                );
              }),
            ),
          ),
        ],
        if (layer == OfficeLayer.back) ...[
          const SizedBox(height: 8),
          _row(
            title: 'sop_comp_stok'.tr(),
            done: stok,
            actionLabel: stok ? null : 'sop_btn_stok'.tr(),
            onAction: !stok && !busy ? onClaimStok : null,
          ),
        ],
        if (isPagi) ...[
          const SizedBox(height: 8),
          _row(
            title: 'sop_comp_sapu'.tr(),
            done: sapu,
            actionLabel: sapu ? null : 'sop_btn_sapu'.tr(),
            onAction: !sapu && !busy ? onClaimSapu : null,
          ),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: busy ? null : onSync,
          style: FilledButton.styleFrom(
            backgroundColor: OptikKaryawanTokens.seasideMid,
            foregroundColor: OptikKaryawanTokens.ink,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text('sop_btn_sync_skor'.tr()),
        ),
      ],
    );
  }

  Widget _row({
    required String title,
    required bool done,
    String? actionLabel,
    VoidCallback? onAction,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OptikKaryawanTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? OptikKaryawanTokens.success.withOpacity(0.35)
              : OptikKaryawanTokens.cyan.withOpacity(0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: done
                    ? OptikKaryawanTokens.success
                    : OptikKaryawanTokens.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: OptikKaryawanTokens.ink,
                    fontSize: 13,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 8),
            child,
          ],
        ],
      ),
    );
  }
}
