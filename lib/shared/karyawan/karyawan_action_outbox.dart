import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../garansi/garansi_service.dart';
import 'lab_job_service.dart';
import 'toko_antrian_service.dart';

/// Antre aksi antrian/lab saat jaringan gagal, flush saat online.
class KaryawanActionOutbox {
  KaryawanActionOutbox._();
  static final instance = KaryawanActionOutbox._();

  static const _prefsKey = 'karyawan_action_outbox_v1';
  TokoAntrianService? _antrian;
  LabJobService? _lab;
  GaransiService? _garansi;
  bool _flushing = false;

  TokoAntrianService get _antrianSvc => _antrian ??= TokoAntrianService();
  LabJobService get _labSvc => _lab ??= LabJobService();
  GaransiService get _garansiSvc => _garansi ??= GaransiService();

  Future<List<Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(items));
  }

  Future<int> pendingCount() async => (await _load()).length;

  Future<void> enqueue({
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    final items = await _load();
    final dedupe = '$kind|${jsonEncode(payload)}';
    if (items.any((e) => '${e['kind']}|${jsonEncode(e['payload'])}' == dedupe)) {
      return;
    }
    items.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'kind': kind,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _save(items);
  }

  /// Enqueue bila [error] terlihat seperti jaringan; else rethrow.
  Future<bool> enqueueIfNetworkError({
    required Object error,
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    final s = '$error'.toLowerCase();
    final net = s.contains('socket') ||
        s.contains('network') ||
        s.contains('failed host') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('connection') ||
        s.contains('offline') ||
        s.contains('clientexception');
    if (!net) return false;
    await enqueue(kind: kind, payload: payload);
    return true;
  }

  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    var ok = 0;
    try {
      final items = await _load();
      if (items.isEmpty) return 0;
      final remain = <Map<String, dynamic>>[];
      for (final item in items) {
        try {
          await _run(item);
          ok++;
        } catch (e) {
          debugPrint('outbox flush keep: $e');
          remain.add(item);
        }
      }
      await _save(remain);
    } finally {
      _flushing = false;
    }
    return ok;
  }

  Future<void> _run(Map<String, dynamic> item) async {
    final kind = (item['kind'] ?? '').toString();
    final p = Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    switch (kind) {
      case 'online_advance':
        await _antrianSvc.advanceOnlinePickup(
          orderId: '${p['orderId']}',
          currentStatus: '${p['currentStatus']}',
        );
        break;
      case 'booking_status':
        await _antrianSvc.updateBookingStatus(
          bookingId: '${p['bookingId']}',
          status: '${p['status']}',
        );
        break;
      case 'klaim_proses':
        await _antrianSvc.markKlaimDiproses(requestId: '${p['requestId']}');
        break;
      case 'lab_claim':
        await _labSvc.claim('${p['jobId']}');
        break;
      case 'lab_complete':
        final foto = (p['fotoUrl'] ?? p['foto_url'] ?? '').toString().trim();
        await _labSvc.complete(
          jobId: '${p['jobId']}',
          fotoUrl: foto.isEmpty ? null : foto,
        );
        break;
      case 'garansi_ambil':
        await _garansiSvc.konfirmasiAmbil(
          noInvoice: '${p['noInvoice']}',
          fotoHasilUrl: (p['fotoHasilUrl'] ?? '').toString().trim().isEmpty
              ? null
              : '${p['fotoHasilUrl']}',
          tokoId: (p['tokoId'] ?? '').toString().trim().isEmpty
              ? null
              : '${p['tokoId']}',
          isPusat: p['isPusat'] == true,
        );
        break;
      default:
        throw 'Unknown outbox kind: $kind';
    }
  }

  /// Coba online dulu; bila jaringan gagal → outbox.
  Future<void> runOrEnqueue({
    required String kind,
    required Map<String, dynamic> payload,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
    } catch (e) {
      final queued = await enqueueIfNetworkError(
        error: e,
        kind: kind,
        payload: payload,
      );
      if (queued) {
        throw 'Jaringan bermasalah. Aksi disimpan & akan dikirim otomatis.';
      }
      rethrow;
    }
  }
}

/// Helper: cek sesi Supabase masih punya akses net kasar.
Future<bool> karyawanLikelyOnline() async {
  try {
    await Supabase.instance.client
        .from('karyawan')
        .select('id')
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 4));
    return true;
  } catch (_) {
    return false;
  }
}
