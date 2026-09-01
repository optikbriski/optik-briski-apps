import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simpan draft form lokal (SharedPreferences) — offline / reload aman.
abstract final class LocalFormDraft {
  static Future<void> save(String key, Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final copy = Map<String, dynamic>.from(payload);
    copy['saved_at'] ??= DateTime.now().toIso8601String();
    await prefs.setString(key, jsonEncode(copy));
  }

  /// Hapus draft form sensitif saat logout (foto pengaduan, POS, DO).
  static Future<void> clearSessionDrafts({
    String? userId,
    String? tokoId,
  }) async {
    final uid = (userId ?? '').trim();
    final toko = (tokoId ?? '').trim();
    if (uid.isNotEmpty) {
      await clear('pengaduan_compose_draft_karyawan_$uid');
      await clear('pengaduan_compose_draft_admin_$uid');
    }
    if (toko.isNotEmpty) {
      await clear('pos_draft_transaksi_$toko');
      await clear('do_compose_draft_${toko.toUpperCase()}');
    }
  }

  static Future<Map<String, dynamic>?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  static Future<void> clear(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  /// Batas aman SharedPreferences (~1MB/key di beberapa device Android).
  static const int maxDraftPhotoBytes = 900000;

  static String? bytesToB64(Uint8List? bytes, {bool enforceLimit = true}) {
    if (bytes == null || bytes.isEmpty) return null;
    if (enforceLimit && bytes.length > maxDraftPhotoBytes) return null;
    return base64Encode(bytes);
  }

  static Uint8List? bytesFromB64(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }
}

/// Debounce autosave form (POS / DO / pengaduan).
final class DebouncedFormSave {
  DebouncedFormSave({this.delay = const Duration(milliseconds: 700)});

  final Duration delay;
  Timer? _timer;

  void schedule(Future<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(action()));
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
