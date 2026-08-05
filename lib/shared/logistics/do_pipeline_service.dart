import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../qr/obr_codes.dart';
import 'product_identity.dart';
import 'receive_scan_service.dart';
import 'request_order_service.dart';
import 'stock_mutation_service.dart';

/// Hasil klaim / aksi pipeline DO.
class DoPipelineResult {
  const DoPipelineResult({
    required this.ok,
    required this.message,
    this.moveId,
    this.resi,
    this.status,
    this.needsDriverPhoto = false,
    this.becameTransit = false,
    this.becamePreparing = false,
  });

  final bool ok;
  final String message;
  final String? moveId;
  final String? resi;
  final String? status;
  final bool needsDriverPhoto;
  final bool becameTransit;
  final bool becamePreparing;
}

/// Alur DO:
/// QUEUED (admin list + QR prep) → PREPARING (tim scan OBRPREP)
/// → foto packing + QR jalan → TRANSIT (driver scan OBRDO + foto)
/// → SUCCESS (cabang terima)
class DoPipelineService {
  DoPipelineService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const queuedStatuses = ['QUEUED'];
  static const preparingStatuses = ['PREPARING', 'WAITING'];
  static const openStatuses = [
    'QUEUED',
    'PREPARING',
    'WAITING',
    'TRANSIT',
    'PENDING',
  ];

