import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bootstrap.dart';
import 'rekasa_store_midtrans_pay_page.dart';

class RekasaStoreMidtransResult {
  const RekasaStoreMidtransResult({
    required this.ok,
    this.mock = false,
    this.paid = false,
    this.orderId,
    this.redirectUrl,
    this.error,
  });

  final bool ok;
  final bool mock;
  final bool paid;
  final String? orderId;
  final String? redirectUrl;
  final String? error;

  static RekasaStoreMidtransResult fromMap(Map<String, dynamic> map) {
    if (map['ok'] != true) {
      return RekasaStoreMidtransResult(
        ok: false,
        error: '${map['error'] ?? 'Gagal membuat bayar Midtrans'}',
      );
    }
    if (map['mock_payment'] == true) {
      return RekasaStoreMidtransResult(
        ok: true,
        mock: true,
        orderId: '${map['order_id'] ?? ''}',
      );
    }
    final url = '${map['redirect_url'] ?? ''}'.trim();
    final token = '${map['snap_token'] ?? ''}'.trim();
    if (url.isEmpty && token.isEmpty) {
      return const RekasaStoreMidtransResult(
        ok: false,
        error: 'Redirect Midtrans kosong',
      );
    }
    return RekasaStoreMidtransResult(
      ok: true,
      orderId: '${map['order_id'] ?? ''}',
      redirectUrl: url,
    );
  }
}

/// Snap lisensi etalase — pintu yang sama dengan situs `paket.html`.
class RekasaStoreMidtrans {
  RekasaStoreMidtrans._();

  static Future<RekasaStoreMidtransResult> chargeAndWait({
    required BuildContext context,
    required Map<String, dynamic> body,
  }) async {
    try {
      final res = await supabase.functions.invoke(
        'rekasa-midtrans-create',
        body: body,
      );
      final data = res.data;
      if (data is! Map) {
        return const RekasaStoreMidtransResult(
          ok: false,
          error: 'Respons Midtrans katalog tidak valid',
        );
      }
      final parsed = RekasaStoreMidtransResult.fromMap(
        Map<String, dynamic>.from(data),
      );
      if (!parsed.ok || parsed.mock) return parsed;

      final url = (parsed.redirectUrl ?? '').trim();
      if (url.isEmpty) {
        return const RekasaStoreMidtransResult(
          ok: false,
          error: 'Redirect Midtrans kosong',
        );
      }
      if (!context.mounted) {
        return const RekasaStoreMidtransResult(ok: false, error: 'Dibatalkan');
      }

      if (kIsWeb) {
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
        if (!context.mounted) {
          return RekasaStoreMidtransResult(
            ok: true,
            orderId: parsed.orderId,
            redirectUrl: url,
          );
        }
        final done = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Pembayaran Midtrans'),
            content: const Text(
              'Selesaikan bayar di tab Midtrans, lalu kembali ke sini.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Belum'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sudah bayar'),
              ),
            ],
          ),
        );
        return RekasaStoreMidtransResult(
          ok: true,
          paid: done == true,
          orderId: parsed.orderId,
          redirectUrl: url,
        );
      }

      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RekasaStoreMidtransPayPage(
            redirectUrl: url,
            orderId: parsed.orderId ?? '',
          ),
        ),
      );
      return RekasaStoreMidtransResult(
        ok: true,
        paid: paid == true,
        orderId: parsed.orderId,
        redirectUrl: url,
      );
    } catch (e) {
      debugPrint('rekasa store midtrans: $e');
      return RekasaStoreMidtransResult(ok: false, error: '$e');
    }
  }
}
