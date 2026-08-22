// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/logistics/receive_verification_rules.dart';
import '../../shared/logistics/request_order_service.dart';
import '../../shared/training/training_approval_simulator.dart';
import '../../shared/training/training_mode.dart';
import 'request_order_pusat_page.dart';
import 'verifikasi_terima.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

class RequestOrderPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RequestOrderPage({super.key, required this.profile});

  @override
  State<RequestOrderPage> createState() => _RequestOrderPageState();
}

class _RequestOrderPageState extends State<RequestOrderPage> {
  final supabase = Supabase.instance.client;
  final _svc = RequestOrderService();
  List<Map<String, dynamic>> pendingRequestsList = [];
  bool isLoading = true;
  bool _sending = false;

  final TextEditingController trackingSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> trackingResults = [];

  bool get _isPusat {
    final toko = (widget.profile['toko_id'] ?? '').toString().toUpperCase();
    return toko == 'PUSAT' || toko == 'CABANG-PUSAT';
  }

  String get _tokoId =>
      (widget.profile['toko_id'] ?? 'PUSAT').toString().toUpperCase();

  @override
  void initState() {
    super.initState();
    if (_isPusat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RequestOrderPusatPage(profile: widget.profile),
          ),
        );
      });
    } else {
      _loadTodayRequests();
    }
  }

  @override
  void dispose() {
    trackingSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTodayRequests() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      // Antrian "hari ini" = hari lokal device (bukan UTC calendar day).
      final bounds = RequestOrderService.localDayBoundsUtc();

      final res = await supabase
          .from('pending_requests')
          .select()
          .eq('toko_id', _tokoId)
          .eq('status', 'PENDING')
          .gte('created_at', bounds.startUtc.toIso8601String())
          .lt('created_at', bounds.endExclusiveUtc.toIso8601String())
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          pendingRequestsList = List<Map<String, dynamic>>.from(res);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack('Gagal memuat antrian: $e', OptikAdminTokens.danger);
      }
    }
  }

  Future<void> _kirimKePusatMassal() async {
    if (_sending) return;
    if (pendingRequestsList.isEmpty) {
      _showSnack(
        'Tidak ada antrian Request Order hari ini.',
        OptikAdminTokens.warning,
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Kirim ke Pusat?',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '${pendingRequestsList.length} request akan dikirim ke Gudang Pusat '
          'untuk approval.\n\n'
          'Setelah dikirim, lacak status di panel Tracking di atas.',
          style: const TextStyle(
            color: OptikAdminTokens.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      isLoading = true;
      _sending = true;
    });
    try {
      final idsToUpdate =
          pendingRequestsList.map((e) => e['id']).whereType<Object>().toList();

      // Training: TrainingHttpClient sandboxes this (no cabang↔pusat sync).
      await _svc.sendToHq(idsToUpdate);

      if (TrainingMode.instance.isActive && mounted) {
        final sim = await TrainingApprovalSimulator.showIfTraining(
          context,
          body: 'training_approval_sim_body_request_order'.tr(),
        );
        if (!mounted) return;
        final outcome = sim?.outcome ?? TrainingApprovalOutcome.pending;
        final status = TrainingApprovalSimulator.requestOrderStatus(outcome);
        for (final id in idsToUpdate) {
          await TrainingApprovalSimulator.applySandboxOutcome(
            table: 'pending_requests',
            id: id,
            outcome: outcome,
            statusFor: TrainingApprovalSimulator.requestOrderStatus,
            note: sim?.note,
            noteColumn: 'detail_resep',
            extraValues: {
              'tracking_status': RequestOrderService.trackingFor(status),
            },
          );
        }
        _showSnack(
          'training_ro_outcome_${outcome.name}'.tr(),
          outcome == TrainingApprovalOutcome.rejected
              ? OptikAdminTokens.danger
              : OptikAdminTokens.training,
        );
        await _loadTodayRequests();
        return;
      }

      _showSnack(
        'Berhasil kirim ${idsToUpdate.length} request ke Gudang Pusat.',
        OptikAdminTokens.success,
      );
      await _loadTodayRequests();
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showSnack('Gagal mengirim ke pusat: $e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _lacakStatusTransaksi(String query) async {
    if (query.trim().isEmpty) return;
    try {
      var q = supabase
          .from('pending_requests')
          .select()
          .or('no_invoice.ilike.%$query%,nama_pelanggan.ilike.%$query%,'
              'stock_move_resi.ilike.%$query%,nama_produk.ilike.%$query%');
      if (!_isPusat && _tokoId.isNotEmpty) {
        q = q.eq('toko_id', _tokoId);
      }
      final res = await q.order('created_at', ascending: false).limit(40);

      setState(() {
        trackingResults = List<Map<String, dynamic>>.from(res);
      });
      if (trackingResults.isEmpty) {
        _showSnack('Tidak ada hasil untuk pencarian ini.', OptikAdminTokens.warning);
      }
    } catch (e) {
      _showSnack('Gagal melacak: $e', OptikAdminTokens.danger);
    }
  }

  Color _trackColor(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'APPROVED':
      case 'PREPARING':
        return OptikAdminTokens.navy;
      case 'SHIPPING':
        return OptikAdminTokens.warning;
      case 'SUCCESS':
        return OptikAdminTokens.success;
      case 'REJECTED':
        return OptikAdminTokens.danger;
      case 'SENT_TO_HQ':
        return OptikAdminTokens.ice;
      case 'PENDING':
        return OptikAdminTokens.warning;
      default:
        return OptikAdminTokens.textMuted;
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isPusat) {
      return const PremiumScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Request Order Cabang',
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: isLoading ? null : _loadTodayRequests,
            icon: const Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PremiumPanel(
              padding: const EdgeInsets.all(18),
              borderRadius: 20,
              borderColor: OptikAdminTokens.warning.withOpacity(0.28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PremiumSectionHeader(
                    label: 'Lacak Request Order',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Alur: Cabang kirim → Approval Pusat → Disiapkan → '
                    'Dalam perjalanan → Terima di Verifikasi Terima.',
                    style: TextStyle(
                      color: OptikAdminTokens.textMuted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: trackingSearchCtrl,
                    style:
                        const TextStyle(color: OptikAdminTokens.navy, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Invoice / pelanggan / resi / produk…',
                      hintStyle: const TextStyle(
                          color: OptikAdminTokens.textMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.track_changes,
                          color: OptikAdminTokens.navy, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search,
                            color: OptikAdminTokens.warning, size: 18),
                        onPressed: () =>
                            _lacakStatusTransaksi(trackingSearchCtrl.text),
                      ),
                      filled: true,
                      fillColor: OptikAdminTokens.bgMid,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _lacakStatusTransaksi,
                  ),
                  if (trackingResults.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(color: OptikAdminTokens.line),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: trackingResults.length,
                      itemBuilder: (context, idx) {
                        final track = trackingResults[idx];
                        final st = track['status']?.toString() ?? '';
                        final color = _trackColor(st);
                        final resi =
                            (track['stock_move_resi'] ?? '').toString().trim();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${track['nama_produk']} (${track['qty_request']} pcs)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'Invoice: ${track['no_invoice']} · '
                            '${track['nama_pelanggan']}'
                            '${resi.isNotEmpty ? ' · Resi $resi' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OptikAdminTokens.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: color.withOpacity(0.35)),
                              ),
                              child: Text(
                                RequestOrderService.labelStatus(st),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (ReceiveVerificationRules.canOpenIncomingQueue(
                          widget.profile) &&
                        trackingResults.any((t) =>
                            (t['status'] ?? '')
                                .toString()
                                .toUpperCase() ==
                            'SHIPPING')) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => IncomingVerification(
                                  profile: widget.profile,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.fact_check_outlined, size: 16),
                          label: const Text('Buka Verifikasi Terima'),
                        ),
                      ),
                    ],
                  ]
                ],
              ),
            ),
            const SizedBox(height: 20),
            const PremiumSectionHeader(label: 'Antrian Request Hari Ini'),
            const SizedBox(height: 6),
            const Text(
              'Kirim manual ke Pusat kapan saja. '
              'Sisa yang lupa dikirim otomatis ke Pusat jam 23:59.',
              style: TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 11,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: OptikAdminTokens.navy,
                  foregroundColor: OptikAdminTokens.bg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: OptikAdminTokens.bg,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  pendingRequestsList.isEmpty
                      ? 'Kirim ke Pusat'
                      : 'Kirim ke Pusat (${pendingRequestsList.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: (_sending || isLoading) ? null : _kirimKePusatMassal,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : pendingRequestsList.isEmpty
                      ? PremiumEmptyState(
                          message:
                              'Belum ada Request Order antrian untuk hari ini.\n'
                              'Yang sudah dikirim bisa dilacak di panel atas.',
                          icon: Icons.assignment_outlined,
                          accent: OptikAdminTokens.ice,
                        )
                      : ListView.builder(
                          itemCount: pendingRequestsList.length,
                          itemBuilder: (context, index) {
                            final req = pendingRequestsList[index];
                            final tipe =
                                (req['tipe_request'] ?? '').toString();
                            final isPre = tipe.toUpperCase() == 'PRE_ORDER';
                            final detail =
                                (req['detail_resep'] ?? '').toString();
                            final isOnline = detail
                                    .toLowerCase()
                                    .contains('online member') ||
                                (req['no_invoice'] ?? '')
                                    .toString()
                                    .toUpperCase()
                                    .startsWith('ON-');
                            return PremiumListTile(
                              title: req['nama_produk'] ?? 'Produk',
                              subtitle:
                                  'Kurang ${req['qty_request']} pcs · '
                                  '${isOnline ? 'Online Member · ' : ''}'
                                  '${isPre ? 'Pre-order' : (tipe.isEmpty ? 'Stok' : tipe)}'
                                  '${req['no_invoice'] != null ? ' · ${req['no_invoice']}' : ''}',
                              icon: isOnline
                                  ? Icons.shopping_bag_outlined
                                  : Icons.shopping_basket_rounded,
                              iconColor: isOnline
                                  ? OptikAdminTokens.navy
                                  : (isPre
                                      ? OptikAdminTokens.warning
                                      : OptikAdminTokens.danger),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      OptikAdminTokens.warning.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: OptikAdminTokens.warning
                                        .withOpacity(0.4),
                                  ),
                                ),
                                child: const Text(
                                  'Antrian',
                                  style: TextStyle(
                                    color: OptikAdminTokens.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              margin: const EdgeInsets.only(bottom: 8),
                            );
                          },
                        ),
            )
          ],
        ),
      ),
    );
  }
}
