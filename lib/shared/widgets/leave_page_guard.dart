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
  /// - [hasEdits] true → Batalkan / Keluar tanpa save / Keluar dan save
  /// - [hasEdits] false → Batalkan / Keluar dari halaman ini
  static Future<LeavePageAction?> confirm(
    BuildContext context, {
    required bool hasEdits,
  }) {
    if (hasEdits) {
      return _show(
        context,
        titleKey: 'leave_title_edits',
        actions: const [
          _ActionSpec(LeavePageAction.cancel, 'leave_cancel'),
          _ActionSpec(LeavePageAction.leaveDiscard, 'leave_discard_edits'),
          _ActionSpec(LeavePageAction.leaveSave, 'leave_save_edits'),
        ],
      );
    }
    return _show(
      context,
      titleKey: 'leave_title_view',
      actions: const [
        _ActionSpec(LeavePageAction.cancel, 'leave_cancel'),
        _ActionSpec(LeavePageAction.leaveDiscard, 'leave_view_exit'),
      ],
    );
  }

  /// POS: selalu 3 pilihan draft.
  static Future<LeavePageAction?> confirmPos(BuildContext context) {
    return _show(
      context,
      titleKey: 'leave_title_pos',
      actions: const [
        _ActionSpec(LeavePageAction.cancel, 'leave_cancel'),
        _ActionSpec(LeavePageAction.leaveDiscard, 'pos_leave_discard_draft'),
        _ActionSpec(LeavePageAction.leaveSave, 'pos_leave_save_draft'),
      ],
    );
  }

  /// HID / incidental QR that would navigate away from the current page.
  /// - [offerSave] false → Batalkan / Keluar & jalankan QR
  /// - [offerSave] true → + Simpan dulu lalu jalankan QR
  static Future<LeavePageAction?> confirmLeaveToRunQr(
    BuildContext context, {
    bool offerSave = false,
  }) {
    if (offerSave) {
      return _show(
        context,
        titleKey: 'leave_to_run_qr_title',
        actions: const [
          _ActionSpec(LeavePageAction.cancel, 'leave_cancel'),
          _ActionSpec(LeavePageAction.leaveDiscard, 'leave_to_run_qr_confirm'),
          _ActionSpec(LeavePageAction.leaveSave, 'leave_save_then_run_qr'),
        ],
      );
    }
    return _show(
      context,
      titleKey: 'leave_to_run_qr_title',
      actions: const [
        _ActionSpec(LeavePageAction.cancel, 'leave_cancel'),
        _ActionSpec(LeavePageAction.leaveDiscard, 'leave_to_run_qr_confirm'),
      ],
    );
  }

  /// Intercept back / system pop. Panggil [onSave] jika user pilih simpan.
  /// Return `true` jika boleh keluar (caller harus `Navigator.pop` jika perlu).
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
    required List<_ActionSpec> actions,
  }) {
    return showDialog<LeavePageAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          titleKey.tr(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _LeaveActionButton(spec: actions[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionSpec {
  const _ActionSpec(this.action, this.labelKey);
  final LeavePageAction action;
  final String labelKey;
}

class _LeaveActionButton extends StatelessWidget {
  const _LeaveActionButton({required this.spec});
  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    final isCancel = spec.action == LeavePageAction.cancel;
    final isSave = spec.action == LeavePageAction.leaveSave;
    final Color fg = isCancel
        ? Colors.white70
        : isSave
            ? Colors.greenAccent
            : Colors.orangeAccent;

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: fg.withOpacity(0.45)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        alignment: Alignment.centerLeft,
      ),
      onPressed: () => Navigator.pop(context, spec.action),
      child: Text(
        spec.labelKey.tr(),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}
