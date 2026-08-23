import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'do_cart_lines.dart';
import 'product_identity.dart';
import 'stock_mutation_service.dart';
import 'stock_realtime.dart';

/// Transit / terima / retur / buat DO lewat RPC — bukan REST + stok terpisah.
class DoLifecycleService {
  DoLifecycleService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<Map<String, dynamic>> markTransit({
    required String moveId,
    String? kurirId,
    String? kurirNama,
    String? buktiFotoKurir,
  }) async {
    try {
      final res = await _db.rpc('mark_stock_move_transit', params: {
        'p_move_id': moveId,
        'p_kurir_id': (kurirId ?? '').trim().isEmpty ? null : kurirId!.trim(),
        'p_kurir_nama':
            (kurirNama ?? '').trim().isEmpty ? null : kurirNama!.trim(),
        'p_bukti_foto_kurir': (buktiFotoKurir ?? '').trim().isEmpty
            ? null
            : buktiFotoKurir!.trim(),
      });
      return _map('mark_stock_move_transit', res);
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal set TRANSIT.' : msg;
    }
  }

  Future<Map<String, dynamic>> receive({
    required String moveId,
    String? verifiedBy,
    String? verifiedByName,
    String? buktiFotoPenerima,
  }) async {
    try {
      final res = await _db.rpc('receive_stock_move', params: {
        'p_move_id': moveId,
        'p_verified_by':
            (verifiedBy ?? '').trim().isEmpty ? null : verifiedBy!.trim(),
        'p_verified_by_name': (verifiedByName ?? '').trim().isEmpty
            ? null
            : verifiedByName!.trim(),
        'p_bukti_foto_penerima': (buktiFotoPenerima ?? '').trim().isEmpty
            ? null
            : buktiFotoPenerima!.trim(),
      });
      return _map('receive_stock_move', res);
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal terima surat jalan.' : msg;
    }
  }

  Future<Map<String, dynamic>> createReturn({
    required String dari,
    required List<Map<String, dynamic>> items,
    String? kurirId,
    String? kurirNama,
  }) async {
    try {
      final res = await _db.rpc('create_return_stock_move', params: {
        'p_dari': dari.trim().toUpperCase(),
        'p_items': items,
        'p_kurir_id': (kurirId ?? '').trim().isEmpty ? null : kurirId!.trim(),
        'p_kurir_nama':
            (kurirNama ?? '').trim().isEmpty ? null : kurirNama!.trim(),
      });
      return _map('create_return_stock_move', res);
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal buat retur.' : msg;
    }
  }

