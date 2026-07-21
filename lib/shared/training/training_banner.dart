import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'training_mode.dart';

/// Persistent banner shown only while Training Mode is active.
/// Same live UI underneath — this is the only intentional visual difference.
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
          color: const Color(0xFFB45309),
          elevation: 2,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.school_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'training_banner_title'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'training_banner_subtitle'.tr(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
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
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black26,
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

/// Confirm dialogs for enter / exit training (identical feature scope; ephemeral data).
class TrainingModeDialogs {
  TrainingModeDialogs._();

  static Future<bool> confirmEnter(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('training_enter_title'.tr()),
        content: Text('training_enter_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('sop_batal'.tr()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB45309),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('training_btn_enter'.tr()),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static Future<bool> confirmExit(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('training_exit_title'.tr()),
        content: Text('training_exit_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('sop_batal'.tr()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('training_btn_exit_confirm'.tr()),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