  Future<Map<String, dynamic>?> findByResi(String resi) async {
    final row = await _client
        .from('stock_move_history')
        .select()
        .eq('product_name', resi.trim())
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  /// Tim preparing scan OBRPREP → QUEUED/WAITING menjadi PREPARING.
  Future<DoPipelineResult> claimPreparingFromQr({
    required String qrRaw,
    required String actorId,
    required String actorNama,
  }) async {
    final prep = ObrPrep.parse(qrRaw.trim());
    if (prep == null) {
      return const DoPipelineResult(
        ok: false,
        message: 'QR bukan barcode klaim preparing (OBRPREP).',
      );
    }

    final row = await findByResi(prep.resi);
    if (row == null) {
      return DoPipelineResult(
        ok: false,
        resi: prep.resi,
        message: 'Resi ${prep.resi} tidak ditemukan.',
      );
    }

    final status = (row['status'] ?? '').toString().toUpperCase();
    final moveId = row['id'].toString();

    if (status == 'PREPARING') {
      return DoPipelineResult(
        ok: true,
        moveId: moveId,
        resi: prep.resi,
        status: status,
        becamePreparing: false,
        message: 'Paket sudah PREPARING. Lanjutkan ceklis & generate QR jalan.',
      );
    }

    if (status == 'QUEUED' || status == 'WAITING') {
      await _client.from('stock_move_history').update({
        'status': 'PREPARING',
      }).eq('id', moveId);
      return DoPipelineResult(
        ok: true,
        moveId: moveId,
        resi: prep.resi,
        status: 'PREPARING',
        becamePreparing: true,
        message:
            'Klaim sukses. Status PREPARING. Siapkan barang sesuai daftar, lalu foto & generate QR jalan.',
      );
    }

    return DoPipelineResult(
      ok: false,
      moveId: moveId,
      resi: prep.resi,
      status: status,
      message: 'Status $status tidak bisa diklaim preparing.',
    );
  }

  /// Simpan foto packing + siap generate QR jalan (status tetap PREPARING).
  Future<DoPipelineResult> savePackingPhoto({
    required String moveId,
    required Uint8List photoBytes,
  }) async {
    final path = 'pengiriman/prep_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('attendance_photos').uploadBinary(
          path,
          photoBytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from('attendance_photos').getPublicUrl(path);
    await _client.from('stock_move_history').update({
      'bukti_foto_pengirim': url,
    }).eq('id', moveId);
    return DoPipelineResult(
      ok: true,
      moveId: moveId,
      message: 'Foto packing tersimpan. QR jalan siap ditampilkan ke driver.',
    );
  }

  /// Driver scan OBRDO saat PREPARING → butuh foto dulu, lalu TRANSIT.
  Future<DoPipelineResult> inspectTravelScan({
    required String qrRaw,
  }) async {
    final travel = parseObrTravel(qrRaw.trim());
    if (travel == null) {
      return const DoPipelineResult(
        ok: false,
        message: 'QR bukan barcode perjalanan (OBRDO/OBRRO).',
      );
    }
    final row = await findByResi(travel.resi);
    if (row == null) {
      return DoPipelineResult(
        ok: false,
        resi: travel.resi,
        message: 'Resi ${travel.resi} tidak ditemukan.',
      );
    }
    final status = (row['status'] ?? '').toString().toUpperCase();
    final packing =
        (row['bukti_foto_pengirim'] ?? '').toString().trim();
    final moveId = row['id'].toString();

    if (status == 'SUCCESS') {
      return DoPipelineResult(
        ok: false,
        moveId: moveId,
        resi: travel.resi,
        status: status,
        message: 'Paket sudah SUCCESS.',
      );
    }
    if (status == 'TRANSIT') {
      // Cabang receive — ditangani ReceiveScanService.
      return DoPipelineResult(
        ok: true,
        moveId: moveId,
        resi: travel.resi,
        status: status,
        message: 'Siap diterima cabang.',
      );
    }
    if (preparingStatuses.contains(status)) {
      if (packing.isEmpty || packing == '-') {
        return DoPipelineResult(
          ok: false,
          moveId: moveId,
          resi: travel.resi,
          status: status,
          message:
              'Tim preparing belum foto & generate QR jalan. Driver belum bisa berangkat.',
        );
      }
      return DoPipelineResult(
        ok: true,
        moveId: moveId,
        resi: travel.resi,
        status: status,
        needsDriverPhoto: true,
        message: 'Ambil foto barang, lalu status jadi TRANSIT.',
      );
    }
    if (status == 'QUEUED') {
      return DoPipelineResult(
        ok: false,
        moveId: moveId,
        resi: travel.resi,
        status: status,
        message:
            'Masih QUEUED. Tim preparing harus scan barcode klaim (OBRPREP) dulu.',
      );
    }
    return DoPipelineResult(
      ok: false,
      moveId: moveId,
      resi: travel.resi,
      status: status,
      message: 'Status $status tidak valid untuk scan perjalanan.',
    );
  }

  Future<DoPipelineResult> markTransitWithDriverPhoto({
    required String resi,
    required Uint8List photoBytes,
    required String kurirId,
    required String kurirNama,
  }) {
    return markTransitConsumingStock(
      resi: resi,
      kurirId: kurirId,
      kurirNama: kurirNama,
      photoBytes: photoBytes,
      requirePackingPhoto: true,
    );
  }

  /// PREPARING → TRANSIT + potong stok Real (DO).
  /// Dipakai driver scan (dengan/ tanpa foto) dan [ReceiveScanService].
  Future<DoPipelineResult> markTransitConsumingStock({
    required String resi,
    required String kurirId,
    required String kurirNama,
    Uint8List? photoBytes,
    bool requirePackingPhoto = false,
  }) async {
    final row = await findByResi(resi);
    if (row == null) {
      return DoPipelineResult(
        ok: false,
        resi: resi,
        message: 'Resi $resi tidak ditemukan.',
      );
    }
    final status = (row['status'] ?? '').toString().toUpperCase();
    if (status == 'TRANSIT') {
      return DoPipelineResult(
        ok: true,
        moveId: row['id'].toString(),
        resi: resi,
        status: status,
        becameTransit: false,
        message: 'Resi $resi sudah TRANSIT.',
      );
    }
    if (!preparingStatuses.contains(status)) {
      return DoPipelineResult(
        ok: false,
        resi: resi,
        status: status,
        message: 'Hanya PREPARING yang bisa diubah ke TRANSIT (status: $status).',
      );
    }
    final packing = (row['bukti_foto_pengirim'] ?? '').toString().trim();
    if (requirePackingPhoto && (packing.isEmpty || packing == '-')) {
      return DoPipelineResult(
        ok: false,
        resi: resi,
        message: 'Foto packing belum ada. Tim preparing harus generate QR jalan dulu.',
      );
    }

    String? kurirPhotoUrl;
    if (photoBytes != null && photoBytes.isNotEmpty) {
      final path =
          'pengiriman/kurir_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _client.storage.from('attendance_photos').uploadBinary(
            path,
            photoBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      kurirPhotoUrl =
          _client.storage.from('attendance_photos').getPublicUrl(path);
    }

    final moveId = row['id'].toString();
    final dari =
        (row['dari_lokasi'] ?? 'PUSAT').toString().trim().toUpperCase();

    // Potong Real (TRANSFER_OUT) saat masuk TRANSIT — wajib untuk DO.
    final mut = StockMutationService(client: _client);
    final consumed = await mut.consumeReservationAndShipOut(
      kind: StockReserveKind.doPreparing,
      refType: 'stock_move',
      refId: moveId,
      tokoId: dari.isEmpty ? 'PUSAT' : dari,
      alasanText: 'DO $resi → TRANSIT',
      ledgerRefType: 'stock_move',
      ledgerRefId: moveId,
    );
    final items = (consumed['items'] as List?) ?? const [];
    if (items.isEmpty) {
      // Legacy PREPARING tanpa reservation: potong Real dari keterangan.
      await _shipOutFromKeterangan(
        mut: mut,
        fromToko: dari.isEmpty ? 'PUSAT' : dari,
        keterangan: (row['keterangan'] ?? '').toString(),
        refId: moveId,
        alasan: 'DO $resi → TRANSIT (legacy)',
      );
    }

    final patch = <String, dynamic>{
      'status': 'TRANSIT',
      if (kurirPhotoUrl != null) 'bukti_foto_kurir': kurirPhotoUrl,
    };
    if ((row['kurir_karyawan_id'] ?? '').toString().trim().isEmpty &&
        kurirId.trim().isNotEmpty) {
      patch['kurir_karyawan_id'] = kurirId.trim();
      patch['kurir_nama'] = kurirNama.trim();
    }

    try {
      await _client.from('stock_move_history').update(patch).eq('id', moveId);
    } catch (_) {
      // Kolom bukti_foto_kurir mungkin belum dimigrasi — tetap TRANSIT.
      patch.remove('bukti_foto_kurir');
      await _client.from('stock_move_history').update(patch).eq('id', moveId);
    }

    return DoPipelineResult(
      ok: true,
      moveId: moveId,
      resi: resi,
      status: 'TRANSIT',
      becameTransit: true,
      message: 'Resi $resi sekarang TRANSIT. Driver: $kurirNama',
    );
  }

  Future<void> _shipOutFromKeterangan({
    required StockMutationService mut,
    required String fromToko,
    required String keterangan,
    required String refId,
    required String alasan,
  }) async {
    List items = const [];
    try {
      if (keterangan.trim().startsWith('[')) {
        items = jsonDecode(keterangan) as List;
      } else if (keterangan.contains('[{')) {
        final jsonPart =
            keterangan.substring(keterangan.indexOf('[{'));
        items = jsonDecode(jsonPart) as List;
      }
    } catch (_) {
      items = const [];
    }
    for (final raw in items) {
      if (raw is! Map) continue;
      final itm = Map<String, dynamic>.from(raw);
      final qty = int.tryParse(itm['qty']?.toString() ?? '0') ?? 0;
      if (qty <= 0) continue;
      final sku = ProductIdentity.skuOf(itm);
      if (sku == null) continue;
      await mut.shipOut(
        fromToko: fromToko,
        sku: sku,
        qty: qty,
        alasanText: alasan,
        refType: 'stock_move',
        refId: refId,
      );
    }
  }

  /// Cabang terima (wrapper ke ReceiveScanService logic untuk TRANSIT/PENDING).
  Future<ReceiveScanResult> receiveAtCabang({
    required String qrRaw,
    required String cabangKaryawan,
    required String verifiedById,
    required String verifiedByName,
  }) {
    return ReceiveScanService(client: _client).receiveFromQr(
      qrRaw: qrRaw,
      cabangKaryawan: cabangKaryawan,
      verifiedById: verifiedById,
      verifiedByName: verifiedByName,
    );
  }
}
