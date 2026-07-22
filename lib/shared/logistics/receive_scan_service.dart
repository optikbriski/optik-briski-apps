import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../qr/obr_codes.dart';
import 'request_order_service.dart';

class ReceiveScanResult {
  const ReceiveScanResult({
    required this.ok,
    required this.message,
    this.resi,
    this.alreadyDone = false,
    this.verifiedByName,
    this.verifiedAt,
  });

  final bool ok;
  final String message;
  final String? resi;
  final bool alreadyDone;
  final String? verifiedByName;
  final DateTime? verifiedAt;
}

/// Scan QR surat jalan → SUCCESS + stok cabang + audit petugas.
class ReceiveScanService {
  ReceiveScanService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const openStatuses = ['WAITING', 'TRANSIT', 'PENDING'];

  static Map<String, dynamic> parseQrPayload(String raw) {
    final trimmed = raw.trim();

    // OBRDO|v1|<resi>|<tujuan> / OBRRO|v1|<resi>|<tujuan>
    final obr = parseObrLogistics(trimmed);
    if (obr != null) {
      return {
        'resi': obr.resi,
        if (obr.tujuan != null) 'tujuan': obr.tujuan,
        'kind': obr.kind,
      };
    }

    // Legacy JSON: {"resi":"DO-…","tujuan":"…"}
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return {'resi': trimmed};
  }

  static bool tokoMatches(String? tujuan, String cabangKaryawan) {
    final a = (tujuan ?? '').trim().toUpperCase();
    final b = cabangKaryawan.trim().toUpperCase();
    if (a.isEmpty || b.isEmpty) return false;
    return a == b;
  }

  Future<ReceiveScanResult> receiveFromQr({
    required String qrRaw,
    required String cabangKaryawan,
    required String verifiedById,
    required String verifiedByName,
  }) async {
    final payload = parseQrPayload(qrRaw);
    final resi = (payload['resi'] ?? payload['product_name'] ?? '')
        .toString()
        .trim();
    final tujuanQr = payload['tujuan']?.toString();

    if (resi.isEmpty) {
      return const ReceiveScanResult(
        ok: false,
        message: 'QR tidak berisi nomor resi yang valid.',
      );
    }

    if (tujuanQr != null &&
        tujuanQr.trim().isNotEmpty &&
        !tokoMatches(tujuanQr, cabangKaryawan)) {
      return ReceiveScanResult(
        ok: false,
        message:
            'Barang ini untuk $tujuanQr, bukan untuk toko Anda ($cabangKaryawan).',
        resi: resi,
      );
    }

    final row = await _client
        .from('stock_move_history')
        .select()
        .eq('product_name', resi)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) {
      return ReceiveScanResult(
        ok: false,
        message: 'Resi $resi tidak ditemukan di sistem.',
        resi: resi,
      );
    }

    final ke = (row['ke_lokasi'] ?? '').toString();
    if (!tokoMatches(ke, cabangKaryawan)) {
      return ReceiveScanResult(
        ok: false,
        message:
            'Akses ditolak. Paket ini ditujukan ke $ke, bukan $cabangKaryawan.',
        resi: resi,
      );
    }

    final status = (row['status'] ?? '').toString().toUpperCase();
    if (status == 'SUCCESS') {
      final atRaw = row['verified_at']?.toString();
      DateTime? at;
      if (atRaw != null && atRaw.isNotEmpty) {
        at = DateTime.tryParse(atRaw)?.toLocal();
      }
      final by = row['verified_by_name']?.toString();
      return ReceiveScanResult(
        ok: false,
        alreadyDone: true,
        resi: resi,
        verifiedByName: by,
        verifiedAt: at,
        message: by != null && by.isNotEmpty
            ? 'Sudah diterima oleh $by${at != null ? ' pada ${_fmt(at)}' : ''}.'
            : 'Paket ini sudah berstatus SUCCESS sebelumnya.',
      );
    }