  /// Buat DELIVERY PREPARING + booking Pending atomik (000039).
  Future<Map<String, dynamic>> createDelivery({
    required String ke,
    required List<Map<String, dynamic>> items,
    String? resi,
    String? buktiFotoPengirim,
    String? actor,
  }) async {
    final lines = items.map(DoCartLines.normalize).toList();
    if (lines.isEmpty) throw 'Item surat jalan wajib.';
    try {
      final res = await _db.rpc('create_delivery_stock_move', params: {
        'p_ke': ke.trim().toUpperCase(),
        'p_items': lines,
        'p_bukti_foto_pengirim': (buktiFotoPengirim ?? '').trim().isEmpty
            ? null
            : buktiFotoPengirim!.trim(),
        'p_resi': (resi ?? '').trim().isEmpty ? null : resi!.trim(),
        'p_actor': (actor ?? '').trim().isEmpty ? null : actor!.trim(),
      });
      _pingPusat();
      return _map('create_delivery_stock_move', res);
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) {
        final msg = e.message.trim();
        throw msg.isEmpty ? 'Gagal buat surat jalan.' : msg;
      }
      return _createDeliveryRest(
        ke: ke,
        items: lines,
        resi: resi,
        buktiFotoPengirim: buktiFotoPengirim,
        actor: actor,
      );
    }
  }

  Future<Map<String, dynamic>> createDraft({
    required String ke,
    required List<Map<String, dynamic>> items,
    String? actor,
  }) async {
    final lines = items.map(DoCartLines.normalize).toList();
    if (lines.isEmpty) throw 'Item draf wajib.';
    try {
      final res = await _db.rpc('create_delivery_draft', params: {
        'p_ke': ke.trim().toUpperCase(),
        'p_items': lines,
        'p_actor': (actor ?? '').trim().isEmpty ? null : actor!.trim(),
      });
      _pingPusat();
      return _map('create_delivery_draft', res);
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) {
        final msg = e.message.trim();
        throw msg.isEmpty ? 'Gagal simpan draf.' : msg;
      }
      return _createDraftRest(ke: ke, items: lines, actor: actor);
    }
  }

  Future<Map<String, dynamic>> promoteDraft({
    required String draftId,
    List<Map<String, dynamic>>? items,
    String? buktiFotoPengirim,
    String? resi,
    String? actor,
  }) async {
    final lines = items?.map(DoCartLines.normalize).toList();
    try {
      final res = await _db.rpc('promote_delivery_draft', params: {
        'p_draft_id': draftId,
        'p_items': lines,
        'p_bukti_foto_pengirim': (buktiFotoPengirim ?? '').trim().isEmpty
            ? null
            : buktiFotoPengirim!.trim(),
        'p_resi': (resi ?? '').trim().isEmpty ? null : resi!.trim(),
        'p_actor': (actor ?? '').trim().isEmpty ? null : actor!.trim(),
      });
      _pingPusat();
      return _map('promote_delivery_draft', res);
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) {
        final msg = e.message.trim();
        throw msg.isEmpty ? 'Gagal jadikan surat jalan.' : msg;
      }
      return _promoteDraftRest(
        draftId: draftId,
        items: lines ?? const [],
        buktiFotoPengirim: buktiFotoPengirim,
        resi: resi,
        actor: actor,
      );
    }
  }

  Future<Map<String, dynamic>> cancelPreparing({
    required String moveId,
  }) async {
    try {
      final res = await _db.rpc('cancel_preparing_stock_move', params: {
        'p_move_id': moveId,
      });
      _pingPusat();
      return _map('cancel_preparing_stock_move', res);
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) {
        final msg = e.message.trim();
        throw msg.isEmpty ? 'Gagal batalkan surat jalan.' : msg;
      }
      final mut = StockMutationService(client: _db);
      await mut.releaseReservation(
        kind: StockReserveKind.doPreparing,
        refType: 'stock_move',
        refId: moveId,
        tokoId: 'PUSAT',
      );
      await _db.from('stock_move_history').update({
        'status': 'BATAL',
      }).eq('id', moveId);
      return {'ok': true, 'id': moveId, 'status': 'BATAL'};
    }
  }

  Future<Map<String, dynamic>> _createDeliveryRest({
    required String ke,
    required List<Map<String, dynamic>> items,
    String? resi,
    String? buktiFotoPengirim,
    String? actor,
  }) async {
    final mut = StockMutationService(client: _db);
    final resiDO = (resi ?? '').trim().isEmpty
        ? 'DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}'
        : resi!.trim();
    String? moveId;
    try {
      final inserted = await _db
          .from('stock_move_history')
          .insert({
            'product_name': resiDO,
            'dari_lokasi': 'PUSAT',
            'ke_lokasi': ke.trim().toUpperCase(),
            'jumlah': DoCartLines.totalQty(items),
            'tipe': 'DELIVERY',
            'status': 'PREPARING',
            'keterangan': DoCartLines.encode(items),
            if ((buktiFotoPengirim ?? '').trim().isNotEmpty)
              'bukti_foto_pengirim': buktiFotoPengirim!.trim(),
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();
      moveId = inserted['id'].toString();
      for (final it in items) {
        final sku = ProductIdentity.skuOf(it);
        if (sku == null) throw 'Item tanpa SKU.';
        await mut.reserve(
          tokoId: 'PUSAT',
          sku: sku,
          qty: DoCartLines.qtyOf(it),
          kind: StockReserveKind.doPreparing,
          refType: 'stock_move',
          refId: moveId,
          meta: {
            'resi': resiDO,
            'tujuan': ke,
            if ((actor ?? '').trim().isNotEmpty) 'actor': actor!.trim(),
          },
        );
      }
      _pingPusat();
      return {
        'ok': true,
        'id': moveId,
        'resi': resiDO,
        'status': 'PREPARING',
        'jumlah': DoCartLines.totalQty(items),
      };
    } catch (e) {
      if (moveId != null) {
        try {
          await mut.releaseReservation(
            kind: StockReserveKind.doPreparing,
            refType: 'stock_move',
            refId: moveId,
            tokoId: 'PUSAT',
          );
        } catch (_) {}
        try {
          await _db.from('stock_move_history').update({
            'status': 'BATAL',
          }).eq('id', moveId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _createDraftRest({
    required String ke,
    required List<Map<String, dynamic>> items,
    String? actor,
  }) async {
    final mut = StockMutationService(client: _db);
    String? draftId;
    try {
      final draft = await _db
          .from('draft_pengiriman')
          .insert({
            'tujuan': ke.trim().toUpperCase(),
            'items': DoCartLines.encode(items),
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();
      draftId = draft['id'].toString();
      for (final it in items) {
        final sku = ProductIdentity.skuOf(it);
        if (sku == null) throw 'Item tanpa SKU.';
        await mut.reserve(
          tokoId: 'PUSAT',
          sku: sku,
          qty: DoCartLines.qtyOf(it),
          kind: StockReserveKind.doDraft,
          refType: 'draft',
          refId: draftId,
          meta: {
            'tujuan': ke,
            if ((actor ?? '').trim().isNotEmpty) 'actor': actor!.trim(),
          },
        );
      }
      _pingPusat();
      return {'ok': true, 'id': draftId, 'tujuan': ke};
    } catch (e) {
      if (draftId != null) {
        try {
          await mut.releaseReservation(
            kind: StockReserveKind.doDraft,
            refType: 'draft',
            refId: draftId,
            tokoId: 'PUSAT',
          );
        } catch (_) {}
        try {
          await _db.from('draft_pengiriman').delete().eq('id', draftId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _promoteDraftRest({
    required String draftId,
    required List<Map<String, dynamic>> items,
    String? buktiFotoPengirim,
    String? resi,
    String? actor,
  }) async {
    if (items.isEmpty) throw 'Item draf wajib.';
    final mut = StockMutationService(client: _db);
    var draftReleased = false;
    String? moveId;
    final resiDO = (resi ?? '').trim().isEmpty
        ? 'DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}'
        : resi!.trim();
    try {
      await mut.releaseReservation(
        kind: StockReserveKind.doDraft,
        refType: 'draft',
        refId: draftId,
        tokoId: 'PUSAT',
      );
      draftReleased = true;

      final draft = await _db
          .from('draft_pengiriman')
          .select('tujuan')
          .eq('id', draftId)
          .maybeSingle();
      final ke = (draft?['tujuan'] ?? '').toString().trim().toUpperCase();
      if (ke.isEmpty) throw 'Tujuan draf kosong.';

      final inserted = await _db
          .from('stock_move_history')
          .insert({
            'product_name': resiDO,
            'dari_lokasi': 'PUSAT',
            'ke_lokasi': ke,
            'jumlah': DoCartLines.totalQty(items),
            'tipe': 'DELIVERY',
            'status': 'PREPARING',
            if ((buktiFotoPengirim ?? '').trim().isNotEmpty)
              'bukti_foto_pengirim': buktiFotoPengirim!.trim(),
            'keterangan': DoCartLines.encode(items),
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();
      moveId = inserted['id'].toString();
      for (final it in items) {
        final sku = ProductIdentity.skuOf(it);
        if (sku == null) throw 'Item tanpa SKU.';
        await mut.reserve(
          tokoId: 'PUSAT',
          sku: sku,
          qty: DoCartLines.qtyOf(it),
          kind: StockReserveKind.doPreparing,
          refType: 'stock_move',
          refId: moveId,
          meta: {
            'resi': resiDO,
            'from_draft': draftId,
            if ((actor ?? '').trim().isNotEmpty) 'actor': actor!.trim(),
          },
        );
      }
      await _db.from('draft_pengiriman').delete().eq('id', draftId);
      _pingPusat();
      return {
        'ok': true,
        'id': moveId,
        'resi': resiDO,
        'status': 'PREPARING',
      };
    } catch (e) {
      if (moveId != null) {
        try {
          await mut.releaseReservation(
            kind: StockReserveKind.doPreparing,
            refType: 'stock_move',
            refId: moveId,
            tokoId: 'PUSAT',
          );
        } catch (_) {}
        try {
          await _db.from('stock_move_history').update({
            'status': 'BATAL',
          }).eq('id', moveId);
        } catch (_) {}
      }
      if (draftReleased) {
        try {
          for (final it in items) {
            final sku = ProductIdentity.skuOf(it);
            if (sku == null) continue;
            await mut.reserve(
              tokoId: 'PUSAT',
              sku: sku,
              qty: DoCartLines.qtyOf(it),
              kind: StockReserveKind.doDraft,
              refType: 'draft',
              refId: draftId,
              meta: {'restored_after_failed_promote': true},
            );
          }
        } catch (_) {}
      }
      rethrow;
    }
  }

  void _pingPusat() {
    unawaited(StockRealtime.broadcastToko(tokoId: 'PUSAT'));
  }

  static bool _missingRpc(PostgrestException e) {
    final blob = '${e.code} ${e.message} ${e.details} ${e.hint}'.toLowerCase();
    return e.code == 'PGRST202' ||
        blob.contains('pgrst202') ||
        blob.contains('could not find the function') ||
        blob.contains('does not exist');
  }

  static Map<String, dynamic> _map(String rpc, dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    throw 'Respon $rpc tidak valid.';
  }
}
