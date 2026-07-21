// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../apps/admin/garansi_page.dart';
import '../../apps/admin/sales_page.dart';
import '../qr/qr_route.dart';
import '../qr/universal_qr_scan_page.dart';
import 'invoice_hub_service.dart';
import 'invoice_link.dart';

/// Hub multi-fungsi dari QR invoice.
/// - Customer / guest: ringkasan status + garansi + CTA Google Review
///   (rating kasir/pembuat hanya di APK Member)
/// - Staff (admin/karyawan login): aksi ambil, klaim, detail POS, lihat rating
class InvoiceHubPage extends StatefulWidget {
  const InvoiceHubPage({
    super.key,
    this.noInvoice,
    this.rawScan,
    this.profile,
  });

  final String? noInvoice;
  final String? rawScan;
  final Map<String, dynamic>? profile;

  /// Buka scanner universal (hanya invoice) lalu hub.
  static Future<void> openScanner(BuildContext context,
      {Map<String, dynamic>? profile}) async {
    final result = await UniversalQrScanPage.scanRouted(
      context,
      allowedTypes: {QrPayloadType.invoice},
      titleKey: 'scan_qr',
      hintKey: 'universal_qr_scan_hint',
    );
    if (result == null || !context.mounted) return;
    final inv = result.invoiceNo ?? InvoiceLink.parse(result.raw);
    if (inv == null || inv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('invoice_hub_not_invoice'.tr())),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceHubPage(noInvoice: inv, profile: profile),
      ),
    );
  }

  @override
  State<InvoiceHubPage> createState() => _InvoiceHubPageState();
}

