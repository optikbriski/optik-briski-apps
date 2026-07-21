import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'training_data_client.dart';
import 'training_mode.dart';
import '../theme.dart';

/// Simulated pusat decision in Training Mode only.
enum TrainingApprovalOutcome {
  /// Pusat menerima / menyetujui.
  approved,

  /// Pusat menolak.
  rejected,

  /// Biarkan menunggu (status pending / OPEN).
  pending,
}

/// Result from [TrainingApprovalSimulator.show].
class TrainingApprovalResult {
  const TrainingApprovalResult({
    required this.outcome,
    this.note,
  });

  final TrainingApprovalOutcome outcome;

  /// Optional rejection / reviewer note (useful when [outcome] is rejected).
  final String? note;
}

/// Training-only control: after a request would wait for pusat, the trainee
/// picks the outcome locally (sandbox). Never shown in live mode.
class TrainingApprovalSimulator {
  TrainingApprovalSimulator._();

  /// Shows the simulator only when [TrainingMode.isActive].
  /// Returns `null` if training is off, the sheet is dismissed, or [context]
  /// is unmounted.
  static Future<TrainingApprovalResult?> showIfTraining(
    BuildContext context, {
    String? body,
  }) async {
    if (!TrainingMode.instance.isActive) return null;
    if (!context.mounted) return null;
    return show(context, body: body);
  }

  /// Always shows the sheet (caller must gate on training).
  static Future<TrainingApprovalResult?> show(
    BuildContext context, {
    String? body,
  }) {
    return showModalBottomSheet<TrainingApprovalResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TrainingApprovalSheet(body: body),
    );
  }

  /// Live-style status string for pengaduan sandbox rows.
  /// Live schema: OPEN | DONE; REJECTED is training-only for “ditolak”.
  static String pengaduanStatus(TrainingApprovalOutcome outcome) {
    switch (outcome) {
      case TrainingApprovalOutcome.approved:
        return 'DONE';
      case TrainingApprovalOutcome.rejected:
        return 'REJECTED';
      case TrainingApprovalOutcome.pending:
        return 'OPEN';
    }
  }

  /// Live-style status for jadwal_pengajuan.
  static String jadwalPengajuanStatus(TrainingApprovalOutcome outcome) {
    switch (outcome) {
      case TrainingApprovalOutcome.approved:
        return 'APPROVED';
      case TrainingApprovalOutcome.rejected:
        return 'REJECTED';
      case TrainingApprovalOutcome.pending:
        return 'PENDING';
    }
  }

  /// Live-style status for pending_requests (cabang → pusat RO).
  /// Approve maps to PREPARING — same as live HQ approve flow.
  static String requestOrderStatus(TrainingApprovalOutcome outcome) {
    switch (outcome) {
      case TrainingApprovalOutcome.approved:
        return 'PREPARING';
      case TrainingApprovalOutcome.rejected:
        return 'REJECTED';
      case TrainingApprovalOutcome.pending:
        return 'SENT_TO_HQ';
    }
  }

  /// Live-style `status_konfirmasi` for finance_transactions (COA manual).
  static String coaStatus(TrainingApprovalOutcome outcome) {
    switch (outcome) {
      case TrainingApprovalOutcome.approved:
        return 'APPROVED';
      case TrainingApprovalOutcome.rejected:
        return 'REJECTED';
      case TrainingApprovalOutcome.pending:
        return 'PENDING';
    }
  }

  /// Live-style status for stock_move_history retur cabang→pusat.
  static String stockMoveStatus(TrainingApprovalOutcome outcome) {
    switch (outcome) {
      case TrainingApprovalOutcome.approved:
        return 'SUCCESS';
      case TrainingApprovalOutcome.rejected:
        return 'REJECTED';
      case TrainingApprovalOutcome.pending:
        return 'PENDING';
    }
  }

  /// Apply simulated pusat decision to a **sandbox row only**.
  ///
  /// Throws if training is off — never touches production / admin APIs /
  /// pusat notifications.
  static Future<void> applySandboxOutcome({
    required String table,
    required dynamic id,
    required TrainingApprovalOutcome outcome,
    required String Function(TrainingApprovalOutcome) statusFor,
    String statusColumn = 'status',
    String? note,
    String noteColumn = 'reviewer_note',
    Map<String, dynamic>? extraValues,
  }) async {
    if (!TrainingMode.instance.isActive) {
      throw StateError(
        'TrainingApprovalSimulator.applySandboxOutcome requires Training Mode.',
      );
    }
    final values = <String, dynamic>{
      statusColumn: statusFor(outcome),
      if (note != null && note.isNotEmpty) noteColumn: note,
      if (outcome != TrainingApprovalOutcome.pending)
        'reviewed_at': DateTime.now().toIso8601String(),
      ...?extraValues,
    };
    await TrainingDataClient.instance.update(
      table,
      values,
      where: {'id': id},
    );
  }

  /// After cabang queues / sends a `pending_requests` row that waits on HQ.
  static Future<TrainingApprovalOutcome?> simulatePendingRequestIfTraining(
    BuildContext context, {
    required dynamic id,
    String? body,
    String Function(String status)? trackingFor,
  }) async {
    final sim = await showIfTraining(
      context,
      body: body ?? 'training_approval_sim_body_request_order'.tr(),
    );
    if (!TrainingMode.instance.isActive) return null;
    final outcome = sim?.outcome ?? TrainingApprovalOutcome.pending;
    final status = requestOrderStatus(outcome);
    await applySandboxOutcome(
      table: 'pending_requests',
      id: id,
      outcome: outcome,
      statusFor: requestOrderStatus,
      note: sim?.note,
      noteColumn: 'detail_resep',
      extraValues: {
        if (trackingFor != null) 'tracking_status': trackingFor(status),
      },
    );
    return outcome;
  }

  /// After cabang posts a manual COA journal awaiting owner/pusat.
  /// Reject matches live COA quarantine: delete the sandbox row.
  static Future<TrainingApprovalOutcome?> simulateCoaIfTraining(
    BuildContext context, {
    required dynamic id,
  }) async {
    final sim = await showIfTraining(
      context,
      body: 'training_approval_sim_body_coa'.tr(),
    );
    if (!TrainingMode.instance.isActive) return null;
    final outcome = sim?.outcome ?? TrainingApprovalOutcome.pending;
    if (outcome == TrainingApprovalOutcome.rejected) {
      await TrainingDataClient.instance.delete(
        'finance_transactions',
        where: {'id': id},
      );
      return outcome;
    }
    await applySandboxOutcome(
      table: 'finance_transactions',
      id: id,
      outcome: outcome,
      statusFor: coaStatus,
      statusColumn: 'status_konfirmasi',
      note: sim?.note,
    );
    return outcome;
  }

  /// After cabang submits retur → pusat validation.
  static Future<TrainingApprovalOutcome?> simulateStockMoveIfTraining(
    BuildContext context, {
    required dynamic id,
  }) async {
    final sim = await showIfTraining(
      context,
      body: 'training_approval_sim_body_stock_move'.tr(),
    );
    if (!TrainingMode.instance.isActive) return null;
    final outcome = sim?.outcome ?? TrainingApprovalOutcome.pending;
    await applySandboxOutcome(
      table: 'stock_move_history',
      id: id,
      outcome: outcome,
      statusFor: stockMoveStatus,
      note: sim?.note,
      noteColumn: 'keterangan_review',
    );
    return outcome;
  }
}

