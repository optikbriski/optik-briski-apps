import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../formatters.dart';
import 'invoice_hub_service.dart';

/// Karyawan-only invoice summary (no POS detail / PDF / print / garansi module).
class InvoicePeekPage extends StatefulWidget {
  const InvoicePeekPage({
    super.key,
    required this.noInvoice,
    this.rawScan,
  });

  final String noInvoice;
  final String? rawScan;

  @override
  State<InvoicePeekPage> createState() => _InvoicePeekPageState();
}

class _InvoicePeekPageState extends State<InvoicePeekPage> {
  final _svc = InvoiceHubService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _hub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = widget.rawScan?.trim();
      final hub = (raw != null && raw.isNotEmpty)
          ? await _svc.loadFromScan(raw)
          : await _svc.loadByInvoice(widget.noInvoice);
      if (!mounted) return;
      if (hub == null) {
        setState(() {
          _loading = false;
          _error = 'invoice_hub_not_found'.tr();
        });
        return;
      }
      setState(() {
        _hub = hub;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12233A),
        title: Text('invoice_hub_title'.tr()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : _buildBody(_hub!),
    );
  }

  Widget _buildBody(Map<String, dynamic> h) {
    final items = (h['items'] as List?) ?? const [];
    final garansi = (h['garansi'] as List?) ?? const [];
    final total = (h['total_harga'] as num?)?.toInt() ?? 0;
    final bayar = (h['dibayarkan'] as num?)?.toInt() ?? 0;
    final sisa = (h['sisa_tagihan'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          h['no_invoice']?.toString() ?? widget.noInvoice,
          style: const TextStyle(
            color: Color(0xFFE8C872),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          h['nama_pelanggan']?.toString() ?? '-',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          '${h['status_pembayaran'] ?? '-'} · ${h['tracking_status'] ?? '-'}',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        const SizedBox(height: 16),
        _row('Total', formatRupiah(total)),
        _row('Dibayar', formatRupiah(bayar)),
        _row('Sisa', formatRupiah(sisa)),
        const SizedBox(height: 20),
        Text(
          'Items',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final sub = (m['subtotal'] as num?)?.toInt() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    m['nama_produk']?.toString() ?? '-',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                Text(
                  formatRupiah(sub),
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          );
        }),
        if (garansi.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'invoice_hub_garansi'.tr(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...garansi.map((raw) {
            final g = Map<String, dynamic>.from(raw as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${g['jenis_garansi'] ?? '-'} · ${g['status'] ?? '-'}'
                '${g['tanggal_akhir'] != null ? ' · s/d ${g['tanggal_akhir']}' : ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            );
          }),
        ],
        const SizedBox(height: 24),
        Text(
          'Mode lihat saja di app Karyawan.\n'
          'Cetak / PDF / klaim garansi tersedia di Admin.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openInvoicePeek(
  BuildContext context, {
  required String noInvoice,
  String? rawScan,
  Map<String, dynamic>? profile,
  required bool viewOnly,
  required bool fromAdminHidScanner,
}) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => InvoicePeekPage(
        noInvoice: noInvoice,
        rawScan: rawScan,
      ),
    ),
  );
}
