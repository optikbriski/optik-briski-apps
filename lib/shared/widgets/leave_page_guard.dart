// ignore_for_file: deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Hasil pilihan dialog keluar halaman.
enum LeavePageAction {
  /// Tetap di halaman.
  cancel,

  /// Keluar tanpa menyimpan (buang editan / buang draft).
  leaveDiscard,

  /// Keluar setelah menyimpan (editan / draft).
  leaveSave,
}

/// Helper dialog konfirmasi keluar halaman (edit / view / POS draft).
class LeavePageGuard {
  const LeavePageGuard._();

  /// Halaman edit umum:
  /// - [hasEdits] true → dialog + konfirmasi kedua (sedang kerja)
  /// - [hasEdits] false → langsung boleh keluar (tidak sedang edit)
  static Future<LeavePageAction?> confirm(
    BuildContext context, {
    required bool hasEdits,
  }) async {
    // Hanya ganggu user kalau sedang mengerjakan / mengedit sesuatu.
    if (!hasEdits) return LeavePageAction.leaveDiscard;

    final action = await _show(
      context,
      titleKey: 'leave_title_edits',
      messageKey: 'leave_msg_edits',
      icon: Icons.edit_note_rounded,
      actions: const [
        _ActionSpec(
          LeavePageAction.cancel,
          'leave_cancel',
          subtitleKey: 'leave_cancel_sub',
          tone: _ActionTone.neutral,
          icon: Icons.close_rounded,
        ),
        _ActionSpec(
          LeavePageAction.leaveDiscard,
          'leave_discard_edits',
          subtitleKey: 'leave_discard_edits_sub',
          tone: _ActionTone.danger,
          icon: Icons.delete_outline_rounded,
        ),
        _ActionSpec(
          LeavePageAction.leaveSave,
          'leave_save_edits',
          subtitleKey: 'leave_save_edits_sub',
          tone: _ActionTone.primary,
          icon: Icons.save_rounded,
        ),
      ],
    );
    if (!context.mounted) return LeavePageAction.cancel;
    return _requireLeaveSure(context, action);
  }

  /// POS: 3 pilihan draft; setiap keluar wajib konfirmasi kedua.
  static Future<LeavePageAction?> confirmPos(BuildContext context) async {
    final action = await _show(
      context,
      titleKey: 'leave_title_pos',
      messageKey: 'leave_msg_pos',
      icon: Icons.point_of_sale_rounded,
      actions: const [
        _ActionSpec(
          LeavePageAction.cancel,
          'leave_cancel',
          subtitleKey: 'leave_cancel_sub',
          tone: _ActionTone.neutral,
          icon: Icons.close_rounded,
        ),
        _ActionSpec(
          LeavePageAction.leaveDiscard,
          'pos_leave_discard_draft',
          subtitleKey: 'pos_leave_discard_draft_sub',
          tone: _ActionTone.danger,
          icon: Icons.restart_alt_rounded,
        ),
        _ActionSpec(
          LeavePageAction.leaveSave,
          'pos_leave_save_draft',
          subtitleKey: 'pos_leave_save_draft_sub',
          tone: _ActionTone.primary,
          icon: Icons.bookmark_added_rounded,
        ),
      ],
    );
    if (!context.mounted) return LeavePageAction.cancel;
    return _requireLeaveSure(
      context,
      action,
      discardTitleKey: 'pos_discard_sure_title',
      discardMessageKey: 'pos_discard_sure_msg',
      saveTitleKey: 'pos_save_leave_sure_title',
      saveMessageKey: 'pos_save_leave_sure_msg',
    );
  }

  /// HID / incidental QR that would navigate away from the current page.
  static Future<LeavePageAction?> confirmLeaveToRunQr(
    BuildContext context, {
    bool offerSave = false,
  }) async {
    if (offerSave) {
      final action = await _show(
        context,
        titleKey: 'leave_to_run_qr_title',
        messageKey: 'leave_to_run_qr_msg',
        icon: Icons.qr_code_scanner_rounded,
        actions: const [
          _ActionSpec(
            LeavePageAction.cancel,
            'leave_cancel',
            subtitleKey: 'leave_cancel_sub',
            tone: _ActionTone.neutral,
            icon: Icons.close_rounded,
          ),
          _ActionSpec(
            LeavePageAction.leaveDiscard,
            'leave_to_run_qr_confirm',
            subtitleKey: 'leave_to_run_qr_confirm_sub',
            tone: _ActionTone.danger,
            icon: Icons.exit_to_app_rounded,
          ),
          _ActionSpec(
            LeavePageAction.leaveSave,
            'leave_save_then_run_qr',
            subtitleKey: 'leave_save_then_run_qr_sub',
            tone: _ActionTone.primary,
            icon: Icons.save_rounded,
          ),
        ],
      );
      if (!context.mounted) return LeavePageAction.cancel;
      return _requireLeaveSure(context, action);
    }
    final action = await _show(
      context,
      titleKey: 'leave_to_run_qr_title',
      messageKey: 'leave_to_run_qr_msg',
      icon: Icons.qr_code_scanner_rounded,
      actions: const [
        _ActionSpec(
          LeavePageAction.cancel,
          'leave_cancel',
          subtitleKey: 'leave_cancel_sub',
          tone: _ActionTone.neutral,
          icon: Icons.close_rounded,
        ),
        _ActionSpec(
          LeavePageAction.leaveDiscard,
          'leave_to_run_qr_confirm',
          subtitleKey: 'leave_to_run_qr_confirm_sub',
          tone: _ActionTone.primary,
          icon: Icons.exit_to_app_rounded,
        ),
      ],
    );
    if (!context.mounted) return LeavePageAction.cancel;
    return _requireLeaveSure(context, action);
  }