    if (status == 'BATAL' || status == 'REJECTED') {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message: 'Paket berstatus $status dan tidak bisa diterima.',
      );
    }

    if (!openStatuses.contains(status)) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message: 'Status paket $status tidak bisa di-scan terima.',
      );
    }

    final now = DateTime.now().toUtc();
    final moveId = row['id'].toString();

    await _client.from('stock_move_history').update({
      'status': 'SUCCESS',
      'verified_by': verifiedById,
      'verified_by_name': verifiedByName,
      'verified_at': now.toIso8601String(),
    }).eq('id', moveId);

    try {
      await RequestOrderService(client: _client).markSuccessFromMove(
        stockMoveId: moveId,
        resi: resi,
      );
    } catch (_) {}

    await _injectStockToCabang(
      keterangan: row['keterangan']?.toString() ?? '',
      jumlahFlat: int.tryParse(row['jumlah']?.toString() ?? '0') ?? 0,
      tokoId: cabangKaryawan.trim().toUpperCase(),
    );

    return ReceiveScanResult(
      ok: true,
      resi: resi,
      verifiedByName: verifiedByName,
      verifiedAt: now.toLocal(),
      message:
          'Resi $resi diterima. Stok toko diperbarui. Petugas: $verifiedByName · ${_fmt(now.toLocal())}',
    );
  }

  Future<void> _injectStockToCabang({
    required String keterangan,
    required int jumlahFlat,
    required String tokoId,
  }) async {
    if (keterangan.contains('[{')) {
      try {
        final jsonPart = keterangan.substring(keterangan.indexOf('[{'));
        final items = jsonDecode(jsonPart);
        if (items is! List) return;
        for (final itm in items) {
          if (itm is! Map) continue;
          final qty = int.tryParse(itm['qty']?.toString() ?? '0') ?? 0;
          if (qty <= 0) continue;
          await _upsertProductLine(
            tokoId: tokoId,
            qty: qty,
            barcode: itm['barcode']?.toString() ?? '-',
            sku: itm['sku']?.toString(),
            nama: itm['nama']?.toString() ?? '-',
            hargaJual: itm['harga_jual'] ?? itm['harga'] ?? 0,
            hargaModal: itm['harga_modal'],
            kategori: itm['kategori']?.toString() ?? 'Lainnya',
            warna: itm['warna']?.toString() ?? '-',
          );
        }
        return;
      } catch (_) {}
    }

    // Fallback: move 1-SKU tanpa JSON detail
    if (jumlahFlat > 0) {
      await _upsertProductLine(
        tokoId: tokoId,
        qty: jumlahFlat,
        barcode: '-',
        nama: 'Barang masuk (tanpa detail SKU)',
        hargaJual: 0,
        hargaModal: 0,
        kategori: 'Lainnya',
        warna: '-',
      );
    }
  }

  Future<void> _upsertProductLine({
    required String tokoId,
    required int qty,
    required String barcode,
    String? sku,
    required String nama,
    required dynamic hargaJual,
    required dynamic hargaModal,
    required String kategori,
    required String warna,
  }) async {
    Map<String, dynamic>? existing;
    if (barcode.isNotEmpty && barcode != '-') {
      existing = await _client
          .from('products')
          .select('id, stock')
          .eq('barcode', barcode)
          .eq('toko_id', tokoId)
          .maybeSingle();
    }
    if (existing == null && sku != null && sku.trim().isNotEmpty) {
      existing = await _client
          .from('products')
          .select('id, stock')
          .eq('sku', sku.trim())
          .eq('toko_id', tokoId)
          .maybeSingle();
    }

    if (existing != null) {
      final cur = int.tryParse(existing['stock']?.toString() ?? '0') ?? 0;
      await _client
          .from('products')
          .update({'stock': cur + qty}).eq('id', existing['id']);
      return;
    }

    final hj = int.tryParse(hargaJual?.toString() ?? '0') ?? 0;
    final hm = int.tryParse(hargaModal?.toString() ?? '') ??
        (hj > 0 ? (hj * 0.4).round() : 0);

    await _client.from('products').insert({
      'nama': nama,
      'barcode': barcode,
      if (sku != null && sku.trim().isNotEmpty) 'sku': sku.trim(),
      'stock': qty,
      'toko_id': tokoId,
      'harga_jual': hj,
      'harga_modal': hm,
      'kategori': kategori,
      'warna': warna,
    });
  }

  static String _fmt(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }
}
