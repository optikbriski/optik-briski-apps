import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bootstrap.dart';
import 'pos_midtrans_pay_page.dart';

class PosMidtransResult {
  const PosMidtransResult({
    required this.ok,
    this.settled = false,
    this.midtransOrderId,
    this.paymentType,
    this.error,
  });

  final bool ok;
  final bool settled;
  final String? midtransOrderId;
  final String? paymentType;
  final String? error;
}

/// Snap Midtrans untuk kasir / pelunasan. Bukan tagihan etalase Rekasa.
class PosMidtrans {
  PosMidtrans._();

  static bool usesGateway(String method) {
    switch (method.trim().toLowerCase()) {
      case 'qris':
      case 'transfer':
      case 'debit':
      case 'midtrans':
        return true;
      default:
        return false;
    }
  }

  static String labelForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('qris') || t.contains('gopay') || t.contains('shopee')) {
      return 'QRIS';
    }
    if (t.contains('bank') || t.contains('va') || t.contains('transfer')) {
      return 'Transfer';
    }
    if (t.contains('credit') || t.contains('debit') || t.contains('card')) {
      return 'Debit';
    }
    if (t == 'dev_mock') return 'QRIS';
    return 'QRIS';
  }

  static Future<PosMidtransResult> chargeAndWait({
    required BuildContext context,
    required int amountIdr,
    required String purpose,
    required String tokoId,
    String? saleId,
    String? invoiceNo,
    String? customerName,
    String? phone,
  }) async {
    try {
      final res = await supabase.functions.invoke(
        'pos-midtrans-create',
        body: {
          'amount_idr': amountIdr,
          'purpose': purpose,
          'toko_id': tokoId,
          if (saleId != null && saleId.isNotEmpty) 'sale_id': saleId,
          if (invoiceNo != null) 'invoice_no': invoiceNo,
          if (customerName != null) 'customer_name': customerName,
          if (phone != null) 'phone': phone,
        },
      );
      final data = res.data;
      if (data is! Map) {
        return const PosMidtransResult(
          ok: false,
          error: 'Respons Midtrans kasir tidak valid',
        );
      }
      final map = Map<String, dynamic>.from(data);
      if (map['ok'] != true) {
        return PosMidtransResult(
          ok: false,
          error: '${map['error'] ?? 'Gagal membuat bayar Midtrans'}',
        );
      }
      final mid = '${map['midtrans_order_id'] ?? ''}';
      if (mid.isEmpty) {
        return const PosMidtransResult(ok: false, error: 'order_id POS kosong');
      }

      if (map['mock_payment'] == true) {
        if (!context.mounted) {
          return const PosMidtransResult(ok: false, error: 'Dibatalkan');
        }
        final mock = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bayar uji (tanpa Midtrans)'),
            content: Text(
              'MIDTRANS_SERVER_KEY belum di Edge. '
              'Lunasi uji ${amountIdr.toString()} untuk $purpose?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Bayar uji'),
              ),
            ],
          ),
        );
        if (mock != true) {
          return const PosMidtransResult(
            ok: false,
            error: 'Pembayaran Midtrans dibatalkan',
          );
        }
        final raw = await supabase.rpc(
          'dev_fulfill_pos_payment',
          params: {'p_midtrans_order_id': mid},
        );
        final paid = raw is Map ? Map<String, dynamic>.from(raw) : const {};
        if (paid['ok'] != true) {
          return PosMidtransResult(
            ok: false,
            error: '${paid['error'] ?? 'Bayar uji gagal. Apply SQL 000014.'}',
          );
        }
        return PosMidtransResult(
          ok: true,
          settled: true,
          midtransOrderId: mid,
          paymentType: '${paid['payment_type'] ?? 'DEV_MOCK'}',
        );
      }

      final url = '${map['redirect_url'] ?? ''}';
      if (url.isEmpty) {
        return const PosMidtransResult(
          ok: false,
          error: 'redirect Midtrans kosong',
        );
      }
      if (!context.mounted) {
        return const PosMidtransResult(ok: false, error: 'Dibatalkan');
      }
      final settled = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PosMidtransPayPage(
            redirectUrl: url,
            midtransOrderId: mid,
          ),
        ),
      );
      if (settled != true) {
        return const PosMidtransResult(
          ok: false,
          error: 'Pembayaran Midtrans belum selesai',
        );
      }
      final st = await supabase.rpc(
        'get_pos_payment',
        params: {'p_midtrans_order_id': mid},
      );
      final row = st is Map ? Map<String, dynamic>.from(st) : const {};
      return PosMidtransResult(
        ok: true,
        settled: true,
        midtransOrderId: mid,
        paymentType: '${row['payment_type'] ?? 'Midtrans'}',
      );
    } catch (e) {
      debugPrint('pos midtrans: $e');
      return PosMidtransResult(ok: false, error: '$e');
    }
  }

  static Future<void> linkSale(String midtransOrderId, String saleId) async {
    try {
      await supabase.rpc(
        'link_pos_payment_sale',
        params: {
          'p_midtrans_order_id': midtransOrderId,
          'p_sale_id': saleId,
        },
      );
    } catch (e) {
      debugPrint('link_pos_payment_sale: $e');
    }
  }
}
