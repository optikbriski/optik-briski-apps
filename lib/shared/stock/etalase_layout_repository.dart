import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../invoice/invoice_settings_service.dart';
import 'etalase_layout.dart';

class _RemoteLayout {
  const _RemoteLayout({required this.units, required this.updatedAt});

  final List<EtalaseUnit> units;
  final DateTime updatedAt;
}

/// Persist denah etalase: cache lokal + Supabase `etalase_layouts` (jika tersedia).
///
/// Konflik: yang `updated_at`-nya lebih baru menang.
/// Kalau save cloud gagal, timestamp lokal tetap lebih baru → refresh tidak
/// menimpa edit lokal dengan remote lama.
class EtalaseLayoutRepository {
  EtalaseLayoutRepository({
    SupabaseClient? client,
    this.tenantId,
  }) : _client = client;

  final SupabaseClient? _client;
  final String? tenantId;

  /// Lazy — jangan paksa init Supabase saat hanya baca/tulis cache lokal.
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  String _norm(String tokoId) =>
      InvoiceSettingsService.normalizeTokoId(tokoId);

  static String _tsKey(String tokoId) =>
      '${EtalaseLayoutStore.prefKey(tokoId)}_updated_at';

  Future<List<EtalaseUnit>> load(String tokoId) async {
    final id = _norm(tokoId);
    final local = await _loadLocal(id);
    final localTs = await _loadLocalTs(id);
    final remote = await _loadRemote(id);

    if (remote == null) {
      // Belum ada row cloud / offline: pakai lokal; coba heal kalau ada isi.
      if (local.isNotEmpty) {
        final ts = localTs ?? DateTime.now().toUtc();
        if (localTs == null) {
          // Cache lama tanpa timestamp — stempel supaya sync berikutnya konsisten.
          await _saveLocal(id, local, updatedAt: ts);
        }
        await _saveRemote(id, local, updatedAt: ts);
      }
      return local;
    }

    // Cache lama tanpa ts: jangan anggap lebih baru dari remote.
    if (localTs != null && localTs.isAfter(remote.updatedAt)) {
      // Edit lokal lebih baru (biasanya sync cloud sempat gagal) — jangan ditimpa.
      await _saveRemote(id, local, updatedAt: localTs);
      return local;
    }

    await _saveLocal(id, remote.units, updatedAt: remote.updatedAt);
    return remote.units;
  }

  /// Return `false` jika tulis cloud gagal (lokal tetap tersimpan).
  Future<bool> save(String tokoId, List<EtalaseUnit> units) async {
    final id = _norm(tokoId);
    final now = DateTime.now().toUtc();
    await _saveLocal(id, units, updatedAt: now);
    return _saveRemote(id, units, updatedAt: now);
  }

  Future<List<EtalaseUnit>> _loadLocal(String tokoId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(EtalaseLayoutStore.prefKey(tokoId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          EtalaseUnit.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<DateTime?> _loadLocalTs(String tokoId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tsKey(tokoId));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> _saveLocal(
    String tokoId,
    List<EtalaseUnit> units, {
    required DateTime updatedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      EtalaseLayoutStore.prefKey(tokoId),
      jsonEncode([for (final u in units) u.toJson()]),
    );
    await prefs.setString(_tsKey(tokoId), updatedAt.toUtc().toIso8601String());
  }

  Future<_RemoteLayout?> _loadRemote(String tokoId) async {
    final tid = (tenantId ?? '').trim();
    if (tid.isEmpty) return null;
    try {
      final row = await _db
          .from('etalase_layouts')
          .select('layout, updated_at')
          .eq('toko_id', tokoId)
          .eq('tenant_id', tid)
          .maybeSingle();
      if (row == null) return null;
      final layout = row['layout'];
      if (layout is! List) return null;
      final ts = DateTime.tryParse('${row['updated_at'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return _RemoteLayout(
        updatedAt: ts,
        units: [
          for (final e in layout)
            EtalaseUnit.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
    } catch (_) {
      // Tabel belum di-migrate / offline → pakai lokal.
      return null;
    }
  }

  Future<bool> _saveRemote(
    String tokoId,
    List<EtalaseUnit> units, {
    required DateTime updatedAt,
  }) async {
    final tid = (tenantId ?? '').trim();
    if (tid.isEmpty) return true;
    try {
      await _db.from('etalase_layouts').upsert(
        {
          'tenant_id': tid,
          'toko_id': tokoId,
          'layout': [for (final u in units) u.toJson()],
          'updated_at': updatedAt.toUtc().toIso8601String(),
        },
        onConflict: 'tenant_id,toko_id',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