  /// Konfirmasi kedua setiap kali user memilih keluar (buang / simpan).
  static Future<LeavePageAction?> _requireLeaveSure(
    BuildContext context,
    LeavePageAction? action, {
    String discardTitleKey = 'leave_discard_sure_title',
    String discardMessageKey = 'leave_discard_sure_msg',
    String saveTitleKey = 'leave_save_sure_title',
    String saveMessageKey = 'leave_save_sure_msg',
  }) async {
    if (action == null || action == LeavePageAction.cancel) return action;
    if (!context.mounted) return LeavePageAction.cancel;

    final isDiscard = action == LeavePageAction.leaveDiscard;
    final sure = await _show(
      context,
      titleKey: isDiscard ? discardTitleKey : saveTitleKey,
      messageKey: isDiscard ? discardMessageKey : saveMessageKey,
      icon: isDiscard
          ? Icons.warning_amber_rounded
          : Icons.help_outline_rounded,
      actions: [
        const _ActionSpec(
          LeavePageAction.cancel,
          'leave_discard_sure_no',
          subtitleKey: 'leave_discard_sure_no_sub',
          tone: _ActionTone.neutral,
          icon: Icons.arrow_back_rounded,
        ),
        _ActionSpec(
          action,
          isDiscard ? 'leave_discard_sure_yes' : 'leave_save_sure_yes',
          subtitleKey: isDiscard
              ? 'leave_discard_sure_yes_sub'
              : 'leave_save_sure_yes_sub',
          tone: isDiscard ? _ActionTone.danger : _ActionTone.primary,
          icon: isDiscard
              ? Icons.delete_forever_rounded
              : Icons.check_circle_outline_rounded,
        ),
      ],
    );
    if (sure == action) return action;
    return LeavePageAction.cancel;
  }

  /// Intercept back / system pop. Panggil [onSave] jika user pilih simpan.
  static Future<bool> handlePop(
    BuildContext context, {
    required bool hasEdits,
    Future<void> Function()? onSave,
  }) async {
    final action = await confirm(context, hasEdits: hasEdits);
    switch (action) {
      case LeavePageAction.cancel:
      case null:
        return false;
      case LeavePageAction.leaveDiscard:
        return true;
      case LeavePageAction.leaveSave:
        if (onSave != null) await onSave();
        return true;
    }
  }

  static Future<LeavePageAction?> _show(
    BuildContext context, {
    required String titleKey,
    required String messageKey,
    required IconData icon,
    required List<_ActionSpec> actions,
  }) {
    return showGeneralDialog<LeavePageAction>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.62),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1A2740),
                        Color(0xFF111827),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0EA5A4).withOpacity(0.14),
                            border: Border.all(
                              color: const Color(0xFF2DD4BF).withOpacity(0.35),
                            ),
                          ),
                          child: Icon(icon,
                              color: const Color(0xFF5EEAD4), size: 26),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          titleKey.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: -0.2,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          messageKey.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.62),
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final spec in actions) ...[
                          _PremiumActionTile(spec: spec),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

enum _ActionTone { neutral, danger, primary }

class _ActionSpec {
  const _ActionSpec(
    this.action,
    this.labelKey, {
    required this.subtitleKey,
    required this.tone,
    required this.icon,
  });

  final LeavePageAction action;
  final String labelKey;
  final String subtitleKey;
  final _ActionTone tone;
  final IconData icon;
}

class _PremiumActionTile extends StatelessWidget {
  const _PremiumActionTile({required this.spec});
  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    late final Color accent;
    late final Color bg;
    late final Color border;
    switch (spec.tone) {
      case _ActionTone.neutral:
        accent = Colors.white70;
        bg = Colors.white.withOpacity(0.04);
        border = Colors.white.withOpacity(0.08);
      case _ActionTone.danger:
        accent = const Color(0xFFFBBF24);
        bg = const Color(0xFFF59E0B).withOpacity(0.08);
        border = const Color(0xFFFBBF24).withOpacity(0.28);
      case _ActionTone.primary:
        accent = const Color(0xFF2DD4BF);
        bg = const Color(0xFF0D9488).withOpacity(0.14);
        border = const Color(0xFF2DD4BF).withOpacity(0.35);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, spec.action),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withOpacity(0.14),
                  ),
                  child: Icon(spec.icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.labelKey.tr(),
                        style: TextStyle(
                          color: accent == Colors.white70
                              ? Colors.white
                              : accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spec.subtitleKey.tr(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.52),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
