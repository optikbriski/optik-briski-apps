import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../qr/obr_codes.dart';
import 'inventory_stock_rules.dart';
import 'request_order_service.dart';
import 'stock_mutation_service.dart';

class ReceiveScanResult {
  const ReceiveScanResult({
    required this.ok,
    required this.message,
    this.resi,
    this.alreadyDone = false,
    this.verifiedByName,
    this.verifiedAt,
    this.becameTransit = false,
  });

  final bool ok;
  final String message;
  final String? resi;
  final bool alreadyDone;
  final String? verifiedByName;
  final DateTime? verifiedAt;
  /// True jika scan mengubah PREPARING/WAITING → TRANSIT (jemput kurir).
  final bool becameTransit;
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
    );
  }

  /// Kompat: sama dengan [processLogisticsQr].
  Future<ReceiveScanResult> receiveFromQr({
    required String qrRaw,
    required String cabangKaryawan,
    required String verifiedById,
    required String verifiedByName,
  }) =>
      processLogisticsQr(
        qrRaw: qrRaw,
        cabangKaryawan: cabangKaryawan,
        verifiedById: verifiedById,
        verifiedByName: verifiedByName,
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

    // RO: stok sudah dipotong saat ship dari Pusat — cukup flip status.
    if (isRo) {
      final moveId = row['id'].toString();
      final patch = <String, dynamic>{'status': 'TRANSIT'};
      final existingKurir = (row['kurir_karyawan_id'] ?? '').toString().trim();
      if (existingKurir.isEmpty && kurirId.trim().isNotEmpty) {
        patch['kurir_karyawan_id'] = kurirId.trim();
        patch['kurir_nama'] = kurirNama.trim();
      }
      await _client.from('stock_move_history').update(patch).eq('id', moveId);
      return ReceiveScanResult(
        ok: true,
        resi: resi,
        becameTransit: true,
        verifiedByName: kurirNama,
        message: 'Resi $resi (RO) sekarang TRANSIT. Kurir: $kurirNama',
      );
    }

    // DO: foto packing wajib sebelum jemput.
    final packing = (row['bukti_foto_pengirim'] ?? '').toString().trim();
    if (packing.isEmpty || packing == '-') {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message:
            'Foto packing belum ada. Tim gudang harus foto & tampilkan QR '
            'perjalanan dulu di halaman Disiapkan.',
      );
    }

    final moveId = row['id'].toString();
    final mut = StockMutationService(client: _client);
    var didCutStock = false;
    try {
      final consumed = await mut.consumeReservationAndShipOut(
        kind: StockReserveKind.doPreparing,
        refType: 'stock_move',
        refId: moveId,
        tokoId: dari.isEmpty ? 'PUSAT' : dari,
        alasanText: 'DO $resi → TRANSIT',
        ledgerRefType: 'stock_move',
        ledgerRefId: moveId,
        actorNama: kurirNama,
      );
      final items = (consumed['items'] as List?) ?? const [];
      if (items.isNotEmpty) {
        didCutStock = true;
      } else {
        // Reservation kosong: kemungkinan sudah di-consume sebelumnya
        // (retry setelah status gagal update). JANGAN potong Real lagi.
        // Hanya selesaikan flip status → TRANSIT.
        didCutStock = false;
      }
    } catch (e) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message: 'Gagal potong stok saat TRANSIT: $e',
      );
    }

    final patch = <String, dynamic>{'status': 'TRANSIT'};
    final existingKurir = (row['kurir_karyawan_id'] ?? '').toString().trim();
    if (existingKurir.isEmpty && kurirId.trim().isNotEmpty) {
      patch['kurir_karyawan_id'] = kurirId.trim();
      patch['kurir_nama'] = kurirNama.trim();
    }
    try {
      await _client.from('stock_move_history').update(patch).eq('id', moveId);
    } catch (e) {
      return ReceiveScanResult(
        ok: false,
        resi: resi,
        message: didCutStock
            ? 'Stok sudah dipotong tapi status gagal jadi TRANSIT: $e. '
                'Scan ulang — sistem tidak akan potong stok dua kali.'
            : 'Gagal set TRANSIT: $e',
      );
    }

    return ReceiveScanResult(
      ok: true,
      resi: resi,
      becameTransit: true,
      verifiedByName: kurirNama,
      message: didCutStock
          ? 'Resi $resi sekarang TRANSIT (stok dipotong). Kurir: $kurirNama'
          : 'Resi $resi sekarang TRANSIT (stok sudah dipotong sebelumnya). '
              'Kurir: $kurirNama',
    );
  }

  Future<ReceiveScanResult> _receiveRow({
    required Map<String, dynamic> row,
    required String resi,
    required String? tujuanQr,
    required String cabangKaryawan,
    required String verifiedById,
    required String verifiedByName,
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

    final now = DateTime.now().toUtc();
    final moveId = row['id'].toString();

    final tipe = (row['tipe'] ?? '').toString().toUpperCase();
    final isReturn = tipe == 'RETUR' || resi.toUpperCase().startsWith('RET-');
    await StockMutationService(client: _client).receiveItemsFromMoveKeterangan(
      tokoId: cabangKaryawan.trim().toUpperCase(),
      keterangan: row['keterangan']?.toString() ?? '',
      jumlahFlat: int.tryParse(row['jumlah']?.toString() ?? '0') ?? 0,
      reason: StockReason.transferIn,
      refType: 'stock_move',
      refId: moveId,
      actorNama: verifiedByName,
      isReturn: isReturn,
    );

    await _client.from('stock_move_history').update({
      'status': 'SUCCESS',
      'verified_by': verifiedById,
      'verified_by_name': verifiedByName,
      'verified_at': now.toIso8601String(),
    }).eq('id', moveId);

    var roNote = '';
    try {
      await RequestOrderService(client: _client).markSuccessFromMove(
        stockMoveId: moveId,
        resi: resi,
      );
    } catch (e) {
      roNote = ' RO/QR sync: $e';
    }

    return ReceiveScanResult(
      ok: true,
      resi: resi,
      verifiedByName: verifiedByName,
      verifiedAt: now.toLocal(),
      message:
          'Resi $resi diterima. Stok toko diperbarui. Petugas: $verifiedByName · ${_fmt(now.toLocal())}.$roNote',
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
