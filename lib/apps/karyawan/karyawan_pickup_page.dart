import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/attendance/pos_duty_gate.dart';
import '../../shared/invoice/invoice_lifecycle_rules.dart';
import '../../shared/invoice/invoice_lifecycle_service.dart';
import '../../shared/invoice/pickup_item_picker_dialog.dart';
import '../../shared/invoice/sale_fulfillment_service.dart';
import '../../shared/theme.dart';

/// Serah terima pickup dari HP Karyawan: scan QR LUNAS Member + duty gate sesi.
class KaryawanPickupPage extends StatefulWidget {
  const KaryawanPickupPage({
    super.key,
    required this.noInvoice,
    required this.rawScan,
    required this.profile,
  });

  final String noInvoice;
  final String rawScan;
  final Map<String, dynamic> profile;

  @override
  State<KaryawanPickupPage> createState() => _KaryawanPickupPageState();
}

class _KaryawanPickupPageState extends State<KaryawanPickupPage> {
  final _lifecycle = InvoiceLifecycleService();
  final _fulfillment = SaleFulfillmentService();

  bool _busy = false;
  String? _error;
  String? _success;
  Map<String, dynamic>? _sale;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  String get _nik =>
      (widget.profile['nik'] ?? '').toString().trim().toUpperCase();
  String get _karyawanId => (widget.profile['id'] ?? '').toString().trim();
  String get _nama => (widget.profile['nama'] ?? '').toString().trim();
  String get _toko => (widget.profile['toko_id'] ?? '').toString().trim();

  Future<void> _boot() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_karyawanId.isEmpty || _nik.isEmpty) {
        throw 'antrian_err_profil_nik'.tr();
      }

      final duty = await PosDutyGate.blockReason(
        karyawanId: _karyawanId,
        nik: _nik,
      );
      if (duty != null) {
        throw duty.tr();
      }

      final validated = await _lifecycle.validateCustomerScan(widget.rawScan);
      if (validated.phase != 'LUNAS') {
        throw 'antrian_err_bukan_lunas'.tr();
      }
      if (validated.sale['no_invoice']?.toString() != widget.noInvoice) {
        throw 'antrian_err_invoice_mismatch'.tr();
      }

      final saleToko = (validated.sale['toko_id'] ?? '').toString();
      if (!InvoiceLifecycleRules.isPusatToko(_toko) &&
          !InvoiceLifecycleRules.sameStore(_toko, saleToko)) {
        throw 'antrian_err_beda_cabang'.tr();
      }

      final saleId = validated.sale['id'].toString();
      final items = await _fulfillment.listItems(saleId);
      if (!mounted) return;
      setState(() {
        _sale = validated.sale;
        _items = items;
        _busy = false;
      });

      await _runHandover();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _runHandover() async {
    final sale = _sale;
    if (sale == null || _busy) return;

    final picked = await showPickupItemPickerDialog(context, items: _items);
    if (picked == null || picked.isEmpty || !mounted) {
      if (mounted && _success == null && _error == null) {
        setState(() => _error = 'antrian_err_batal_pilih'.tr());
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final duty = await PosDutyGate.blockReason(
        karyawanId: _karyawanId,
        nik: _nik,
      );
      if (duty != null) throw duty.tr();

      final saleToko = (sale['toko_id'] ?? '').toString();
      final res = await _lifecycle.handoverAndIssueClaim(
        noInvoice: widget.noInvoice,
        rawScan: widget.rawScan,
        staffNik: _nik,
        saleItemIds: picked,
        tokoId: saleToko,
        isPusat: InvoiceLifecycleRules.isPusatToko(_toko),
      );

      final keepLunas = res['lunas_qr_kept'] == true;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = keepLunas
            ? 'antrian_pickup_partial_ok'.tr()
            : 'antrian_pickup_ok'.tr();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pelanggan = (_sale?['nama_pelanggan'] ?? '-').toString();
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.pale,
      appBar: AppBar(
        backgroundColor: OptikKaryawanTokens.surface,
        foregroundColor: OptikKaryawanTokens.ink,
        title: Text('antrian_pickup_title'.tr()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.noInvoice,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: OptikKaryawanTokens.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pelanggan,
              style: const TextStyle(
                color: OptikKaryawanTokens.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_nama.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${'antrian_staff_label'.tr()}: $_nama',
                style: const TextStyle(
                  color: OptikKaryawanTokens.muted,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_busy)
              const Center(
                child: CircularProgressIndicator(
                  color: OptikKaryawanTokens.gold,
                ),
              )
            else if (_success != null)
              _statusCard(
                color: OptikKaryawanTokens.success,
                icon: Icons.check_circle_rounded,
                text: _success!,
              )
            else if (_error != null)
              _statusCard(
                color: Colors.orange.shade800,
                icon: Icons.error_outline_rounded,
                text: _error!,
              ),
            const Spacer(),
            if (_error != null && _success == null)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (_sale != null) {
                          _runHandover();
                        } else {
                          _boot();
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: OptikKaryawanTokens.seasideMid,
                  foregroundColor: OptikKaryawanTokens.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('btn_coba_lagi'.tr()),
              ),
            if (_success != null)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: OptikKaryawanTokens.seasideMid,
                  foregroundColor: OptikKaryawanTokens.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('btn_mengerti'.tr()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OptikKaryawanTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: OptikKaryawanTokens.ink.withOpacity(0.9),
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
