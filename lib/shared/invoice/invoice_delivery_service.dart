import 'package:supabase_flutter/supabase_flutter.dart';

import '../member/member_realtime.dart';
import '../qr/obr_codes.dart';
import '../tenant/tenant_service.dart';
import '../whatsapp_launcher.dart';
import 'invoice_delivery_result.dart';
import 'invoice_lifecycle_rules.dart';
import 'invoice_link.dart';
import 'invoice_lifecycle_service.dart';

/// Mode kirim nota ke customer.
enum InvoiceDeliveryMode {
  /// Setelah bayar DP / lunas pending: konfirmasi + invoice, tanpa QR.
  paymentConfirm,

  /// Setelah admin "Barang Ready": pesan siap + invoice + QR fase.
  goodsReady,

  /// Kirim nota + QR fase aktif (default / pelunasan / ulang kirim).
  withQr,
}

/// Kirim nota (+ QR bila mode mengizinkan) ke email & WhatsApp (+ sinyal Member).
class InvoiceDeliveryService {
  InvoiceDeliveryService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<InvoiceDeliveryResult> deliver({
    required Map<String, dynamic> sale,
    String? pdfBase64,
    bool sendEmail = true,
    bool sendWa = true,
    InvoiceDeliveryMode mode = InvoiceDeliveryMode.withQr,
    /// Paksa payload QR (mis. CLAIM setelah partial, meski LUNAS masih aktif).
    String? qrPayloadOverride,
  }) async {
    var row = Map<String, dynamic>.from(sale);
    final saleId = row['id']?.toString();
    final includeQr = mode != InvoiceDeliveryMode.paymentConfirm;
    final override = (qrPayloadOverride ?? '').trim();

    if (includeQr &&
        override.isEmpty &&
        saleId != null &&
        saleId.isNotEmpty) {
      try {
        row = await InvoiceLifecycleService(client: _db).ensureTokens(saleId);
      } catch (_) {}
    }

    final payload = !includeQr
        ? ''
        : (override.isNotEmpty
            ? override
            : (InvoiceLifecycleService.customerQrPayload(row) ??
                InvoiceLink.encodeFromSale(row)));
    final lifecyclePayload =
        includeQr && InvoiceLink.isCustomerLifecycleQr(payload) ? payload : '';
    final phase = !includeQr
        ? _paymentConfirmPhase(row)
        : (ObrInvoice.parse(lifecyclePayload)?.phase ?? _phaseLabel(row));
    final invoice = (row['no_invoice'] ?? '').toString();
    final name = (row['nama_pelanggan'] ?? 'Pelanggan').toString();
    final email = (row['email_pelanggan'] ?? '').toString().trim();
    final phone = (row['no_wa'] ?? '').toString().trim();
    final total = (row['total_harga'] ?? 0).toString();
    final hubUrl = InvoiceLink.encodeHttps(invoice);
    final headline = _headline(mode: mode, name: name, row: row);
    final tip = includeQr ? _phaseTip(phase) : _paymentConfirmTip(row);

    var emailOk = false;
    var waOk = false;
    var emailSkipped = !sendEmail || !email.contains('@');
    var waSkipped = !sendWa || phone.length < 8;
    String? emailError;
    String? waError;

    if (!emailSkipped) {
      try {
        final res = await _db.functions.invoke(
          'send-invoice-email',
          body: {
            'invoice': invoice,
            'email': email,
            'customerName': name,
            'netTotal': total,
            if (pdfBase64 != null) 'pdfBase64': pdfBase64,
            'qrPayload': lifecyclePayload,
            'qrPhase': phase,
            'hubUrl': hubUrl,
            'phaseTip': tip,
            'headlineMessage': headline,
            'includeQr': includeQr && lifecyclePayload.isNotEmpty,
            'tokoId': row['toko_id'] ?? '',
          },
        );
        if (res.status >= 400) {
          emailError = 'HTTP ${res.status}';
        } else {
          emailOk = true;
        }
      } catch (e) {
        emailError = e.toString();
      }
    }

    if (!waSkipped) {
      try {
        final res = await _db.functions.invoke(
          'send-invoice-whatsapp',
          body: {
            'invoice': invoice,
            'phone': phone,
            'customerName': name,
            'netTotal': total,
            'qrPayload': lifecyclePayload,
            'qrPhase': phase,
            'hubUrl': hubUrl,
            'phaseTip': tip,
            'headlineMessage': headline,
            'includeQr': includeQr && lifecyclePayload.isNotEmpty,
            'sisaTagihan': row['sisa_tagihan'] ?? 0,
            'statusPembayaran': row['status_pembayaran'] ?? '',
            'tokoId': row['toko_id'] ?? '',
          },
        );
        if (res.status >= 400) {
          waError = 'HTTP ${res.status}';
        } else {
          waOk = true;
        }
      } catch (e) {
        waError = e.toString();
      }
    }

    // Sinyal ke APK Member (notif lokal + refresh UI).
    try {
      await _pushMemberAlert(
        invoice: invoice,
        phone: phone,
        mode: mode,
        headline: headline,
        tip: tip,
        includeQr: includeQr && lifecyclePayload.isNotEmpty,
      );
    } catch (_) {}

    return InvoiceDeliveryResult(
      emailOk: emailOk,
      waOk: waOk,
      emailSkipped: emailSkipped,
      waSkipped: waSkipped,
      emailError: emailError,
      waError: waError,
      payload: lifecyclePayload.isEmpty ? null : lifecyclePayload,
      phase: phase,
      invoice: invoice,
    );
  }

