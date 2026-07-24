// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../apps/admin/garansi_page.dart';
import '../garansi/garansi_service.dart';
import '../qr/obr_codes.dart';
import '../qr/qr_route.dart';
import '../qr/universal_qr_scan_page.dart';
import 'invoice_detail_page.dart';
import 'invoice_hub_service.dart';
import 'invoice_lifecycle_service.dart';
import 'invoice_link.dart';
import 'invoice_qr_anti_copy_beta.dart';
import 'staff_nik_scan_dialog.dart';

/// Hub multi-fungsi dari QR invoice.
/// - Customer / guest: ringkasan status + garansi + CTA Google Review
///   (rating kasir/pembuat hanya di APK Member)
/// - Staff (admin + HID scanner): aksi pelunasan / serah terima / klaim
class InvoiceHubPage extends StatefulWidget {
  const InvoiceHubPage({
    super.key,
    this.noInvoice,
    this.rawScan,
    this.profile,
    this.viewOnly = false,
    this.fromAdminHidScanner = false,
  });

  final String? noInvoice;
  final String? rawScan;
  final Map<String, dynamic>? profile;

  /// Paksa mode lihat saja (QR toko / buka dari history tanpa QR pelanggan).
  final bool viewOnly;

  /// Lifecycle hanya dari scanner HID yang terhubung ke web admin.
  final bool fromAdminHidScanner;

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
        builder: (_) => InvoiceHubPage(
          noInvoice: inv,
          rawScan: result.raw,
          profile: profile,
          // openScanner = kamera → bukan lifecycle HID
          viewOnly: true,
          fromAdminHidScanner: false,
        ),
      ),
    );
  }

  @override
  State<InvoiceHubPage> createState() => _InvoiceHubPageState();
}

