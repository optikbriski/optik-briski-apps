import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../qr/obr_codes.dart';
import 'do_lifecycle_service.dart';
import 'inventory_stock_rules.dart';
import 'request_order_service.dart';

class ReceiveScanResult {
  const ReceiveScanResult({
    required this.ok,
    required this.message,
    this.resi,
    this.alreadyDone = false,
    this.verifiedByName,
    this.verifiedAt,
    this.becameTransit = false,
    this.needsPhoto = false,
    this.moveId,
  });

  final bool ok;
  final String message;
  final String? resi;
  final bool alreadyDone;
  final String? verifiedByName;
  final DateTime? verifiedAt;
  /// True jika scan mengubah PREPARING/WAITING → TRANSIT (jemput kurir).
  final bool becameTransit;
  /// Terima butuh foto bukti dulu (000029).
  final bool needsPhoto;
  final String? moveId;
}

/// Scan QR surat jalan:
/// - PREPARING / WAITING → TRANSIT (kurir jemput)
/// - TRANSIT / PENDING → SUCCESS + stok cabang (penerimaan)
class ReceiveScanService {
  ReceiveScanService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Status yang boleh di-scan jadi transit (barcode perjalanan).
  static const pickupStatuses = ['PREPARING', 'WAITING'];

  /// Status yang boleh diterima cabang.
  static const receiveStatuses = ['TRANSIT', 'PENDING'];