  Future<void> _pushMemberAlert({
    required String invoice,
    required String phone,
    required InvoiceDeliveryMode mode,
    required String headline,
    required String tip,
    required bool includeQr,
  }) async {
    final digits = normalizeWaNumber(phone);
    if (digits.length < 8 || invoice.trim().isEmpty) return;

    final kind = switch (mode) {
      InvoiceDeliveryMode.paymentConfirm => 'payment_confirm',
      InvoiceDeliveryMode.goodsReady => 'goods_ready',
      InvoiceDeliveryMode.withQr => 'with_qr',
    };
    final title = switch (mode) {
      InvoiceDeliveryMode.paymentConfirm => 'Konfirmasi pembayaran · $invoice',
      InvoiceDeliveryMode.goodsReady => includeQr
          ? 'Pesanan siap · QR tersedia · $invoice'
          : 'Pesanan siap · $invoice',
      InvoiceDeliveryMode.withQr => 'Update nota · $invoice',
    };

    final body = '$headline\n$tip';
    await _db.rpc('create_member_order_alert', params: withTenant({
      'p_no_invoice': invoice.trim(),
      'p_phone': digits,
      'p_title': title,
      'p_body': body,
      'p_kind': kind,
    }));

    // Dorong APK Member secara instan (Broadcast), tidak menunggu poll.
    await MemberRealtime.broadcastOrderUpdate(
      phone: digits,
      invoice: invoice.trim(),
      title: title,
      body: body,
      kind: kind,
    );
  }

  static String _headline({
    required InvoiceDeliveryMode mode,
    required String name,
    required Map<String, dynamic> row,
  }) {
    switch (mode) {
      case InvoiceDeliveryMode.paymentConfirm:
        final pay = ObrInvoice.normalizePayStatus(
          row['status_pembayaran']?.toString(),
        );
        final sisa = InvoiceLifecycleRules.moneyOf(row['sisa_tagihan']);
        if (pay == 'DP' || sisa > 0) {
          return 'Konfirmasi pembayaran DP atas nama $name. '
              'Nota terlampir. QR akan dikirim saat pesanan siap.';
        }
        return 'Konfirmasi pembayaran lunas atas nama $name. '
            'Nota terlampir. QR pengambilan akan dikirim saat barang ready.';
      case InvoiceDeliveryMode.goodsReady:
        final pay = ObrInvoice.normalizePayStatus(
          row['status_pembayaran']?.toString(),
        );
        final sisa = InvoiceLifecycleRules.moneyOf(row['sisa_tagihan']);
        if (pay == 'DP' || sisa > 0) {
          return 'Pesanan atas nama $name sudah bisa untuk melakukan '
              'pelunasan dan pengambilan barang.';
        }
        return 'Pesanan atas nama $name sudah bisa diambil.';
      case InvoiceDeliveryMode.withQr:
        return 'Halo $name, nota digital Anda terlampir.';
    }
  }

  static String _paymentConfirmPhase(Map<String, dynamic> sale) {
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = InvoiceLifecycleRules.moneyOf(sale['sisa_tagihan']);
    if (pay == 'DP' || sisa > 0) return 'DP_CONFIRM';
    return 'PENDING_CONFIRM';
  }

  static String _paymentConfirmTip(Map<String, dynamic> sale) {
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = InvoiceLifecycleRules.moneyOf(sale['sisa_tagihan']);
    if (pay == 'DP' || sisa > 0) {
      return 'Ini konfirmasi pembayaran DP + nota. '
          'QR pelunasan dikirim setelah admin menandai barang ready.';
    }
    return 'Ini konfirmasi pembayaran lunas + nota. '
        'QR pengambilan dikirim setelah admin menandai barang ready.';
  }

  static String _phaseLabel(Map<String, dynamic> sale) {
    final payload = InvoiceLifecycleService.customerQrPayload(sale);
    if (payload != null) {
      final p = ObrInvoice.parse(payload);
      if (p?.phase != null) return p!.phase!;
    }
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = InvoiceLifecycleRules.moneyOf(sale['sisa_tagihan']);
    if (pay == 'DP' || sisa > 0) return 'DP';
    final diambil = sale['diambil_at'] != null ||
        (sale['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');
    return diambil ? 'CLAIM' : 'LUNAS';
  }

  static String _phaseTip(String phase) {
    switch (phase) {
      case 'DP':
        return 'QR pelunasan (customer). Tunjukkan ke kasir untuk pelunasan.';
      case 'LUNAS':
        return 'QR pengambilan (customer). Tunjukkan saat ambil barang — '
            'aktifkan kartu garansi. Sama di email, WhatsApp, dan APK Member.';
      case 'CLAIM':
        return 'QR CLAIM (customer). Bawa barang + QR ini saat klaim garansi.';
      default:
        return 'QR nota sinkron di email, WhatsApp, dan APK Member.';
    }
  }
}