class _InvoiceHubPageState extends State<InvoiceHubPage> {
  final _svc = InvoiceHubService();
  final _lifecycle = InvoiceLifecycleService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _hub;
  bool _busy = false;
  String? _scanPhase;

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
      String? phase;
      if (_customerLifecycleEnabled && widget.rawScan != null) {
        try {
          final v = await _lifecycle.validateCustomerScan(widget.rawScan!);
          phase = v.phase;
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _hub = data;
            _loading = false;
            _error = e.toString();
            _scanPhase = null;
          });
          return;
        }
      }
      setState(() {
        _hub = data;
        _loading = false;
        _scanPhase = phase;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Pelunasan: payment gateway kasir → scan NIK → finance+sales → QR LUNAS.
  Future<void> _settleDpConfirmed(Map<String, dynamic> h) async {
    final saleId = h['sale_id']?.toString();
    final raw = widget.rawScan;
    if (saleId == null || raw == null || _busy) return;

    final sisa = int.tryParse(h['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final metode = await _showPelunasanGateway(sisa);
    if (metode == null || !mounted) return;

    final staff = await showStaffNikScanDialog(
      context,
      title: 'Scan karyawan · pelunasan',
      subtitle: 'Scan NIK karyawan yang menerima pelunasan sisa tagihan.',
    );
    if (staff == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = await _lifecycle.settleDpViaGateway(
        saleId: saleId,
        metodePembayaran: metode,
        staffNik: staff['nik']?.toString() ?? '',
        staffNama: staff['nama']?.toString() ?? '',
        rawScan: raw,
      );
      if (!mounted) return;
      await _showCustomerQrDialog(
        title: 'QR pelanggan · LUNAS',
        body:
            'Pelunasan berhasil. Berikan QR LUNAS ini ke pelanggan.\n'
            'QR DP lama sudah tidak berlaku.\n'
            'Scan berikutnya (scanner toko): serah terima + aktifkan garansi.',
        payload: InvoiceLifecycleService.customerQrPayload(updated) ?? '',
      );
      if (!mounted) return;
      Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showPelunasanGateway(int sisa) async {
    var metode = 'Tunai';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              title: const Text(
                'Payment Gateway · Pelunasan',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Bayar sisa tagihan sekali lunas.\n'
                    'Jumlah: Rp ${_fmt(sisa)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: metode,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Metode bayar',
                      labelStyle:
                          TextStyle(color: Colors.white.withOpacity(0.55)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Tunai', child: Text('Tunai')),
                      DropdownMenuItem(value: 'Debit', child: Text('Debit')),
                      DropdownMenuItem(
                          value: 'Transfer', child: Text('Transfer')),
                      DropdownMenuItem(value: 'QRIS', child: Text('QRIS')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => metode = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Konfirmasi hanya setelah pembayaran benar-benar diterima. '
                    'QR LUNAS muncul setelah sukses; QR DP hangus.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, metode),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8C872),
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                  child: const Text('Bayar & lanjut'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showStoreViewQr(String inv) async {
    final payload = InvoiceLink.encodeStoreView(inv);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('QR toko · lihat detail',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'QR internal toko. Hanya membuka data & riwayat transaksi — '
              'bukan untuk lunasi DP, serah terima, atau klaim garansi.',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(data: payload, size: 180),
            ),
            const SizedBox(height: 10),
            SelectableText(
              payload,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomerQrDialog({
    required String title,
    required String body,
    required String payload,
  }) async {
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR pelanggan gagal dibuat (token kosong).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              body,
              style:
                  TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(data: payload, size: 180),
            ),
            const SizedBox(height: 10),
            SelectableText(
              payload,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
              ),
            ),
            if (InvoiceQrAntiCopyBeta.isUsable) ...[
              const SizedBox(height: 8),
              Text(
                'Beta anti-copy aktif',
                style: TextStyle(
                  color: Colors.orange.withOpacity(0.8),
                  fontSize: 11,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Pelanggan wajib jaga QR ini. Fitur anti-copy masih beta (belum aktif).',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  /// Serah terima + aktifkan garansi + terbitkan QR CLAIM.
  Future<void> _handoverConfirmed(Map<String, dynamic> h) async {
    final inv = h['no_invoice']?.toString() ?? '';
    final raw = widget.rawScan;
    if (inv.isEmpty || raw == null || _busy) return;

    final staff = await showStaffNikScanDialog(
      context,
      title: 'Scan karyawan · serah terima',
      subtitle: 'Scan NIK karyawan yang menyerahkan barang ke pelanggan.',
    );
    if (staff == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final toko = h['toko_id']?.toString();
      final role = _profileOrToko['role']?.toString() ?? '';
      final isPusat = toko?.toUpperCase() == 'PUSAT' ||
          role == 'owner' ||
          role == 'admin_pusat';
      final res = await _lifecycle.handoverAndIssueClaim(
        noInvoice: inv,
        rawScan: raw,
        staffNik: staff['nik']?.toString() ?? '',
        tokoId: toko,
        isPusat: isPusat,
      );
      if (!mounted) return;
      final claimQr = res['claim_qr']?.toString() ?? '';
      await _showCustomerQrDialog(
        title: 'QR pelanggan · CLAIM',
        body:
            'Serah terima OK. Garansi aktif s/d ${res['tanggal_akhir']}.\n'
            'QR LUNAS hangus. Berikan QR CLAIM ini ke pelanggan (sekali pakai).',
        payload: claimQr,
      );
      if (!mounted) return;
      Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claimConfirmed(Map<String, dynamic> h) async {
    final inv = h['no_invoice']?.toString() ?? '';
    final raw = widget.rawScan;
    if (inv.isEmpty || raw == null || !mounted) return;

    if (InvoiceHubService.isCaseClosed(h)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Case closed: garansi habis / sudah diklaim. Tidak bisa diproses.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final staff = await showStaffNikScanDialog(
      context,
      title: 'Scan karyawan · klaim garansi',
      subtitle: 'Scan NIK karyawan yang menangani klaim garansi.',
    );
    if (staff == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _lifecycle.consumeClaimQr(
        rawScan: raw,
        staffNik: staff['nik']?.toString() ?? '',
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GaransiPage(
            profile: _profileOrToko,
            initialInvoice: inv,
            openKlaimTab: true,
          ),
        ),
      );
      if (mounted) Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  bool get _staff => _hub != null && InvoiceHubService.isStaffView(_hub!);

  /// Aksi DP / serah terima / klaim: QR pelanggan + HID web admin saja.
  bool get _customerLifecycleEnabled {
    if (widget.viewOnly) return false;
    if (!widget.fromAdminHidScanner) return false;
    return InvoiceLink.isCustomerLifecycleQr(widget.rawScan);
  }

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
              const SizedBox(height: 8),
              Text(
                '${'invoice_hub_status'.tr()}: ${InvoiceHubService.statusLabel(h)}'
                ' · ${'invoice_hub_bayar'.tr()}: ${h['status_pembayaran'] ?? '-'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
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
        const Text(
          'Data pelanggan',
          style: TextStyle(
            color: Color(0xFFE8C872),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _infoCard(_customerDetailRows(h, dense: true)),
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
        const SizedBox(height: 8),
        _infoCard([
          Text(
            'Total: Rp ${_fmt(int.tryParse(h['total_harga']?.toString() ?? '0') ?? 0)}\n'
            'Dibayar: Rp ${_fmt(int.tryParse(h['dibayarkan']?.toString() ?? '0') ?? 0)}\n'
            'Sisa: Rp ${_fmt(int.tryParse(h['sisa_tagihan']?.toString() ?? '0') ?? 0)}\n'
            'Metode: ${h['metode_pembayaran'] ?? '-'} · Kasir: ${h['nama_kasir'] ?? '-'}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ]),
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
        // Lifecycle (lunasi / serah terima / klaim) hanya dari QR pelanggan.
        if (_staff && _customerLifecycleEnabled) ..._confirmPanel(h),
        if (_staff && !_customerLifecycleEnabled) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              'Mode lihat saja.\n'
              'Aksi pelunasan / serah terima / klaim wajib scan QR pelanggan '
              'lewat scanner yang terhubung ke web admin '
              '(bukan kamera HP / link HTTPS).\n'
              'QR toko (OBRTXN) hanya untuk detail.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!_staff) ..._customerActions(h),
        if (_staff) ...[
          const SizedBox(height: 8),
          ..._staffSecondaryActions(h),
        ],
      ],
    );
  }

  List<Widget> _customerDetailRows(Map<String, dynamic> h,
      {bool dense = false}) {
    final wa = h['no_wa']?.toString().trim();
    final email = h['email_pelanggan']?.toString().trim() ??
        h['email']?.toString().trim();
    final alamat = h['alamat']?.toString().trim();
    final rows = <Widget>[
      Text(
        h['nama_pelanggan']?.toString() ?? '-',
        style: TextStyle(
          color: Colors.white.withOpacity(dense ? 0.9 : 0.85),
          fontWeight: FontWeight.w700,
          fontSize: dense ? 14 : 15,
        ),
      ),
      Text(
        'Toko: ${h['toko_id'] ?? '-'}',
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5),
      ),
      if (wa != null && wa.isNotEmpty)
        Text('WhatsApp: $wa',
            style:
                TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.5)),
      if (email != null && email.isNotEmpty)
        Text('Email: $email',
            style:
                TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.5)),
      if (alamat != null && alamat.isNotEmpty)
        Text('Alamat: $alamat',
            style:
                TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.5)),
    ];
    if (dense) return rows;
    return rows
        .map((w) => Padding(padding: const EdgeInsets.only(bottom: 2), child: w))
        .toList();
  }

  Widget _infoCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// Panel konfirmasi di bawah — fase mengikuti QR yang di-scan (sekali pakai).
  List<Widget> _confirmPanel(Map<String, dynamic> h) {
    final sisa = int.tryParse(h['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final dp = int.tryParse(h['dibayarkan']?.toString() ?? '0') ?? 0;
    final phase = _scanPhase ??
        ObrInvoice.normalizePhase(
          ObrInvoice.parse(widget.rawScan)?.phase,
        );

    late final String title;
    late final String question;
    late final String yesLabel;
    late final VoidCallback onYes;

    if (phase == 'DP') {
      title = 'Konfirmasi pelunasan';
      question =
          'Sisa yang belum dibayar akan dilunasi 1× lewat payment gateway.\n\n'
          'Sudah DP: Rp ${_fmt(dp)}\nSisa: Rp ${_fmt(sisa)}\n\n'
          'Setelah bayar sukses: QR DP hangus, QR LUNAS baru muncul.';
      yesLabel = 'Ya, buka payment gateway';
      onYes = () => _settleDpConfirmed(h);
    } else if (phase == 'LUNAS') {
      final tracking =
          (h['tracking_status'] ?? '').toString().toUpperCase();
      title = 'Konfirmasi serah terima';
      question = tracking == 'PENDING_PO'
          ? 'Status masih PENDING_PO — barang belum siap.\n'
              'SOP: jangan serah terima sebelum barang selesai.'
          : 'Produk sudah selesai dan akan diberikan ke pelanggan?\n\n'
              'Ini mengaktifkan garansi ${GaransiService.garansiHari} hari '
              'dan menerbitkan QR CLAIM (sekali pakai).\n'
              'Lanjut → scan barcode karyawan.';
      yesLabel = tracking == 'PENDING_PO'
          ? 'Tidak bisa (belum siap)'
          : 'Ya, sudah diberikan';
      onYes = tracking == 'PENDING_PO'
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'SOP: selesaikan barang dulu sebelum serah terima.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          : () => _handoverConfirmed(h);
    } else if (phase == 'CLAIM') {
      if (InvoiceHubService.isCaseClosed(h)) {
        return [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
            ),
            child: const Text(
              'Case closed\n'
              'Garansi sudah habis masa, sudah diklaim, atau QR CLAIM sudah dipakai. '
              'Tidak ada tindak lanjut.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ];
      }
      title = 'Konfirmasi klaim garansi';
      question =
          'Buka proses klaim untuk transaksi ini?\n'
          'QR CLAIM hanya sekali pakai. Lanjut → scan barcode karyawan.';
      yesLabel = 'Ya, buka klaim garansi';
      onYes = () => _claimConfirmed(h);
    } else {
      return const [];
    }

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8C872).withOpacity(0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFE8C872),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              question,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.maybePop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withOpacity(0.25)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Tidak'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : onYes,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE8C872),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(yesLabel,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
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

  /// Aksi sekunder (detail / pembuat / rating) — di bawah panel konfirmasi.
  List<Widget> _staffSecondaryActions(Map<String, dynamic> h) {
    final saleId = h['sale_id']?.toString();
    final inv = h['no_invoice']?.toString() ?? '';

    return [
      Text(
        'Lainnya',
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
      if (inv.isNotEmpty)
        _actionBtn(
          icon: Icons.qr_code_2_rounded,
          label: 'QR toko (lihat detail saja)',
          onTap: () => _showStoreViewQr(inv),
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