  /// Alias lama — status terbuka di ledger (masih di jalan / belum selesai).
  static const openStatuses = [
    'PREPARING',
    'WAITING',
    'TRANSIT',
    'PENDING',
  ];

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
    if (a == b) return true;
    const pusat = {'PUSAT', 'CABANG-PUSAT'};
    return pusat.contains(a) && pusat.contains(b);
  }

  /// Entry utama scan logistik (kurir jemput ATAU cabang terima).
  Future<ReceiveScanResult> processLogisticsQr({
    required String qrRaw,
    required String cabangKaryawan,
    required String verifiedById,
    required String verifiedByName,
    String? buktiFotoPenerima,
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

    final status = (row['status'] ?? '').toString().toUpperCase();
    final kind = (payload['kind'] ?? '').toString().trim().toUpperCase();
    // OBRPREP = klaim preparing, bukan jemput/terima.
    if (kind == 'PREP') {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message:
            'Ini QR klaim PREPARING (OBRPREP), bukan QR perjalanan. '
            'Pakai QR OBRDO setelah packing siap.',
      );
    }

    if (pickupStatuses.contains(status)) {
      return _markTransit(
        row: Map<String, dynamic>.from(row),
        resi: resi,
        kurirId: verifiedById,
        kurirNama: verifiedByName,
        cabangPemindai: cabangKaryawan,
      );
    }

    return _receiveRow(
      row: Map<String, dynamic>.from(row),
      resi: resi,
      tujuanQr: tujuanQr,
      cabangKaryawan: cabangKaryawan,
      verifiedById: verifiedById,
      verifiedByName: verifiedByName,
      buktiFotoPenerima: buktiFotoPenerima,
    );
  }

  /// Kompat: sama dengan [processLogisticsQr].
  Future<ReceiveScanResult> receiveFromQr({
    required String qrRaw,
    required String cabangKaryawan,
    required String verifiedById,
    required String verifiedByName,
    String? buktiFotoPenerima,
  }) =>
      processLogisticsQr(
        qrRaw: qrRaw,
        cabangKaryawan: cabangKaryawan,
        verifiedById: verifiedById,
        verifiedByName: verifiedByName,
        buktiFotoPenerima: buktiFotoPenerima,
      );

  Future<ReceiveScanResult> _markTransit({
    required Map<String, dynamic> row,
    required String resi,
    required String kurirId,
    required String kurirNama,
    required String cabangPemindai,
  }) async {
    final tipe = (row['tipe'] ?? '').toString().toUpperCase();
    final isRo = tipe == 'REQUEST' ||
        tipe == 'RO' ||
        resi.toUpperCase().startsWith('RO-');
    final ke = (row['ke_lokasi'] ?? '').toString().trim().toUpperCase();
    final dari =
        (row['dari_lokasi'] ?? 'PUSAT').toString().trim().toUpperCase();
    final scanner = cabangPemindai.trim().toUpperCase();

    // Cabang tujuan tidak boleh "jemput" — itu memotong stok Pusat terlalu dini.
    if (!InventoryStockRules.canMarkTransit(
      scannerToko: scanner,
      dari: dari,
      ke: ke,
    )) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message:
            'Paket masih disiapkan (belum TRANSIT). '
            'Scan jemput harus dari kurir / Pusat — bukan cabang tujuan ($ke). '
            'Cabang scan lagi setelah status TRANSIT untuk menerima.',
      );
    }

    final moveId = row['id'].toString();
    try {
      final out = await DoLifecycleService(client: _client).markTransit(
        moveId: moveId,
        kurirId: kurirId,
        kurirNama: kurirNama,
      );
      final already = out['already_transit'] == true;
      final label = isRo ? ' (RO)' : '';
      return ReceiveScanResult(
        ok: true,
        resi: resi,
        becameTransit: !already,
        verifiedByName: kurirNama,
        message: already
            ? 'Resi $resi$label sudah TRANSIT.'
            : 'Resi $resi$label sekarang TRANSIT. Kurir: $kurirNama',
      );
    } catch (e) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message: 'Gagal set TRANSIT: $e',
      );
    }
  }

  Future<ReceiveScanResult> _receiveRow({
    required Map<String, dynamic> row,
    required String resi,
    required String? tujuanQr,
    required String cabangKaryawan,
    required String verifiedById,
    required String verifiedByName,
    String? buktiFotoPenerima,
  }) async {
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

    if (pickupStatuses.contains(status)) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message:
            'Paket masih $status. Kurir harus scan barcode perjalanan dulu agar status jadi TRANSIT.',
      );
    }

    if (!receiveStatuses.contains(status)) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message: 'Status paket $status tidak bisa di-scan terima.',
      );
    }

    final moveId = row['id'].toString();
    final foto = (buktiFotoPenerima ?? '').trim();
    if (foto.isEmpty || foto == '-') {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        needsPhoto: true,
        moveId: moveId,
        message: 'Foto terima wajib sebelum stok masuk.',
      );
    }
    Map<String, dynamic> out;
    try {
      out = await DoLifecycleService(client: _client).receive(
        moveId: moveId,
        verifiedBy: verifiedById,
        verifiedByName: verifiedByName,
        buktiFotoPenerima: foto,
      );
    } catch (e) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message: '$e',
      );
    }

    if (out['already_done'] == true) {
      final atRaw = out['verified_at']?.toString();
      DateTime? at;
      if (atRaw != null && atRaw.isNotEmpty) {
        at = DateTime.tryParse(atRaw)?.toLocal();
      }
      final by = out['verified_by_name']?.toString();
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

    var roNote = '';
    try {
      await RequestOrderService(client: _client).markSuccessFromMove(
        stockMoveId: moveId,
        resi: resi,
      );
    } catch (e) {
      roNote = ' RO/QR sync: $e';
    }

    final atRaw = out['verified_at']?.toString();
    final at = atRaw != null && atRaw.isNotEmpty
        ? DateTime.tryParse(atRaw)?.toLocal()
        : DateTime.now();
    return ReceiveScanResult(
      ok: true,
      resi: resi,
      verifiedByName: verifiedByName,
      verifiedAt: at,
      message:
          'Resi $resi diterima. Stok toko diperbarui. Petugas: $verifiedByName'
          '${at != null ? ' · ${_fmt(at)}' : ''}.$roNote',
    );
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
