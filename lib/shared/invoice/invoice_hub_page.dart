// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../apps/admin/garansi_page.dart';
import '../garansi/garansi_service.dart';
import '../qr/obr_codes.dart';
import '../qr/qr_route.dart';
import '../qr/universal_qr_scan_page.dart';
import 'invoice_delivery_result.dart';
import 'invoice_delivery_service.dart';
import 'invoice_detail_page.dart';
import 'invoice_hub_service.dart';
import 'invoice_lifecycle_service.dart';
import 'invoice_link.dart';
import 'invoice_qr_anti_copy_beta.dart';
import 'pickup_item_picker_dialog.dart';
import 'sale_fulfillment_service.dart';
import 'staff_nik_scan_dialog.dart';
import '../theme.dart';
import '../widgets/admin/admin_premium.dart';
import '../widgets/admin/premium_app_bar.dart';

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
    final lifecycle = result.invoiceCustomerLifecycle && !result.invoiceViewOnly;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceHubPage(
          noInvoice: inv,
          rawScan: result.raw,
          profile: profile,
          // Kamera staff: QR pelanggan OBRINV tetap bisa pelunasan / serah terima.
          viewOnly: !lifecycle,
          fromAdminHidScanner: lifecycle,
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
  /// True setelah QR pelanggan OBRINV lolos validasi token/fase.
  bool _lifecycleValidated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _lifecycleValidated = false;
      _scanPhase = null;
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

      // Lengkapi channel/fulfillment bila RPC hub belum mengembalikan kolom itu.
      data = await _enrichSaleChannelFields(data);
      data = await _enrichItemFulfillment(data);
      data = await _healGaransiIfDiambil(data);
      data = await _healClaimQrIfNeeded(data);
      data = await _svc.enrichLabJob(data);

      // Aksi mengikuti payload QR yang di-scan (OBRINV + token), bukan flag UI.
      String? phase;
      var lifecycleOk = false;
      final raw = widget.rawScan;
      if (raw != null && InvoiceLink.isCustomerLifecycleQr(raw)) {
        try {
          final v = await _lifecycle.validateCustomerScan(raw);
          phase = v.phase;
          lifecycleOk = true;
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _hub = data;
            _loading = false;
            _error = e.toString();
            _scanPhase = null;
            _lifecycleValidated = false;
          });
          return;
        }
      }

      setState(() {
        _hub = data;
        _loading = false;
        _scanPhase = phase;
        _lifecycleValidated = lifecycleOk;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Line sudah DIAMBIL tapi kartu masih menunggu_ambil → aktifkan (repair).
  Future<Map<String, dynamic>> _healGaransiIfDiambil(
    Map<String, dynamic> data,
  ) async {
    final saleId = (data['sale_id'] ?? '').toString().trim();
    if (saleId.isEmpty) return data;
    if (!InvoiceHubService.hasDiambilLines(data)) return data;
    try {
      await GaransiService().syncAktifDariLineDiambil(saleId);
      final rows = await Supabase.instance.client
          .from('garansi_kartu')
          .select(
            'id, jenis_garansi, nama_produk, status, tanggal_mulai, '
            'tanggal_akhir, klaim_digunakan, spesifikasi_produk',
          )
          .eq('sale_id', saleId);
      final list = rows as List;
      final claimable = list.any(
        (raw) => GaransiService.kartuBisaDiklaim(
          Map<String, dynamic>.from(raw as Map),
        ),
      );
      return {...data, 'garansi': rows, 'garansi_claimable': claimable};
    } catch (_) {
      return data;
    }
  }

  /// Ada item diambil + garansi aktif tapi QR CLAIM hilang → terbitkan ulang.
  Future<Map<String, dynamic>> _healClaimQrIfNeeded(
    Map<String, dynamic> data,
  ) async {
    final saleId = (data['sale_id'] ?? '').toString().trim();
    if (saleId.isEmpty) return data;
    if (!InvoiceHubService.hasDiambilLines(data)) return data;
    if (data['qr_claim_ready'] == true) return data;
    try {
      final claimQr = await _lifecycle.ensureClaimQrIfNeeded(saleId);
      if (claimQr == null || claimQr.isEmpty) return data;
      return {
        ...data,
        'qr_claim_ready': true,
        'qr_claim_used': false,
        if (data['qr_lunas_ready'] != true) 'qr_payload': claimQr,
      };
    } catch (_) {
      return data;
    }
  }

  /// Pastikan items punya fulfillment_status (RPC lama mungkin belum kirim).
  Future<Map<String, dynamic>> _enrichItemFulfillment(
    Map<String, dynamic> data,
  ) async {
    final saleId = (data['sale_id'] ?? '').toString().trim();
    if (saleId.isEmpty) return data;
    final items = data['items'];
    final needsEnrich = items is! List ||
        items.isEmpty ||
        items.any((raw) {
          if (raw is! Map) return true;
          return !raw.containsKey('fulfillment_status');
        });
    if (!needsEnrich) return data;
    try {
      final rows = await SaleFulfillmentService().listItems(saleId);
      if (rows.isEmpty) return data;
      return {...data, 'items': rows};
    } catch (_) {
      return data;
    }
  }

  Future<Map<String, dynamic>> _enrichSaleChannelFields(
    Map<String, dynamic> data,
  ) async {
    final needsChannel = (data['channel'] ?? '').toString().trim().isEmpty;
    final needsFulfill =
        (data['fulfillment'] ?? '').toString().trim().isEmpty;
    final needsOid =
        (data['online_order_id'] ?? '').toString().trim().isEmpty;
    if (!needsChannel && !needsFulfill && !needsOid) return data;

    final saleId = (data['sale_id'] ?? '').toString().trim();
    final inv = (data['no_invoice'] ?? widget.noInvoice ?? '').toString().trim();
    try {
      Map<String, dynamic>? sale;
      if (saleId.isNotEmpty) {
        sale = await Supabase.instance.client
            .from('sales')
            .select('channel, fulfillment, courier, online_order_id')
            .eq('id', saleId)
            .maybeSingle();
      } else if (inv.isNotEmpty) {
        sale = await Supabase.instance.client
            .from('sales')
            .select('channel, fulfillment, courier, online_order_id')
            .eq('no_invoice', inv)
            .maybeSingle();
      }
      if (sale == null) return data;
      return {
        ...data,
        if (needsChannel) 'channel': sale['channel'],
        if (needsFulfill) 'fulfillment': sale['fulfillment'],
        if ((data['courier'] ?? '').toString().trim().isEmpty)
          'courier': sale['courier'],
        if (needsOid) 'online_order_id': sale['online_order_id'],
      };
    } catch (_) {
      return data;
    }
  }

  Future<bool> _ensureCabangOk(Map<String, dynamic> h) async {
    final msg = _cabangMismatchMessage(h);
    if (msg == null) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: OptikAdminTokens.warning),
    );
    return false;
  }

  /// Pelunasan: payment gateway kasir → scan NIK → finance+sales → QR LUNAS.
  Future<void> _settleDpConfirmed(Map<String, dynamic> h) async {
    final saleId = h['sale_id']?.toString();
    final raw = widget.rawScan;
    if (saleId == null || raw == null || _busy) return;
    if (!await _ensureCabangOk(h)) return;

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
      final tracking =
          (updated['tracking_status'] ?? '').toString().toUpperCase();
      final ready = tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR';
      final delivered = await InvoiceDeliveryService().deliver(
        sale: updated,
        mode: ready
            ? InvoiceDeliveryMode.withQr
            : InvoiceDeliveryMode.paymentConfirm,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(delivered.summary),
          backgroundColor: delivered.anyOk || delivered.allRequestedOk
              ? OptikAdminTokens.success
              : OptikAdminTokens.warning,
          duration: const Duration(seconds: 5),
        ),
      );
      final payload =
          InvoiceLifecycleService.customerQrPayload(updated) ?? '';
      await _showCustomerQrDialog(
        title: ready ? 'QR pelanggan · LUNAS ready' : 'Pelunasan OK',
        body: ready
            ? 'Pelunasan OK. QR pengambilan dikirim ke email, WhatsApp, '
                'dan APK Member.\n${delivered.summary}'
            : 'Pelunasan OK. Barang belum ready — masuk PENDING. '
                'QR pengambilan dikirim setelah admin Barang Ready.\n'
                '${delivered.summary}',
        payload: payload,
      );
      if (!mounted) return;
      Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
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
              backgroundColor: OptikAdminTokens.bg,
              title: const Text(
                'Payment Gateway · Pelunasan',
                style: TextStyle(color: OptikAdminTokens.navy, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Bayar sisa tagihan sekali lunas.\n'
                    'Jumlah: Rp ${_fmt(sisa)}',
                    style: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.75),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AdminPickerField(
                    label: 'Metode bayar',
                    valueText: metode,
                    icon: Icons.payments_rounded,
                    badgeColor: OptikAdminTokens.ice,
                    onTap: () async {
                      const metodes = ['Tunai', 'Debit', 'Transfer', 'QRIS'];
                      final picked = await showAdminPicker<String>(
                        context: ctx,
                        title: 'Metode bayar',
                        options: metodes
                            .map(
                              (m) => AdminPickerOption(value: m, label: m),
                            )
                            .toList(),
                        selected: metode,
                        searchable: false,
                      );
                      if (picked != null && picked.value != null) {
                        setLocal(() => metode = picked.value!);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Konfirmasi hanya setelah pembayaran benar-benar diterima. '
                    'QR LUNAS muncul setelah sukses; QR DP hangus.',
                    style: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.5),
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
                    backgroundColor: OptikAdminTokens.ice,
                    foregroundColor: OptikAdminTokens.navy,
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
    final payload = InvoiceLink.encodeStoreView(
      inv,
      sale: _hub,
      channel: _resolvedChannel,
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.bg,
        title: const Text('QR toko · lihat detail',
            style: TextStyle(color: OptikAdminTokens.navy, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'QR internal toko. Hanya membuka data & riwayat transaksi — '
              'bukan untuk lunasi DP, serah terima, atau klaim garansi.',
              style: TextStyle(
                  color: OptikAdminTokens.slate.withOpacity(0.7), fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OptikAdminTokens.snow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(data: payload, size: 180),
            ),
            const SizedBox(height: 10),
            SelectableText(
              payload,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: OptikAdminTokens.slate.withOpacity(0.55),
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
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
      return;
    }
    // Tunggu frame setelah NIK scan page pop — hindari dialog “invisible”
    // (barrier gelap, konten 0px) yang mengunci seluruh UI.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.bg,
        title: Text(title,
            style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 16)),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  body,
                  style: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.7),
                      fontSize: 13),
                ),
                const SizedBox(height: 14),
                Container(
                  width: 204,
                  height: 204,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.snow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(data: payload, size: 180),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  payload,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: OptikAdminTokens.slate.withOpacity(0.55),
                    fontSize: 11,
                  ),
                ),
                if (InvoiceQrAntiCopyBeta.isUsable) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Beta anti-copy aktif',
                    style: TextStyle(
                      color: OptikAdminTokens.warning.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Pelanggan wajib jaga QR ini. Fitur anti-copy masih beta (belum aktif).',
                    style: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  /// Admin: lunas pending → konfirmasi barang ready → kirim QR LUNAS ready.
  Future<void> _confirmGlassesReady(Map<String, dynamic> h) async {
    final saleId = h['sale_id']?.toString();
    if (saleId == null || _busy) return;
    if (!_isAdminRole) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Konfirmasi barang ready hanya untuk admin '
            '(scan barcode nota di web admin).',
          ),
        ),
      );
      return;
    }
    if (!await _ensureCabangOk(h)) return;

    final staff = await showStaffNikScanDialog(
      context,
      title: 'Scan admin · barang ready',
      subtitle: 'Scan NIK admin yang mengonfirmasi barang sudah siap diambil.',
    );
    if (staff == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = await _lifecycle.markGoodsReadyAndIssueCustomerQr(
        saleId: saleId,
        staffNik: staff['nik']?.toString() ?? '',
        staffNama: staff['nama']?.toString(),
      );
      InvoiceDeliveryResult? delivered;
      try {
        delivered = await InvoiceDeliveryService().deliver(
          sale: updated,
          mode: InvoiceDeliveryMode.goodsReady,
        );
      } catch (e) {
        // DB sudah READY (SIAP_DIAMBIL) + QR — jangan gagalkan UI karena email/WA.
        delivered = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('QR sudah diterbitkan, kirim gagal: $e'),
              backgroundColor: OptikAdminTokens.warning,
            ),
          );
        }
      }
      if (!mounted) return;
      final payload =
          InvoiceLifecycleService.customerQrPayload(updated) ?? '';
      final isDp = InvoiceHubService.isDpOpen(updated);
      final track =
          (updated['tracking_status'] ?? '').toString().toUpperCase();
      // Dialog QR dulu (bisa ditutup / tap luar), baru toast kirim —
      // hindari barrier “gelap tanpa dialog” yang mengunci klik.
      await _showCustomerQrDialog(
        title: isDp
            ? 'QR pelanggan · pelunasan'
            : 'QR pelanggan · pengambilan (READY)',
        body: isDp
            ? 'Barang ready. QR pelunasan siap.\n${delivered?.summary ?? ''}'
            : 'Status $track (board READY). QR pengambilan siap di-scan pelanggan.\n'
                '${delivered?.summary ?? 'Email/WA bisa gagal — QR di bawah tetap valid.'}',
        payload: payload,
      );
      if (!mounted) return;
      if (delivered != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(delivered.summary),
            backgroundColor: delivered.anyOk || delivered.allRequestedOk
                ? OptikAdminTokens.success
                : OptikAdminTokens.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Serah terima: pilih item → aktifkan garansi batch itu + QR CLAIM.
  Future<void> _handoverConfirmed(Map<String, dynamic> h) async {
    final inv = h['no_invoice']?.toString() ?? '';
    final raw = widget.rawScan;
    if (inv.isEmpty || raw == null || _busy) return;
    if (!await _ensureCabangOk(h)) return;

    // Pastikan list line terbaru (status READY / RO / DIAMBIL).
    final saleId = h['sale_id']?.toString() ?? '';
    List<Map<String, dynamic>> lines = const [];
    if (saleId.isNotEmpty) {
      try {
        lines = await SaleFulfillmentService().listItems(saleId);
      } catch (_) {
        final rawItems = h['items'];
        if (rawItems is List) {
          lines = rawItems
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    }

    final picked = await showPickupItemPickerDialog(context, items: lines);
    if (picked == null || picked.isEmpty || !mounted) return;

    final staff = await showStaffNikScanDialog(
      context,
      title: 'Scan karyawan · serah terima',
      subtitle:
          'Scan barcode NIK karyawan yang menyerahkan ${picked.length} item terpilih.',
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
        saleItemIds: picked,
        tokoId: toko,
        isPusat: isPusat,
      );
      final saleRow = res['sale'];
      final claimQr = res['claim_qr']?.toString() ?? '';
      final keepLunas = res['lunas_qr_kept'] == true;
      final nextLunas = res['next_lunas_qr']?.toString() ?? '';
      InvoiceDeliveryResult? delivered;
      if (saleRow is Map) {
        final saleMap = Map<String, dynamic>.from(saleRow);
        // Selalu kirim CLAIM eksplisit (jangan encodeFromSale yang prefer LUNAS).
        delivered = await InvoiceDeliveryService().deliver(
          sale: saleMap,
          qrPayloadOverride: claimQr.isNotEmpty ? claimQr : null,
        );
        // READY ditunda → kirim juga QR LUNAS yang sama (ambil sisa nanti).
        if (keepLunas && nextLunas.isNotEmpty) {
          try {
            await InvoiceDeliveryService().deliver(
              sale: saleMap,
              mode: InvoiceDeliveryMode.goodsReady,
              qrPayloadOverride: nextLunas,
            );
          } catch (_) {}
        }
      }
      if (!mounted) return;
      if (delivered != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(delivered.summary),
            backgroundColor: delivered.anyOk || delivered.allRequestedOk
                ? OptikAdminTokens.success
                : OptikAdminTokens.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      final partial = res['partial'] == true;
      final deferred = int.tryParse('${res['deferred_ready'] ?? 0}') ?? 0;
      final pendingRo = int.tryParse('${res['pending_ro'] ?? 0}') ?? 0;
      final remainHint = [
        if (deferred > 0)
          keepLunas
              ? '$deferred READY ditunda — scan QR LUNAS yang sama lagi'
              : '$deferred READY ditunda',
        if (pendingRo > 0) '$pendingRo RO pending — QR baru setelah RO ready',
      ].join(' · ');
      await _showCustomerQrDialog(
        title: 'QR pelanggan · CLAIM',
        body: partial
            ? 'Diambil ${res['taken_count'] ?? picked.length} item · '
                'garansi batch aktif s/d ${res['tanggal_akhir']}.'
                '${remainHint.isEmpty ? '' : '\nSisa: $remainHint.'}\n'
                '${delivered?.summary ?? 'QR CLAIM untuk batch ini.'}'
            : 'Semua item selesai diambil. Garansi aktif s/d ${res['tanggal_akhir']}.\n'
                '${delivered?.summary ?? 'QR CLAIM untuk APK Member / WA / email.'}',
        payload: claimQr,
      );
      if (!mounted) return;
      // Masih ada sisa → tetap di hub (jangan pop) biar bisa refresh status.
      if (partial) {
        await _load();
      } else {
        Navigator.maybePop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claimConfirmed(Map<String, dynamic> h) async {
    final inv = h['no_invoice']?.toString() ?? '';
    final raw = widget.rawScan;
    if (inv.isEmpty || raw == null || !mounted) return;
    if (!await _ensureCabangOk(h)) return;

    if (InvoiceHubService.isCaseClosed(h)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'CLEAR · Garansi mati (habis / sudah diklaim). Tidak bisa diproses.',
          ),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
      return;
    }

    final staff = await showStaffNikScanDialog(
      context,
      title: 'Scan karyawan · klaim garansi',
      subtitle: 'Scan barcode NIK karyawan yang menangani klaim garansi.',
    );
    if (staff == null || !mounted) return;

    setState(() => _busy = true);
    try {
      // Validasi saja — hanguskan QR setelah klaim tersimpan (bukan sebelum).
      await _lifecycle.validateClaimScan(raw);
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
      if (!mounted) return;
      // Klaim sukses menandai kartu klaim_digunakan → baru hanguskan QR CLAIM.
      try {
        final cards = await Supabase.instance.client
            .from('garansi_kartu')
            .select('klaim_digunakan')
            .eq('sale_id', h['sale_id']?.toString() ?? '');
        final burned = (cards as List).any(
          (raw) => Map<String, dynamic>.from(raw as Map)['klaim_digunakan'] == true,
        );
        if (burned) {
          await _lifecycle.consumeClaimQr(
            rawScan: raw,
            staffNik: staff['nik']?.toString() ?? '',
          );
        }
      } catch (_) {}
      if (mounted) Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
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

  Future<void> _shipOnlineOrder(Map<String, dynamic> h) async {
    final oid = (h['online_order_id'] ?? '').toString().trim();
    if (oid.isEmpty || _busy) return;
    if (!await _ensureCabangOk(h)) return;

    final tracking = TextEditingController(
      text: (h['courier'] ?? '').toString(),
    );
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.bg,
        title: const Text(
          'Kirim pesanan online',
          style: TextStyle(color: OptikAdminTokens.navy, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terdeteksi beli dari APK Member (ONLINE).\n'
              'Kurir: ${h['courier'] ?? '-'} · '
              'Serahkan paket ke kurir / isi resi.',
              style: TextStyle(
                color: OptikAdminTokens.slate.withOpacity(0.75),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tracking,
              style: const TextStyle(color: OptikAdminTokens.navy),
              decoration: const InputDecoration(
                labelText: 'No. resi / tracking kurir',
                labelStyle: TextStyle(color: OptikAdminTokens.slate),
              ),
            ),
            TextField(
              controller: note,
              style: const TextStyle(color: OptikAdminTokens.navy),
              decoration: const InputDecoration(
                labelText: 'Catatan toko',
                labelStyle: TextStyle(color: OptikAdminTokens.slate),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.ice,
              foregroundColor: OptikAdminTokens.navy,
            ),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // Utama: panggil Biteship create-order.
      final bite = await _svc.createBiteshipShipment(onlineOrderId: oid);
      if (!mounted) return;
      if (bite['ok'] == true) {
        final waybill =
            (bite['waybill'] ?? bite['courier_tracking'] ?? '-').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bite['already'] == true
                  ? 'Sudah ada order Biteship · $waybill'
                  : 'Kurir Biteship dipanggil · resi $waybill',
            ),
            backgroundColor: OptikAdminTokens.success,
          ),
        );
        await _load();
        return;
      }

      // Fallback: resi manual bila Biteship gagal / meta belum ada.
      final res = await _svc.markOnlineShipped(
        onlineOrderId: oid,
        courierTracking: tracking.text.trim().isNotEmpty
            ? tracking.text.trim()
            : null,
        storeNote:
            '${note.text.trim()}\nBiteship: ${bite['error'] ?? 'gagal'}'
                .trim(),
      );
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${bite['error'] ?? res['error'] ?? 'Gagal kirim'}',
            ),
            backgroundColor: OptikAdminTokens.danger,
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ditandai dikirim (manual). Biteship: ${bite['error'] ?? '-'}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _channelBadge() {
    final online = _isOnlineChannel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: online
            ? OptikAdminTokens.navy.withOpacity(0.35)
            : OptikAdminTokens.snow.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: online
              ? OptikAdminTokens.ice.withOpacity(0.7)
              : OptikAdminTokens.lineStrong,
        ),
      ),
      child: Text(
        online ? 'Online · APK Member' : 'Toko · Offline',
        style: TextStyle(
          color: online ? OptikAdminTokens.ice : OptikAdminTokens.slate,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }

  List<Widget> _onlineShipPanel(Map<String, dynamic> h) {
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: OptikAdminTokens.navy,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pesanan online · siap kirim',
              style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'QR terdeteksi ONLINE (beli di APK Member).\n'
              'Fulfillment: kirim ke alamat · Kurir: ${h['courier'] ?? '-'}.\n'
              'Tekan Kirim setelah paket diserahkan ke kurir.',
              style: TextStyle(
                color: OptikAdminTokens.snow,
                height: 1.4,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : () => _shipOnlineOrder(h),
              style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.navy,
                foregroundColor: OptikAdminTokens.snow,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.local_shipping_rounded),
              label: const Text(
                'Panggil Biteship / Kirim',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  bool get _staff => _hub != null && InvoiceHubService.isStaffView(_hub!);

  /// Aksi DP / LUNAS ready / CLAIM — scan QR pelanggan OBRINV valid.
  bool get _customerLifecycleEnabled => _lifecycleValidated;

  /// Channel dari QR scan dulu; fallback `sales.channel`.
  String get _resolvedChannel {
    final fromQr = InvoiceLink.channelFromRaw(widget.rawScan);
    if (fromQr == ObrSaleChannel.online) return ObrSaleChannel.online;
    final fromSale =
        ObrSaleChannel.fromSaleChannel(_hub?['channel']?.toString());
    return fromSale;
  }

  bool get _isOnlineChannel => _resolvedChannel == ObrSaleChannel.online;

  bool _isOnlineDelivery(Map<String, dynamic> h) {
    if (!_isOnlineChannel) return false;
    final f = (h['fulfillment'] ?? '').toString().trim().toLowerCase();
    return f == 'delivery';
  }

  /// Online delivery siap dikirim (belum diambil / belum shipped).
  bool _canShipOnline(Map<String, dynamic> h) {
    if (!_staff || !_isOnlineDelivery(h)) return false;
    if (InvoiceHubService.sudahDiambil(h)) return false;
    final oid = (h['online_order_id'] ?? '').toString().trim();
    if (oid.isEmpty) return false;
    final t = (h['tracking_status'] ?? '').toString().trim().toUpperCase();
    if (t == 'DIKIRIM' || t == 'SHIPPED') return false;
    // Siap kirim: barang ready / masih diproses online lunas.
    return InvoiceHubService.isLunas(h);
  }

  bool _isLunasPending(Map<String, dynamic> h) {
    if (!InvoiceHubService.isLunas(h)) return false;
    if (InvoiceHubService.sudahDiambil(h)) return false;
    final t = (h['tracking_status'] ?? '').toString().trim().toUpperCase();
    return t != 'SIAP_DIAMBIL' && t != 'CLEAR';
  }

  /// Ada line READY tapi QR LUNAS belum aktif / sudah dipakai batch sebelumnya.
  bool _needsLunasQrRefresh(Map<String, dynamic> h) {
    if (!InvoiceHubService.isLunas(h)) return false;
    if (InvoiceHubService.sudahDiambil(h)) return false;
    if (!InvoiceHubService.hasReadyLines(h)) return false;
    final ready = h['qr_lunas_ready'] == true;
    final used = h['qr_lunas_used'] == true;
    return used || !ready;
  }

  bool _isLunasReady(Map<String, dynamic> h) {
    if (!InvoiceHubService.isLunas(h)) return false;
    if (InvoiceHubService.sudahDiambil(h)) return false;
    final t = (h['tracking_status'] ?? '').toString().trim().toUpperCase();
    return t == 'SIAP_DIAMBIL' || t == 'CLEAR';
  }

  /// Lunas pending (bayar lunas, stok belum ada) — barcode/aksi khusus admin.
  bool get _isAdminRole {
    final r = (_profileOrToko['role'] ?? '').toString().trim().toLowerCase();
    if (r == 'karyawan' || r == 'staff' || r == 'kasir' || r == 'guest') {
      return false;
    }
    if (r == 'owner' ||
        r == 'admin_pusat' ||
        r == 'admin_toko' ||
        r == 'admin') {
      return true;
    }
    // Web admin: profile kosong + buka dari HID/scanner lifecycle.
    return widget.profile == null &&
        _staff &&
        (widget.fromAdminHidScanner || _lifecycleValidated);
  }

  /// Nota harus diproses di cabang pembuat (kecuali PUSAT).
  String? _cabangMismatchMessage(Map<String, dynamic> sale) {
    final saleToko = (sale['toko_id'] ?? '').toString().trim().toUpperCase();
    final staffToko =
        (_profileOrToko['toko_id'] ?? '').toString().trim().toUpperCase();
    if (saleToko.isEmpty || staffToko.isEmpty) return null;
    if (staffToko == 'PUSAT') return null;
    if (saleToko == staffToko) return null;
    return 'Nota ini dari cabang $saleToko. '
        'Scan QR di POS $saleToko (bukan $staffToko) agar terdeteksi.';
  }

  Map<String, dynamic> get _profileOrToko =>
      widget.profile ??
      {
        'toko_id': _hub?['toko_id']?.toString() ?? 'PUSAT',
        // Jangan default admin_toko — APK karyawan harus kirim profile.role.
        // Web admin tanpa profile tetap bisa lewat fromAdminHidScanner.
        'role': widget.fromAdminHidScanner || _lifecycleValidated
            ? 'admin_toko'
            : (_staff ? 'staff' : 'guest'),
      };

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'invoice_hub_title'.tr(),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.ice),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: OptikAdminTokens.slate)),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: OptikAdminTokens.navy,
                            foregroundColor: OptikAdminTokens.snow,
                          ),
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: OptikAdminTokens.slate,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _pill(String label, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _moneyRow(String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: OptikAdminTokens.slate,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          'Rp $value',
          style: TextStyle(
            color: valueColor ?? OptikAdminTokens.navy,
            fontSize: bold ? 15 : 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _surface({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    Color? color,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? OptikAdminTokens.snow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.lineStrong),
        boxShadow: [
          BoxShadow(
            color: OptikAdminTokens.navy.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _fulfillmentMeter(Map<String, dynamic> h) {
    final items = h['items'];
    final maps = items is List
        ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final c = SaleFulfillmentService.counts(maps);
    final total = c.total <= 0 ? 1 : c.total;

    Widget cell(String label, int n, Color color) {
      return Expanded(
        child: Column(
          children: [
            Text(
              '$n',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: OptikAdminTokens.slate,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: n / total,
                minHeight: 5,
                backgroundColor: OptikAdminTokens.bgMid,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return _surface(
      child: Row(
        children: [
          cell('Ready', c.ready, OptikAdminTokens.navy),
          const SizedBox(width: 14),
          cell('RO', c.pendingRo, OptikAdminTokens.warning),
          const SizedBox(width: 14),
          cell('Diambil', c.diambil, OptikAdminTokens.success),
        ],
      ),
    );
  }

  Widget _identityHeader(Map<String, dynamic> h) {
    final inv = h['no_invoice']?.toString() ?? '-';
    final name = h['nama_pelanggan']?.toString() ?? '-';
    final toko = h['toko_id']?.toString() ?? '-';
    final pay = (h['status_pembayaran'] ?? '-').toString().toUpperCase();
    final status = InvoiceHubService.statusLabel(h);
    final metode = h['metode_pembayaran']?.toString() ?? '-';

    return _surface(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv,
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$name · $toko · $metode',
                      style: const TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Salin invoice',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inv));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'invoice_hub_copied'.tr(),
                        style: const TextStyle(color: OptikAdminTokens.snow),
                      ),
                      backgroundColor: OptikAdminTokens.navy,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded,
                    color: OptikAdminTokens.navy, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(pay,
                  color: pay == 'LUNAS'
                      ? OptikAdminTokens.success
                      : OptikAdminTokens.warning),
              _pill(status, color: OptikAdminTokens.navy),
              _channelBadge(),
              if (_staff)
                _pill(
                  _staff
                      ? 'invoice_hub_mode_staff'.tr()
                      : 'invoice_hub_mode_customer'.tr(),
                  color: OptikAdminTokens.slate,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Zona CTA utama — selalu di atas konten sekunder.
  List<Widget> _primaryActionZone(Map<String, dynamic> h) {
    final out = <Widget>[
      _sectionLabel('Tindakan'),
    ];

    if (_canShipOnline(h)) {
      out.addAll(_onlineShipPanel(h));
      out.add(const SizedBox(height: 10));
    }

    final dpOpen = InvoiceHubService.isDpOpen(h);
    final showAdminReady = _staff &&
        _isAdminRole &&
        !InvoiceHubService.sudahDiambil(h) &&
        !_isOnlineDelivery(h) &&
        (dpOpen ||
            _isLunasPending(h) ||
            _needsLunasQrRefresh(h) ||
            (InvoiceHubService.isLunas(h) &&
                InvoiceHubService.hasPendingRoLines(h)) ||
            (InvoiceHubService.isLunas(h) &&
                InvoiceHubService.hasReadyLines(h)));

    if (showAdminReady) {
      out.addAll(_adminReadyPanel(h));
      out.add(const SizedBox(height: 10));
    }

    if (_staff &&
        !_isAdminRole &&
        (dpOpen ||
            _isLunasPending(h) ||
            _needsLunasQrRefresh(h) ||
            InvoiceHubService.hasPendingRoLines(h)) &&
        !_isOnlineDelivery(h)) {
      out.add(_lunasPendingKaryawanHint());
      out.add(const SizedBox(height: 10));
    }

    if (_staff &&
        _customerLifecycleEnabled &&
        !_isOnlineDelivery(h)) {
      out.addAll(_confirmPanel(h));
      out.add(const SizedBox(height: 10));
    }

    if (_staff &&
        !_customerLifecycleEnabled &&
        !_isLunasPending(h) &&
        !dpOpen &&
        !showAdminReady) {
      out.add(_viewOnlyHint(h));
      out.add(const SizedBox(height: 10));
    }

    if (!_staff) {
      out.addAll(_customerActions(h));
    }

    if (out.length == 1) {
      // hanya label — jangan tampilkan kosong
      return const [];
    }
    return out;
  }

  Widget _buildBody() {
    final h = _hub!;
    final sisaGaransi = InvoiceHubService.garansiSisaHariMax(h);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // 1) Identitas nota (ringan, bukan blok navy penuh)
            _identityHeader(h),
            const SizedBox(height: 12),
            // 2) Meter fulfillment — fokus partial RO/Ready
            _sectionLabel('Pemenuhan barang'),
            _fulfillmentMeter(h),
            if (InvoiceHubService.sudahDiambil(h)) ...[
              const SizedBox(height: 8),
              Text(
                InvoiceHubService.isCaseClosed(h) ||
                        !InvoiceHubService.isGaransiClaimable(h)
                    ? 'CLEAR · Garansi mati'
                    : (sisaGaransi != null && sisaGaransi >= 0
                        ? 'CLEAR · Garansi aktif · $sisaGaransi hari lagi'
                        : 'CLEAR · Garansi aktif'),
                style: TextStyle(
                  color: InvoiceHubService.isCaseClosed(h) ||
                          !InvoiceHubService.isGaransiClaimable(h)
                      ? OptikAdminTokens.danger
                      : OptikAdminTokens.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ] else if (sisaGaransi != null) ...[
              const SizedBox(height: 8),
              Text(
                sisaGaransi >= 0
                    ? 'invoice_hub_garansi_sisa'.tr(args: ['$sisaGaransi'])
                    : 'invoice_hub_garansi_habis'.tr(),
                style: TextStyle(
                  color: sisaGaransi >= 0
                      ? OptikAdminTokens.slate
                      : OptikAdminTokens.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 18),
            // 3) CTA utama dulu
            ..._primaryActionZone(h),
            const SizedBox(height: 8),
            // 4) Items = konten utama
            _sectionLabel('invoice_hub_items'.tr()),
            _surface(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                children: [
                  ..._itemTiles(h),
                  const Divider(height: 20, color: OptikAdminTokens.lineStrong),
                  _moneyRow(
                    'Total',
                    _fmt(int.tryParse(h['total_harga']?.toString() ?? '0') ?? 0),
                    bold: true,
                  ),
                  const SizedBox(height: 6),
                  _moneyRow(
                    'Dibayar',
                    _fmt(int.tryParse(h['dibayarkan']?.toString() ?? '0') ?? 0),
                  ),
                  const SizedBox(height: 6),
                  _moneyRow(
                    'Sisa',
                    _fmt(int.tryParse(h['sisa_tagihan']?.toString() ?? '0') ?? 0),
                    valueColor:
                        (int.tryParse(h['sisa_tagihan']?.toString() ?? '0') ?? 0) >
                                0
                            ? OptikAdminTokens.danger
                            : OptikAdminTokens.success,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 5) Detail sekunder (collapse)
            _sectionLabel('Detail'),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: _surface(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  iconColor: OptikAdminTokens.navy,
                  collapsedIconColor: OptikAdminTokens.slate,
                  title: Text(
                    h['nama_pelanggan']?.toString() ?? 'Pelanggan',
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    'WhatsApp / alamat / kasir',
                    style: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                  children: [
                    ..._customerDetailRows(h, dense: true).map(
                      (w) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: w,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kasir: ${h['nama_kasir'] ?? '-'}',
                      style: const TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _surface(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                iconColor: OptikAdminTokens.navy,
                collapsedIconColor: OptikAdminTokens.slate,
                title: Text(
                  'invoice_hub_garansi'.tr(),
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                children: _garansiTiles(h),
              ),
            ),
            if (_staff) ...[
              const SizedBox(height: 18),
              _sectionLabel('Lainnya'),
              ..._staffSecondaryActions(h),
            ],
          ],
        ),
      ),
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
          color: OptikAdminTokens.navy,
          fontWeight: FontWeight.w700,
          fontSize: dense ? 14 : 15,
        ),
      ),
      Text(
        'Toko: ${h['toko_id'] ?? '-'}',
        style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13),
      ),
      if (wa != null && wa.isNotEmpty)
        Text('WhatsApp: $wa',
            style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13)),
      if (email != null && email.isNotEmpty)
        Text('Email: $email',
            style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13)),
      if (alamat != null && alamat.isNotEmpty)
        Text('Alamat: $alamat',
            style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13)),
    ];
    if (dense) return rows;
    return rows
        .map((w) => Padding(padding: const EdgeInsets.only(bottom: 2), child: w))
        .toList();
  }


  /// Panel admin: DP Barang Ready / Lunas pending / kirim ulang QR.
  List<Widget> _adminReadyPanel(Map<String, dynamic> h) {
    final dpOpen = InvoiceHubService.isDpOpen(h);
    final tracking =
        (h['tracking_status'] ?? '').toString().trim().toUpperCase();
    final dpQrReady = dpOpen && tracking == 'SIAP_PELUNASAN';
    final hasRo = InvoiceHubService.hasPendingRoLines(h);
    final hasReady = InvoiceHubService.hasReadyLines(h);

    late final String title;
    late final String body;
    late final String btn;
    if (dpOpen) {
      title = dpQrReady ? 'DP · siap pelunasan' : 'DP · menunggu barang ready';
      body = dpQrReady
          ? 'QR pelunasan sudah aktif. Bisa kirim ulang ke pelanggan, '
              'atau pelanggan scan QR DP untuk lunasi.'
          : 'Konfirmasi stok ready untuk menerbitkan QR pelunasan (DP). '
              'Setelah lunas → langsung board READY (QR pengambilan).';
      btn = dpQrReady
          ? 'Kirim ulang QR pelunasan'
          : hasRo
              ? 'Tandai RO ready & kirim QR pelunasan'
              : 'Barang Ready · kirim QR pelunasan';
    } else {
      final lunasPending = _isLunasPending(h);
      final lunasReady = _isLunasReady(h);
      if (hasRo) {
        title = hasReady
            ? 'Partial · RO masih pending'
            : 'Partial · RO pending (belum Ready)';
        body = hasReady
            ? 'Ambil item READY lewat scan QR LUNAS, atau tandai RO siap '
                'lalu refresh QR pengambilan.'
            : 'Masih ada item RO. Tandai RO ready dulu — QR pengambilan '
                'akan di-refresh untuk item itu. '
                '(Email/WA boleh gagal; QR di app tetap valid.)';
        btn = 'Tandai RO ready & kirim QR';
      } else if (lunasPending) {
        title = 'Lunas · menunggu konfirmasi READY';
        body = 'Item boleh sudah Ready di gudang, tapi QR pengambilan belum aktif '
            'sampai admin konfirmasi Barang Ready → board READY.';
        btn = hasReady
            ? 'Barang Ready · terbitkan QR READY'
            : 'Konfirmasi ready & terbitkan QR READY';
      } else if (lunasReady) {
        title = 'Siap diambil (READY)';
        body = 'QR pengambilan aktif. Bisa kirim ulang ke pelanggan. '
            'Setelah serah terima → board CLEAR (Garansi aktif / mati). '
            '(Email/WA boleh gagal; QR di dialog tetap valid.)';
        btn = 'Kirim ulang QR pengambilan';
      } else {
        title = 'Konfirmasi barang';
        body = 'Konfirmasi stok ready dan terbitkan QR pelanggan.';
        btn = 'Konfirmasi ready & kirim QR';
      }
    }

    return [
      _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: OptikAdminTokens.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                color: OptikAdminTokens.slate,
                height: 1.4,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : () => _confirmGlassesReady(h),
              style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.navy,
                foregroundColor: OptikAdminTokens.snow,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: Text(
                btn,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _lunasPendingKaryawanHint() {
    final dp = _hub != null && InvoiceHubService.isDpOpen(_hub!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OptikAdminTokens.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikAdminTokens.warning.withOpacity(0.35)),
      ),
      child: Text(
        dp
            ? 'DP — Barang Ready & QR pelunasan hanya di web admin. '
                'Setelah ready, pelanggan scan QR DP untuk lunasi → READY.'
            : 'Lunas pending — Barang Ready hanya di web admin. '
                'Setelah admin konfirmasi, customer menerima QR LUNAS ready.',
        style: const TextStyle(color: OptikAdminTokens.slate, height: 1.4),
      ),
    );
  }

  Widget _viewOnlyHint(Map<String, dynamic> h) {
    final raw = (widget.rawScan ?? '').trim();
    final needed = InvoiceHubService.isDpOpen(h)
        ? 'DP (pelunasan)'
        : InvoiceHubService.sudahDiambil(h)
            ? 'CLAIM (klaim garansi)'
            : _isLunasReady(h)
                ? 'LUNAS ready (serah terima)'
                : 'LUNAS ready (setelah admin konfirmasi barang ready)';

    String why;
    if (raw.isEmpty) {
      why = 'Hub dibuka tanpa scan QR pelanggan (dari detail/menu).';
    } else if (ObrTxn.parse(raw) != null) {
      why = 'Yang di-scan: QR toko (OBRTXN) — hanya untuk lihat detail.';
    } else if (raw.contains('http') || raw.contains('optikbriski://')) {
      why = 'Yang di-scan: link nota — bukan QR tindakan.';
    } else if (ObrInvoice.parse(raw) != null &&
        !InvoiceLink.isCustomerLifecycleQr(raw)) {
      why = 'QR invoice tanpa token fase — bukan QR pelanggan aktif.';
    } else {
      why = 'QR belum dikenali sebagai OBRINV pelanggan bertoken.';
    }

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Belum ada tindakan lifecycle',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$why\n\n'
            'Aksi pelunasan / serah terima / klaim hanya setelah '
            'scan QR pelanggan fase $needed (email / WA / Member / print). '
            'Tidak bisa dibuka dari token di database.',
            style: const TextStyle(
              color: OptikAdminTokens.slate,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => InvoiceHubPage.openScanner(
                      context,
                      profile: widget.profile ?? _profileOrToko,
                    ),
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
            label: Text(
              'Scan QR $needed',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
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
          'Setelah bayar sukses: QR DP hangus. '
          'Jika barang sudah ready → QR LUNAS; jika belum → menunggu konfirmasi ready.';
      yesLabel = 'Ya, buka payment gateway';
      onYes = () => _settleDpConfirmed(h);
    } else if (phase == 'LUNAS') {
      if (_isLunasPending(h) || !InvoiceHubService.hasReadyLines(h)) {
        final noReady = !InvoiceHubService.hasReadyLines(h);
        return [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OptikAdminTokens.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikAdminTokens.warning.withOpacity(0.35)),
            ),
            child: Text(
              noReady
                  ? 'Tidak ada item READY untuk diserahkan.\n'
                      'Tandai RO ready dulu, lalu scan ulang QR LUNAS pelanggan '
                      'yang baru dikirim.'
                  : 'QR LUNAS ready belum aktif.\n'
                      'Admin harus konfirmasi barang ready dulu.',
              style: const TextStyle(color: OptikAdminTokens.slate, height: 1.4),
            ),
          ),
        ];
      }
      title = 'Konfirmasi serah terima';
      question =
          'Pilih produk yang diambil sekarang.\n\n'
          'Item READY bisa dicentang sebagian (tidak wajib ambil semua). '
          'RO pending tidak bisa dipilih. Yang ditunda / RO bisa scan lagi nanti.\n'
          'Lanjut → pilih item → scan barcode karyawan · '
          'garansi ${GaransiService.garansiHari} hari aktif per item terpilih.';
      yesLabel = 'Pilih item & serahkan';
      onYes = () => _handoverConfirmed(h);
    } else if (phase == 'CLAIM') {
      if (InvoiceHubService.isCaseClosed(h)) {
        return [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OptikAdminTokens.danger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OptikAdminTokens.danger.withOpacity(0.4)),
            ),
            child: const Text(
              'CLEAR · Garansi mati\n'
              'Masa garansi habis, sudah diklaim, atau QR CLAIM sudah dipakai. '
              'Tidak ada tindak lanjut.',
              style: TextStyle(color: OptikAdminTokens.slate, height: 1.4),
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
      _surface(
        color: OptikAdminTokens.bgMid,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              question,
              style: const TextStyle(
                color: OptikAdminTokens.slate,
                fontSize: 13,
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
                      foregroundColor: OptikAdminTokens.slate,
                      side: const BorderSide(color: OptikAdminTokens.lineStrong),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : onYes,
                    style: FilledButton.styleFrom(
                      backgroundColor: OptikAdminTokens.navy,
                      foregroundColor: OptikAdminTokens.snow,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: OptikAdminTokens.snow,
                            ),
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
        const Text('Tidak ada item',
            style: TextStyle(color: OptikAdminTokens.slate)),
      ];
    }
    final list = items.toList();
    return [
      for (var i = 0; i < list.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: OptikAdminTokens.line),
        Builder(builder: (_) {
          final it = Map<String, dynamic>.from(list[i] as Map);
          final st =
              (it['fulfillment_status'] ?? 'READY').toString().toUpperCase();
          final badge = switch (st) {
            'PENDING_RO' || 'PENDING' => 'RO pending',
            'DIAMBIL' => 'Diambil',
            _ => 'Ready',
          };
          final badgeColor = switch (st) {
            'PENDING_RO' || 'PENDING' => OptikAdminTokens.warning,
            'DIAMBIL' => OptikAdminTokens.success,
            _ => OptikAdminTokens.navy,
          };
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (it['nama_produk'] ?? '-').toString(),
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${it['tipe_produk'] ?? '-'} × ${it['qty'] ?? 1}'
                        '${_staff && it['subtotal'] != null ? ' · Rp ${it['subtotal']}' : ''}',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _pill(badge, color: badgeColor),
              ],
            ),
          );
        }),
      ],
    ];
  }

  List<Widget> _garansiTiles(Map<String, dynamic> h) {
    final list = h['garansi'];
    if (list is! List || list.isEmpty) {
      return [
        Text(
          'invoice_hub_garansi_empty'.tr(),
          style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13),
        ),
      ];
    }
    return list.map((raw) {
      final g = Map<String, dynamic>.from(raw as Map);
      final st = (g['status'] ?? '-').toString();
      final stLabel = GaransiService.statusLabel(g);
      final stColor = st == 'aktif'
          ? OptikAdminTokens.success
          : OptikAdminTokens.warning;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${g['nama_produk'] ?? '-'}',
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${g['jenis_garansi'] ?? '-'} · '
                    '${g['tanggal_mulai'] ?? '—'} → ${g['tanggal_akhir'] ?? '—'}'
                    '${g['klaim_digunakan'] == true ? ' · klaim dipakai' : ''}',
                    style: const TextStyle(
                      color: OptikAdminTokens.slate,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            _pill(stLabel, color: stColor),
          ],
        ),
      );
    }).toList();
  }

  /// Aksi sekunder (detail / pembuat / rating) — di bawah panel konfirmasi.
  List<Widget> _staffSecondaryActions(Map<String, dynamic> h) {
    final saleId = h['sale_id']?.toString();
    final inv = h['no_invoice']?.toString() ?? '';

    return [
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
        style: const TextStyle(
          color: OptikAdminTokens.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        h['nama_pembuat_kacamata'] != null
            ? '${'invoice_hub_pembuat_current'.tr()}: ${h['nama_pembuat_kacamata']}'
            : 'invoice_hub_pembuat_empty'.tr(),
        style: TextStyle(
            color: OptikAdminTokens.slate.withOpacity(0.55), fontSize: 12.5),
      ),
      const SizedBox(height: 6),
      Text(
        _labJobStatusLabel(h),
        style: TextStyle(
          color: OptikAdminTokens.slate.withOpacity(0.7),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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

  String _labJobStatusLabel(Map<String, dynamic> h) {
    final st = (h['lab_job_status'] ?? '').toString().toUpperCase();
    final nama = h['lab_job_claimed_nama']?.toString() ??
        h['nama_pembuat_kacamata']?.toString();
    if (st.isEmpty && h['lab_job'] == null) {
      return '${'invoice_hub_lab_status'.tr()}: ${'invoice_hub_lab_none'.tr()}';
    }
    switch (st) {
      case 'OPEN':
        return '${'invoice_hub_lab_status'.tr()}: ${'invoice_hub_lab_open'.tr()}';
      case 'CLAIMED':
        return '${'invoice_hub_lab_status'.tr()}: ${'invoice_hub_lab_claimed'.tr(args: [nama ?? '-'])}';
      case 'DONE':
        return '${'invoice_hub_lab_status'.tr()}: ${'invoice_hub_lab_done'.tr()}';
      default:
        return '${'invoice_hub_lab_status'.tr()}: ${st.isEmpty ? '-' : st}';
    }
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
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
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

    final result = await showAdminPicker<String>(
      context: context,
      title: 'invoice_hub_pick_pembuat'.tr(),
      options: list
          .map(
            (k) => AdminPickerOption<String>(
              value: k['id'].toString(),
              label: k['nama']?.toString() ?? '-',
              subtitle: k['jabatan']?.toString(),
              icon: Icons.engineering_rounded,
            ),
          )
          .toList(),
      headerIcon: Icons.engineering_rounded,
      searchable: list.length > 6,
    );
    if (result == null || result.value == null || !mounted) return;

    try {
      await _svc.setPembuat(
        noInvoice: inv,
        karyawanId: result.value!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('invoice_hub_pembuat_ok'.tr()),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    }
  }

  List<Widget> _customerActions(Map<String, dynamic> h) {
    final googleUrl = h['google_review_url']?.toString().trim() ?? '';
    return [
      Text(
        'invoice_hub_customer_actions'.tr(),
        style: const TextStyle(
          color: OptikAdminTokens.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: OptikAdminTokens.slate,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'invoice_hub_customer_info'.tr(),
          style: TextStyle(
            color: OptikAdminTokens.slate,
            height: 1.4,
            fontSize: 13,
          ),
        ),
      ),
      const SizedBox(height: 14),
      _actionBtn(
        icon: Icons.reviews_rounded,
        label: 'invoice_hub_btn_google'.tr(),
        color: OptikAdminTokens.ice,
        foreground: OptikAdminTokens.navy,
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
          color: OptikAdminTokens.slate.withOpacity(0.45),
          fontSize: 12,
          height: 1.35,
        ),
      ),
      if (h['foto_hasil_url'] != null) ...[
        const SizedBox(height: 16),
        Text(
          'invoice_hub_foto_hasil'.tr(),
          style: const TextStyle(
            color: OptikAdminTokens.navy,
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
              style: TextStyle(color: OptikAdminTokens.slate.withOpacity(0.4)),
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
          style: TextStyle(color: OptikAdminTokens.slate.withOpacity(0.4), fontSize: 12),
        ),
      ];
    }
    return [
      Text(
        'invoice_hub_rating_title'.tr(),
        style: const TextStyle(
          color: OptikAdminTokens.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      ...list.map((raw) {
        final r = Map<String, dynamic>.from(raw as Map);
        return Text(
          '• ${r['peran']}: ${r['nama_karyawan'] ?? '-'} → ${r['skor']}/5',
          style: TextStyle(color: OptikAdminTokens.slate.withOpacity(0.6), fontSize: 12.5),
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
    final primary = color != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: primary
            ? FilledButton.icon(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: foreground ?? OptikAdminTokens.snow,
                  disabledBackgroundColor: OptikAdminTokens.line,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(icon, size: 20),
                label: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              )
            : OutlinedButton.icon(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: OptikAdminTokens.navy,
                  side: const BorderSide(color: OptikAdminTokens.lineStrong),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(icon, size: 20),
                label: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
      ),
    );
  }
}
