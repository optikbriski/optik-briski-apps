import 'training_mode.dart';
import 'training_sandbox_store.dart';

/// Sandbox stubs for PostgREST `/rest/v1/rpc/*` used by Karyawan (and shared).
///
/// Unknown RPCs: mutating → empty success; read-like names → try local tables.
class TrainingRpcStubs {
  TrainingRpcStubs._();

  /// Returns JSON-encodable body for the RPC, or `null` to fall through
  /// (should not happen while training — caller uses default stub).
  static Future<Object?> handle(
    String fn,
    Map<String, dynamic>? params,
  ) async {
    switch (fn) {
      case 'issue_attendance_qr_token':
        return _issueAttendanceQr(params);
      case 'validate_attendance_qr_token':
        return _validateAttendanceQr(params);
      case 'get_invoice_hub':
        return _getInvoiceHub(params);
      case 'set_invoice_pembuat':
        return _setInvoicePembuat(params);
      case 'submit_invoice_rating':
        return _submitInvoiceRating(params);
      case 'allocate_export_salinan':
        // Consumer expects a positive int (salinan number), not a Map.
        return 1;
      default:
        return _defaultStub(fn, params);
    }
  }

  static Map<String, dynamic> _issueAttendanceQr(Map<String, dynamic>? p) {
    final tokoId = (p?['p_toko_id'] ?? TrainingMode.instance.tokoId ?? '')
        .toString();
    final ttl = (p?['p_ttl_seconds'] as num?)?.toInt() ?? 120;
    final now = DateTime.now();
    final expires = now.add(Duration(seconds: ttl));
    final id = 'sb_qr_${now.microsecondsSinceEpoch}';
    final token = 'tr_tok_$id';
    final payload = 'TRAINING|$tokoId|$token|${expires.millisecondsSinceEpoch}';
    return {
      'id': id,
      'toko_id': tokoId,
      'token': token,
      'payload': payload,
      'expires_at': expires.toIso8601String(),
      'ttl_seconds': ttl,
      'ok': true,
      'training': true,
    };
  }

  static Map<String, dynamic> _validateAttendanceQr(Map<String, dynamic>? p) {
    final raw = (p?['p_payload'] ?? '').toString().trim();
    final locked = TrainingMode.instance.tokoId ?? '';
    if (raw.startsWith('TRAINING|')) {
      final parts = raw.split('|');
      final tokoId = parts.length > 1 ? parts[1] : locked;
      final token = parts.length > 2 ? parts[2] : 'tr_tok';
      var expires = DateTime.now().add(const Duration(minutes: 5));
      if (parts.length > 3) {
        final ms = int.tryParse(parts[3]);
        if (ms != null) {
          expires = DateTime.fromMillisecondsSinceEpoch(ms);
        }
      }
      return {
        'ok': true,
        'token_id': token,
        'toko_id': tokoId.isNotEmpty ? tokoId : locked,
        'expires_at': expires.toIso8601String(),
        'training': true,
      };
    }
    // Accept any payload in training so live QR codes can still be practiced.
    return {
      'ok': true,
      'token_id': 'sb_qr_accept',
      'toko_id': locked,
      'expires_at':
          DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      'training': true,
    };
  }

  static Future<Map<String, dynamic>?> _getInvoiceHub(
    Map<String, dynamic>? p,
  ) async {
    final inv = (p?['p_no_invoice'] ?? '').toString().trim();
    if (inv.isEmpty) return null;
    final store = TrainingSandboxStore.instance;
    final sale = await store.selectOne('sales', where: {'no_invoice': inv});
    if (sale == null) {
      return {
        'role_view': 'staff',
        'no_invoice': inv,
        'toko_id': TrainingMode.instance.tokoId,
        'items': <dynamic>[],
        'garansi': <dynamic>[],
        'ratings': <dynamic>[],
        'training': true,
        'tracking_status': 'DIPROSES_DI_CABANG',
      };
    }
    final saleId = sale['id'];
    final items = await store.select('sales_items', where: {'sale_id': saleId});
    final garansi =
        await store.select('garansi_kartu', where: {'sale_id': saleId});
    final ratings = await store.select(
      'invoice_ratings',
      where: {'no_invoice': inv},
    );
    return {
      'role_view': 'staff',
      'sale_id': saleId,
      'no_invoice': sale['no_invoice'],
      'toko_id': sale['toko_id'],
      'nama_pelanggan': sale['nama_pelanggan'],
      'nama_kasir': sale['nama_kasir'],
      'status_pembayaran': sale['status_pembayaran'],
      'tracking_status': sale['tracking_status'],
      'diambil_at': sale['diambil_at'],
      'foto_hasil_url': sale['foto_hasil_url'],
      'created_at': sale['created_at'],
      'total_harga': sale['total_harga'],
      'dibayarkan': sale['dibayarkan'],
      'sisa_tagihan': sale['sisa_tagihan'],
      'metode_pembayaran': sale['metode_pembayaran'],
      'no_wa': sale['no_wa'],
      'items': items,
      'garansi': garansi,
      'ratings': ratings,
      'training': true,
    };
  }

  static Future<Map<String, dynamic>> _setInvoicePembuat(
    Map<String, dynamic>? p,
  ) async {
    final inv = (p?['p_no_invoice'] ?? '').toString();
    final kid = (p?['p_karyawan_id'] ?? '').toString();
    await TrainingSandboxStore.instance.insert('invoice_pembuat', {
      'no_invoice': inv,
      'karyawan_id': kid,
    });
    if (inv.isNotEmpty) {
      await TrainingSandboxStore.instance.update(
        'sales',
        {'pembuat_id': kid},
        where: {'no_invoice': inv},
      );
    }
    return {'ok': true, 'training': true};
  }

  static Future<Map<String, dynamic>> _submitInvoiceRating(
    Map<String, dynamic>? p,
  ) async {
    await TrainingSandboxStore.instance.insert('invoice_ratings', {
      'no_invoice': (p?['p_no_invoice'] ?? '').toString(),
      'peran': (p?['p_peran'] ?? '').toString(),
      'skor': p?['p_skor'],
      'komentar': p?['p_komentar'],
    });
    return {'ok': true, 'training': true};
  }

  static Map<String, dynamic> _defaultStub(
    String fn,
    Map<String, dynamic>? params,
  ) {
    // Safe success for unknown mutating RPCs so Karyawan UI continues.
    return {
      'ok': true,
      'training': true,
      'rpc': fn,
      'params': params,
    };
  }
}