class _TrainingApprovalSheet extends StatefulWidget {
  const _TrainingApprovalSheet({this.body});

  final String? body;

  @override
  State<_TrainingApprovalSheet> createState() => _TrainingApprovalSheetState();
}

class _TrainingApprovalSheetState extends State<_TrainingApprovalSheet> {
  final _noteCtrl = TextEditingController();
  TrainingApprovalOutcome? _selected;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final outcome = _selected;
    if (outcome == null) return;
    final note = _noteCtrl.text.trim();
    Navigator.pop(
      context,
      TrainingApprovalResult(
        outcome: outcome,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: OptikAdminTokens.training.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: OptikAdminTokens.training,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'training_approval_sim_title'.tr(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: OptikAdminTokens.bgMid,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.body ?? 'training_approval_sim_body'.tr(),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 16),
                _optionTile(
                  outcome: TrainingApprovalOutcome.approved,
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF059669),
                  title: 'training_approval_sim_approve'.tr(),
                  subtitle: 'training_approval_sim_approve_desc'.tr(),
                ),
                const SizedBox(height: 8),
                _optionTile(
                  outcome: TrainingApprovalOutcome.rejected,
                  icon: Icons.cancel_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'training_approval_sim_reject'.tr(),
                  subtitle: 'training_approval_sim_reject_desc'.tr(),
                ),
                const SizedBox(height: 8),
                _optionTile(
                  outcome: TrainingApprovalOutcome.pending,
                  icon: Icons.hourglass_top_rounded,
                  color: const Color(0xFFD97706),
                  title: 'training_approval_sim_pending'.tr(),
                  subtitle: 'training_approval_sim_pending_desc'.tr(),
                ),
                if (_selected == TrainingApprovalOutcome.rejected) ...[
                  const SizedBox(height: 14),
                  Text(
                    'training_approval_sim_note_label'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'training_approval_sim_note_hint'.tr(),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _selected == null ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OptikAdminTokens.training,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'training_approval_sim_confirm'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionTile({
    required TrainingApprovalOutcome outcome,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    final selected = _selected == outcome;
    return Material(
      color: selected ? color.withOpacity(0.12) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _selected = outcome),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: selected ? color : OptikAdminTokens.bgMid,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? color : Colors.black26,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
