import 'dart:typed_data';

import '../config.dart';
import 'training_mode.dart';
import 'training_sandbox_store.dart';

/// Thin API for **local-only** training reads/writes (offline, no sync).
///
/// Prefer going through Supabase as usual — [TrainingHttpClient] intercepts
/// REST/Storage/RPC while [TrainingMode.isActive]. This client remains for
/// explicit sandbox helpers (pilots, offline seeds).
///
/// Contrast with **live/production**: live MUST stay online; writes go through
/// Supabase and sync cabang ↔ pusat in real time. This client never does that.
class TrainingDataClient {
  TrainingDataClient._();

  static final TrainingDataClient instance = TrainingDataClient._();

  final _store = TrainingSandboxStore.instance;

  /// Throws if training is active — use before production mutations.
  static void assertNotProductionWrite([String op = 'mutation']) {
    TrainingMode.guardProductionWrite(op);
  }

  /// Helper used by call sites that should never reach prod while training ON.
  static Future<Never> forbidProdMutation(String op) async {
    TrainingMode.guardProductionWrite(op);
    throw StateError('unreachable');
  }

  bool get isTraining => TrainingMode.instance.isActive;

  Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> row,
  ) async {
    _requireActive();
    final toko = row['toko_id']?.toString();
    if (toko != null && toko.isNotEmpty) {
      TrainingMode.instance.assertSameToko(toko);
    }
    return _store.insert(table, row);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    required Map<String, dynamic> where,
  }) {
    _requireActive();
    return _store.update(table, values, where: where);
  }

  Future<int> delete(
    String table, {
    required Map<String, dynamic> where,
  }) {
    _requireActive();
    return _store.delete(table, where: where);
  }

  Future<List<Map<String, dynamic>>> select(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) {
    _requireActive();
    return _store.select(
      table,
      where: where,
      orderBy: orderBy,
      ascending: ascending,
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> selectOne(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
    bool ascending = false,
  }) {
    _requireActive();
    return _store.selectOne(
      table,
      where: where,
      orderBy: orderBy,
      ascending: ascending,
    );
  }

  /// Store bytes and return a Supabase-shaped public URL that
  /// [TrainingHttpOverrides] rewrites to the loopback sandbox server.
  Future<String> storeFile(String relativePath, Uint8List bytes) async {
    _requireActive();
    await _store.writeFile(relativePath, bytes);
    // relativePath: "{bucket}/{objectPath}"
    final slash = relativePath.indexOf('/');
    final bucket = slash > 0 ? relativePath.substring(0, slash) : 'training';
    final objectPath =
        slash > 0 ? relativePath.substring(slash + 1) : relativePath;
    final base = supabaseUrl.isNotEmpty ? supabaseUrl : 'https://training.local';
    final publicUrl =
        '$base/storage/v1/object/public/$bucket/$objectPath';
    _store.registerPublicUrl(publicUrl, relativePath);
    return publicUrl;
  }

  void _requireActive() {
    if (!TrainingMode.instance.isActive) {
      throw StateError(
        'TrainingDataClient used while Training Mode is OFF. '
        'Use production Supabase client for live data.',
      );
    }
  }
}

/// Alias documenting the global prod-write gate pattern.
///
/// With [TrainingHttpClient] injected, Supabase mutations are intercepted
/// automatically. [ProdWriteGuard.check] remains a belt-and-suspenders assert.
class ProdWriteGuard {
  ProdWriteGuard._();

  static void check(String op) => TrainingMode.guardProductionWrite(op);

  static bool get trainingBlocksWrites => TrainingMode.instance.isActive;
}
