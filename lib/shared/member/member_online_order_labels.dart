import 'package:flutter/material.dart';

import '../theme.dart';

/// Label & warna status `online_orders` — dipakai Admin + Member.
class MemberOnlineOrderLabels {
  MemberOnlineOrderLabels._();

  static String status(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pending_payment':
        return 'Menunggu pembayaran';
      case 'paid':
        return 'Lunas · menunggu proses';
      case 'packing':
        return 'Dikemas';
      case 'ready':
        return 'Siap diambil / dikirim';
      case 'shipped':
        return 'Dalam pengiriman';
      case 'fulfilled':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      case 'expired':
        return 'Kedaluwarsa';
      default:
        return _humanizeRaw(raw);
    }
  }

  static String fulfillment(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pickup':
        return 'Ambil di toko';
      case 'delivery':
        return 'Kirim ke alamat';
      default:
        return _humanizeRaw(raw);
    }
  }

  static String _humanizeRaw(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '—';
    final upper = s.toUpperCase();
    if (RegExp(r'^[A-Z0-9_]+$').hasMatch(upper) && upper.contains('_')) {
      return upper
          .toLowerCase()
          .split('_')
          .where((p) => p.isNotEmpty)
          .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
          .join(' ');
    }
    return s;
  }

  static Color statusColor(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pending_payment':
      case 'cancelled':
      case 'expired':
        return OptikMemberTokens.danger;
      case 'paid':
      case 'packing':
        return OptikMemberTokens.warning;
      case 'ready':
      case 'shipped':
        return OptikMemberTokens.blue;
      case 'fulfilled':
        return OptikMemberTokens.success;
      default:
        return OptikMemberTokens.inkMuted;
    }
  }

  /// Tracking sales yang selaras dengan online fulfillment.
  static String salesTrackingLabel(String? tracking) {
    final t = (tracking ?? '').trim().toUpperCase();
    if (t == 'DIPROSES' || t == 'DIPROSES_DI_CABANG') {
      return 'Diproses di cabang';
    }
    if (t == 'DIKIRIM' || t == 'SHIPPED') return 'Dalam pengiriman';
    if (t == 'SIAP_DIAMBIL') return 'Siap diambil';
    if (t == 'CLEAR') return 'CLEAR · siap diambil';
    if (t == 'DIAMBIL') return 'Selesai';
    if (t.isEmpty) return 'Dalam proses';
    return _humanizeRaw(t);
  }
}
