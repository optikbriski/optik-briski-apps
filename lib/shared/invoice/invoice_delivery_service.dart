import 'package:supabase_flutter/supabase_flutter.dart';

import '../qr/obr_codes.dart';
import 'invoice_link.dart';
import 'invoice_lifecycle_service.dart';

/// Kirim nota + QR fase aktif ke email & WhatsApp pelanggan (sinkron APK Member).
class InvoiceDeliveryService {
  InvoiceDeliveryService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  /// Pastikan token, lalu kirim email (PDF opsional) + WA.
  Future<({bool email, bool wa, String? payload, String? phase})> deliver({
    required Map<String, dynamic> sale,
    String? pdfBase64,
    bool sendEmail = true,
    bool sendWa = true,
  }) async {
    var row = Map<String, dynamic>.from(sale);
    final saleId = row['id']?.toString();
    if (saleId != null && saleId.isNotEmpty) {
      try {
        row = await InvoiceLifecycleService(client: _db).ensureTokens(saleId);
      } catch (_) {}
    }

    final payload = InvoiceLifecycleService.customerQrPayload(row) ??
        InvoiceLink.encodeFromSale(row);
    final phase = _phaseLabel(row);
    final invoice = (row['no_invoice'] ?? '').toString();
    final name = (row['nama_pelanggan'] ?? 'Pelanggan').toString();
    final email = (row['email_pelanggan'] ?? '').toString().trim();
    final phone = (row['no_wa'] ?? '').toString().trim();
    final total = (row['total_harga'] ?? 0).toString();
    final hubUrl = InvoiceLink.encodeHttps(invoice);
    final tip = _phaseTip(phase);

    var emailOk = false;
    var waOk = false;

    if (sendEmail && email.contains('@')) {
      try {
        await _db.functions.invoke(
          'send-invoice-email',
          body: {
            'invoice': invoice,
            'email': email,
            'customerName': name,
            'netTotal': total,
            if (pdfBase64 != null) 'pdfBase64': pdfBase64,
            'qrPayload': payload,
            'qrPhase': phase,
            'hubUrl': hubUrl,
            'phaseTip': tip,
            'tokoId': row['toko_id'] ?? '',
          },
        );
        emailOk = true;
      } catch (_) {}
    }

    if (sendWa && phone.length >= 8) {
      try {
        await _db.functions.invoke(
          'send-invoice-whatsapp',
          body: {
            'invoice': invoice,
            'phone': phone,
            'customerName': name,
            'netTotal': total,
            'qrPayload': payload,
            'qrPhase': phase,
            'hubUrl': hubUrl,
            'phaseTip': tip,
            'sisaTagihan': row['sisa_tagihan'] ?? 0,
            'statusPembayaran': row['status_pembayaran'] ?? '',
            'tokoId': row['toko_id'] ?? '',
          },
        );
        waOk = true;
      } catch (_) {}
    }

    return (email: emailOk, wa: waOk, payload: payload, phase: phase);
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
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    if (pay == 'DP' || sisa > 0) return 'DP';
    final diambil = sale['diambil_at'] != null ||
        (sale['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');
    return diambil ? 'CLAIM' : 'LUNAS';
  }

  static String _phaseTip(String phase) {
    switch (phase) {
      case 'DP':
        return 'Wajib tunjukkan QR ini di kasir cabang tempat beli untuk '
            'pelunasan. QR sama di email, WhatsApp, dan APK Member.';
      case 'LUNAS':
        return 'Wajib scan QR ini di POS cabang tempat beli saat ambil barang. '
            'QR sama di email, WhatsApp, dan APK Member.';
      case 'CLAIM':
        return 'Untuk klaim, datang ke cabang membawa barang + QR CLAIM '
            '(email / WA / APK Member — kode sama).';
      default:
        return 'QR nota sinkron di email, WhatsApp, dan APK Member.';
    }
  }
}