class _InvoiceHubPageState extends State<InvoiceHubPage> {
  final _svc = InvoiceHubService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _hub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? data;
      if (widget.rawScan != null) {
        data = await _svc.loadFromScan(widget.rawScan!);
      } else if (widget.noInvoice != null) {
        data = await _svc.loadByInvoice(widget.noInvoice!);
      }
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _loading = false;
          _error = 'invoice_hub_not_found'.tr();
        });
        return;
      }
      setState(() {
        _hub = data;
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

  bool get _staff => _hub != null && InvoiceHubService.isStaffView(_hub!);

  Map<String, dynamic> get _profileOrToko =>
      widget.profile ??
      {
        'toko_id': _hub?['toko_id']?.toString() ?? 'PUSAT',
        'role': _staff ? 'admin_toko' : 'guest',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text('invoice_hub_title'.tr()),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final h = _hub!;
    final inv = h['no_invoice']?.toString() ?? '-';
    final sisa = InvoiceHubService.garansiSisaHariMax(h);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E3C72)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8C872).withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inv,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inv));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('invoice_hub_copied'.tr())),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded,
                        color: Color(0xFFE8C872), size: 20),
                  ),
                ],
              ),
              Text(
                _staff
                    ? 'invoice_hub_mode_staff'.tr()
                    : 'invoice_hub_mode_customer'.tr(),
                style: TextStyle(
                  color: const Color(0xFFE8C872).withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${h['nama_pelanggan'] ?? '-'} · ${h['toko_id'] ?? '-'}',
                style: TextStyle(color: Colors.white.withOpacity(0.75)),
              ),
              const SizedBox(height: 6),
              Text(
                '${'invoice_hub_status'.tr()}: ${InvoiceHubService.statusLabel(h)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${'invoice_hub_bayar'.tr()}: ${h['status_pembayaran'] ?? '-'}'
                '${(h['sisa_tagihan'] != null && (h['sisa_tagihan'] as num) > 0) ? ' · Sisa tagihan' : ''}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 13,
                ),
              ),
              if (sisa != null) ...[
                const SizedBox(height: 6),
                Text(
                  sisa >= 0
                      ? 'invoice_hub_garansi_sisa'.tr(args: ['$sisa'])
                      : 'invoice_hub_garansi_habis'.tr(),
                  style: TextStyle(
                    color: sisa >= 0
                        ? const Color(0xFFE8C872)
                        : Colors.redAccent.shade100,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'invoice_hub_items'.tr(),
          style: const TextStyle(
            color: Color(0xFFE8C872),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ..._itemTiles(h),
        const SizedBox(height: 16),
        Text(
          'invoice_hub_garansi'.tr(),
          style: const TextStyle(
            color: Color(0xFFE8C872),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ..._garansiTiles(h),
        const SizedBox(height: 20),
        if (_staff) ..._staffActions(h) else ..._customerActions(h),
      ],
    );
  }

  List<Widget> _itemTiles(Map<String, dynamic> h) {
    final items = h['items'];
    if (items is! List || items.isEmpty) {
      return [
        Text('—', style: TextStyle(color: Colors.white.withOpacity(0.4))),
      ];
    }
    return items.map((raw) {
      final it = Map<String, dynamic>.from(raw as Map);
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${it['nama_produk'] ?? '-'} · ${it['tipe_produk'] ?? ''} × ${it['qty'] ?? 1}'
          '${_staff && it['subtotal'] != null ? ' · Rp ${it['subtotal']}' : ''}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }).toList();
  }

  List<Widget> _garansiTiles(Map<String, dynamic> h) {
    final list = h['garansi'];
    if (list is! List || list.isEmpty) {
      return [
        Text(
          'invoice_hub_garansi_empty'.tr(),
          style: TextStyle(color: Colors.white.withOpacity(0.45)),
        ),
      ];
    }
    return list.map((raw) {
      final g = Map<String, dynamic>.from(raw as Map);
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${g['nama_produk'] ?? '-'} (${g['jenis_garansi']})\n'
          '${g['status']} · ${g['tanggal_mulai'] ?? '-'} → ${g['tanggal_akhir'] ?? '-'}'
          '${g['klaim_digunakan'] == true ? ' · klaim dipakai' : ''}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _staffActions(Map<String, dynamic> h) {
    final inv = h['no_invoice']?.toString() ?? '';
    final saleId = h['sale_id']?.toString();
    final diambil = h['diambil_at'] != null;
    final lunas =
        (h['status_pembayaran']?.toString() ?? '').toLowerCase() == 'lunas';

    return [
      Text(
        'invoice_hub_staff_actions'.tr(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      _actionBtn(
        icon: Icons.receipt_long_rounded,
        label: 'invoice_hub_btn_detail'.tr(),
        onTap: saleId == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoiceDetailPage(saleId: saleId),
                  ),
                ),
      ),
      _actionBtn(
        icon: Icons.qr_code_scanner_rounded,
        label: diambil
            ? 'invoice_hub_btn_ambil_done'.tr()
            : 'invoice_hub_btn_ambil'.tr(),
        color: const Color(0xFFE8C872),
        foreground: const Color(0xFF0F172A),
        onTap: diambil || !lunas
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GaransiKonfirmasiAmbilPage(
                      profile: _profileOrToko,
                      prefillInvoice: inv,
                    ),
                  ),
                );
                await _load();
              },
      ),
      if (!lunas)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'invoice_hub_belum_lunas'.tr(),
            style: TextStyle(color: Colors.orange.shade200, fontSize: 12),
          ),
        ),
      _actionBtn(
        icon: Icons.verified_rounded,
        label: 'invoice_hub_btn_garansi'.tr(),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GaransiPage(profile: _profileOrToko),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'invoice_hub_assign_pembuat'.tr(),
        style: TextStyle(
          color: const Color(0xFFE8C872).withOpacity(0.9),
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        h['nama_pembuat_kacamata'] != null
            ? '${'invoice_hub_pembuat_current'.tr()}: ${h['nama_pembuat_kacamata']}'
            : 'invoice_hub_pembuat_empty'.tr(),
        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12.5),
      ),
      const SizedBox(height: 8),
      _actionBtn(
        icon: Icons.engineering_rounded,
        label: 'invoice_hub_btn_set_pembuat'.tr(),
        onTap: () => _pickPembuat(h),
      ),
      Text(
        '${'invoice_hub_kasir'.tr()}: ${h['nama_kasir'] ?? '-'}',
        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
      ),
      const SizedBox(height: 8),
      ..._ratingSummary(h),
    ];
  }

  Future<void> _pickPembuat(Map<String, dynamic> h) async {
    final toko = h['toko_id']?.toString() ?? '';
    final inv = h['no_invoice']?.toString() ?? '';
    if (toko.isEmpty || inv.isEmpty) return;

    List<Map<String, dynamic>> list;
    try {
      list = await _svc.listKaryawanToko(toko);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
      return;
    }
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('invoice_hub_no_karyawan'.tr())),
      );
      return;
    }

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'invoice_hub_pick_pembuat'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            ...list.map(
              (k) => ListTile(
                title: Text(
                  k['nama']?.toString() ?? '-',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  k['jabatan']?.toString() ?? '',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                onTap: () => Navigator.pop(ctx, k),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    try {
      await _svc.setPembuat(
        noInvoice: inv,
        karyawanId: picked['id'].toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('invoice_hub_pembuat_ok'.tr()),
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

  List<Widget> _customerActions(Map<String, dynamic> h) {
    final googleUrl = h['google_review_url']?.toString().trim() ?? '';
    return [
      Text(
        'invoice_hub_customer_actions'.tr(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'invoice_hub_customer_info'.tr(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.65),
            height: 1.4,
            fontSize: 13,
          ),
        ),
      ),
      const SizedBox(height: 14),
      _actionBtn(
        icon: Icons.reviews_rounded,
        label: 'invoice_hub_btn_google'.tr(),
        color: const Color(0xFFE8C872),
        foreground: const Color(0xFF0F172A),
        onTap: googleUrl.isEmpty
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('invoice_hub_google_missing'.tr())),
                );
              }
            : () async {
                final uri = Uri.tryParse(googleUrl);
                if (uri == null) return;
                final ok = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('invoice_hub_google_fail'.tr())),
                  );
                }
              },
      ),
      Text(
        'invoice_hub_rating_via_member'.tr(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 12,
          height: 1.35,
        ),
      ),
      if (h['foto_hasil_url'] != null) ...[
        const SizedBox(height: 16),
        Text(
          'invoice_hub_foto_hasil'.tr(),
          style: const TextStyle(
            color: Color(0xFFE8C872),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            h['foto_hasil_url'].toString(),
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(
              '—',
              style: TextStyle(color: Colors.white.withOpacity(0.4)),
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _ratingSummary(Map<String, dynamic> h) {
    final list = h['ratings'];
    if (list is! List || list.isEmpty) {
      return [
        Text(
          'invoice_hub_rating_none'.tr(),
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
        ),
      ];
    }
    return [
      Text(
        'invoice_hub_rating_title'.tr(),
        style: const TextStyle(
          color: Color(0xFFE8C872),
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      ...list.map((raw) {
        final r = Map<String, dynamic>.from(raw as Map);
        return Text(
          '• ${r['peran']}: ${r['nama_karyawan'] ?? '-'} → ${r['skor']}/5',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5),
        );
      }),
    ];
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
    Color? foreground,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: color ?? const Color(0xFF1E3C72),
            foregroundColor: foreground ?? Colors.white,
            disabledBackgroundColor: Colors.white12,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
