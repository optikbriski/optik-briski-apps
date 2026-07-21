// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/logistics/request_order_service.dart';
import '../../shared/training/training_approval_simulator.dart';
import '../../shared/training/training_mode.dart';
import 'request_order_pusat_page.dart';

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

  final TextEditingController trackingSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> trackingResults = [];

  bool get _isPusat {
    final toko = (widget.profile['toko_id'] ?? '').toString().toUpperCase();
    return toko == 'PUSAT' || toko == 'CABANG-PUSAT';
  }

  @override
  void initState() {
    super.initState();
    if (_isPusat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                RequestOrderPusatPage(profile: widget.profile),
          ),
        );
      });
    } else {
      _loadTodayRequests();
    }
  }

  Future<void> _loadTodayRequests() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';
      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      final startOfDay = "${todayDate}T00:00:00.000Z";
      final endOfDay = "${todayDate}T23:59:59.999Z";

      final res = await supabase
          .from('pending_requests')
          .select()
          .eq('toko_id', tokoId)
          .eq('status', 'PENDING')
          .gte('created_at', startOfDay)
          .lte('created_at', endOfDay);

      if (mounted) {
        setState(() {
          pendingRequestsList = List<Map<String, dynamic>>.from(res);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack("Gagal memuat data request: $e", Colors.red);
      }
    }
  }

  Future<void> _kirimKePusatMassal() async {
    if (pendingRequestsList.isEmpty) {
      _showSnack("Tidak ada antrean request order hari ini.", Colors.orange);
      return;
    }

    setState(() => isLoading = true);
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
        final status =
            TrainingApprovalSimulator.requestOrderStatus(outcome);
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
              ? Colors.redAccent
              : const Color(0xFFB45309),
        );
        _loadTodayRequests();
        return;
      }

      _showSnack(
          "✓ Sukses mengirim ${idsToUpdate.length} pesanan ke Gudang Pusat!",
          Colors.green);
      _loadTodayRequests();
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showSnack("Gagal mengirim ke pusat: $e", Colors.red);
    }
  }

  Future<void> _lacakStatusTransaksi(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final tokoId = widget.profile['toko_id']?.toString();
      var q = supabase
          .from('pending_requests')
          .select()
          .or('no_invoice.ilike.%$query%,nama_pelanggan.ilike.%$query%');
      if (tokoId != null && tokoId.isNotEmpty && !_isPusat) {
        q = q.eq('toko_id', tokoId);
      }
      final res = await q.order('created_at', ascending: false).limit(40);

      setState(() {
        trackingResults = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      _showSnack("Gagal melacak transaksi: $e", Colors.red);
    }
  }

  Color _trackColor(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'APPROVED':
        return Colors.tealAccent;
      case 'PREPARING':
        return Colors.orangeAccent;
      case 'SHIPPING':
        return Colors.blueAccent;
      case 'SUCCESS':
        return Colors.greenAccent;
      case 'REJECTED':
        return Colors.redAccent;
      case 'SENT_TO_HQ':
        return Colors.amberAccent;
      default:
        return Colors.white54;
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
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("REQUEST ORDER CABANG",
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadTodayRequests,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TRACKING REQUEST ORDER",
                      style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 6),
                  const Text(
                    'Alur: Cabang kirim → Approval Pusat → Preparing → '
                    'Pengiriman → Selesai (terima di cabang).',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: trackingSearchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Nomor Invoice / Nama Customer...",
                      hintStyle:
                          const TextStyle(color: Colors.grey, fontSize: 12),
                      prefixIcon: const Icon(Icons.track_changes,
                          color: Colors.blueAccent, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search,
                            color: Colors.orangeAccent, size: 18),
                        onPressed: () =>
                            _lacakStatusTransaksi(trackingSearchCtrl.text),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (val) => _lacakStatusTransaksi(val),
                  ),
                  if (trackingResults.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: trackingResults.length,
                      itemBuilder: (context, idx) {
                        final track = trackingResults[idx];
                        final st = track['status']?.toString() ?? '';
                        final color = _trackColor(st);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              "${track['nama_produk']} (${track['qty_request']} pcs)",
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              "Invoice: ${track['no_invoice']} | "
                              "${track['nama_pelanggan']}"
                              "${track['stock_move_resi'] != null ? ' | Resi ${track['stock_move_resi']}' : ''}",
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                RequestOrderService.labelStatus(st),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  ]
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  "ANTREAN REQUEST HARI INI",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.send_sharp,
                      size: 14, color: Colors.white),
                  label: const Text(
                    "KIRIM KE PUSAT",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  onPressed: _kirimKePusatMassal,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Colors.blueAccent))
                  : pendingRequestsList.isEmpty
                      ? const Center(
                          child: Text(
                              "Belum ada request order masuk untuk sesi hari ini.",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)))
                      : ListView.builder(
                          itemCount: pendingRequestsList.length,
                          itemBuilder: (context, index) {
                            final req = pendingRequestsList[index];
                            return Card(
                              color: const Color(0xFF1E293B),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      req['tipe_request'] == 'PRE_ORDER'
                                          ? Colors.orange.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                  child: Icon(Icons.shopping_basket,
                                      color: req['tipe_request'] == 'PRE_ORDER'
                                          ? Colors.orange
                                          : Colors.red,
                                      size: 18),
                                ),
                                title: Text(req['nama_produk'] ?? 'Produk',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    "Kekurangan: ${req['qty_request']} pcs | Tipe: ${req['tipe_request']}",
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 11)),
                                trailing: const Text(
                                  "PENDING",
                                  style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
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
