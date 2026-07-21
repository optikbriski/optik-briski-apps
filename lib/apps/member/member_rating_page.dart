// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/invoice/invoice_hub_service.dart';
import '../../shared/invoice/invoice_link.dart';
import '../../shared/invoice/invoice_rating_card.dart';

/// Rating kasir + pembuat kacamata — khusus APK Member (bukan Hub Invoice).
/// Scan QR masuk lewat menu tunggal di [HomeMemberPage] → [UniversalQrNav].
class MemberRatingPage extends StatefulWidget {
  const MemberRatingPage({super.key, this.initialInvoice});

  final String? initialInvoice;

  @override
  State<MemberRatingPage> createState() => _MemberRatingPageState();
}

class _MemberRatingPageState extends State<MemberRatingPage> {
  final _svc = InvoiceHubService();
  final _invoiceCtrl = TextEditingController();
  Map<String, dynamic>? _hub;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialInvoice != null) {
      _invoiceCtrl.text = widget.initialInvoice!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final inv = InvoiceLink.parse(_invoiceCtrl.text) ?? _invoiceCtrl.text.trim();
    if (inv.isEmpty) {
      setState(() => _error = 'invoice_hub_not_invoice'.tr());
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hub = await _svc.loadByInvoice(inv);
      if (!mounted) return;
      if (hub == null) {
        setState(() {
          _loading = false;
          _error = 'invoice_hub_not_found'.tr();
          _hub = null;
        });
        return;
      }
      // Member app: selalu tampilkan sebagai pelanggan untuk rating
      hub['role_view'] = 'customer';
      setState(() {
        _hub = hub;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _submit(String peran, int skor, String? komentar) async {
    final inv = _hub?['no_invoice']?.toString() ?? '';
    try {
      await _svc.submitRating(
        noInvoice: inv,
        peran: peran,
        skor: skor,
        komentar: komentar,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('invoice_hub_rating_ok'.tr()),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _hub;
    final bisa = h?['bisa_rating'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('member_rating_title'.tr()),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'member_rating_desc'.tr(),
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _invoiceCtrl,
            decoration: const InputDecoration(
              labelText: 'No. Invoice',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _load,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              minimumSize: const Size(double.infinity, 48),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('member_rating_load'.tr()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
          if (h != null) ...[
            const SizedBox(height: 20),
            Text(
              h['no_invoice']?.toString() ?? '-',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            Text(
              '${h['nama_pelanggan'] ?? '-'} · ${h['toko_id'] ?? '-'}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            if (!bisa)
              Text(
                'invoice_hub_rating_locked'.tr(),
                style: TextStyle(color: Colors.orange.shade800),
              )
            else ...[
              InvoiceRatingCard(
                dark: false,
                title: 'invoice_hub_rate_kasir'.tr(),
                nama: h['nama_kasir']?.toString(),
                existing: InvoiceHubService.ratingFor(h, 'kasir'),
                onSubmit: (s, k) => _submit('kasir', s, k),
              ),
              const SizedBox(height: 12),
              InvoiceRatingCard(
                dark: false,
                title: 'invoice_hub_rate_pembuat'.tr(),
                nama: h['nama_pembuat_kacamata']?.toString(),
                existing: InvoiceHubService.ratingFor(h, 'pembuat'),
                onSubmit: (s, k) => _submit('pembuat', s, k),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
