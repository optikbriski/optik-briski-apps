import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Fully local, offline-capable table + file store for Training Mode.
///
/// Not a second networked DB. Live/production remains online-only with
/// cabang↔pusat sync; this store never syncs. Data lives under temp dir
/// `training_<sessionId>/` plus in-memory maps. [wipe] deletes everything
/// on Training Mode exit (and orphan recovery on next launch).
class TrainingSandboxStore {
  TrainingSandboxStore._();

  static final TrainingSandboxStore instance = TrainingSandboxStore._();

  String? _sessionId;
  Directory? _root;
  final Map<String, List<Map<String, dynamic>>> _tables = {};
  final Set<String> _mutatedTables = {};
  final Set<String> _deletedIds = {}; // "$table::$id"
  final Map<String, String> _publicUrlToRelative = {};
  final Map<String, Uint8List> _memoryFiles = {};

  String? get sessionId => _sessionId;
  Directory? get rootDir => _root;
  /// Ready when a session is open (disk root optional — memory fallback OK).
  bool get isReady => _sessionId != null;
  Set<String> get mutatedTables => Set.unmodifiable(_mutatedTables);

  Future<void> init(String sessionId) async {
    if (_sessionId != null && _sessionId != sessionId) {
      await wipe();
    }
    _sessionId = sessionId;
    _tables.clear();
    _mutatedTables.clear();
    _deletedIds.clear();
    _publicUrlToRelative.clear();
    _memoryFiles.clear();

    if (kIsWeb) {
      _root = null;
      debugPrint(
        '[TrainingSandbox] web: in-memory only (no temp dir)',
      );
      return;
    }

    try {
      final tmp = await getTemporaryDirectory();
      _root = Directory('${tmp.path}/training_$sessionId');
      if (!await _root!.exists()) {
        await _root!.create(recursive: true);
      }
      await _loadTablesFromDisk();
      debugPrint('[TrainingSandbox] init ${_root!.path}');
    } catch (e) {
      // Unit tests / missing plugin → memory-only sandbox.
      _root = null;
      debugPrint('[TrainingSandbox] temp dir unavailable ($e) — memory only');
    }
  }

  bool tableWasMutated(String table) => _mutatedTables.contains(table);

  bool wasDeleted(String table, dynamic id) =>
      _deletedIds.contains('$table::$id');

  /// Merge network rows with local inserts/updates/deletes for [table].
  List<Map<String, dynamic>> mergeWithNetwork(
    String table,
    List<Map<String, dynamic>> networkRows,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final r in networkRows) {
      final id = '${r['id'] ?? ''}';
      if (id.isEmpty) continue;
      if (wasDeleted(table, id)) continue;
      byId[id] = Map<String, dynamic>.from(r);
    }
    for (final r in _tables[table] ?? const []) {
      final id = '${r['id'] ?? ''}';
      if (id.isEmpty) continue;
      if (wasDeleted(table, id)) continue;
      byId[id] = Map<String, dynamic>.from(r);
    }
    return byId.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Seed / replace cached rows from a read-through (does not mark mutated).
  Future<void> seedFromReadThrough(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    _ensureReady();
    final list = _tables.putIfAbsent(table, () => <Map<String, dynamic>>[]);
    for (final row in rows) {
      final id = '${row['id'] ?? ''}';
      if (id.isEmpty) {
        list.add(Map<String, dynamic>.from(row));
        continue;
      }
      if (wasDeleted(table, id)) continue;
      final idx = list.indexWhere((r) => '${r['id']}' == id);
      final local = idx >= 0 ? list[idx] : null;
      // Prefer already-mutated local row over network seed.
      if (local != null && tableWasMutated(table)) {
        continue;
      }
      final copy = Map<String, dynamic>.from(row);
      if (idx >= 0) {
        list[idx] = copy;
      } else {
        list.add(copy);
      }
    }
    await _persistTable(table);
  }

  /// Insert a row into a sandboxed table. Returns the row (with generated id).
  Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> row,
  ) async {
    _ensureReady();
    final copy = Map<String, dynamic>.from(row);
    copy.putIfAbsent(
      'id',
      () => 'sb_${table}_${DateTime.now().microsecondsSinceEpoch}',
    );
    copy.putIfAbsent('created_at', () => DateTime.now().toIso8601String());
    final list = _tables.putIfAbsent(table, () => <Map<String, dynamic>>[]);
    final id = '${copy['id']}';
    final idx = list.indexWhere((r) => '${r['id']}' == id);
    if (idx >= 0) {
      list[idx] = copy;
    } else {
      list.add(copy);
    }
    _deletedIds.remove('$table::$id');
    _mutatedTables.add(table);
    await _persistTable(table);
    return copy;
  }

  /// Update rows matching [where] (simple equality on keys).
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    required Map<String, dynamic> where,
  }) async {
    _ensureReady();
    final list = _tables.putIfAbsent(table, () => <Map<String, dynamic>>[]);
    var n = 0;
    for (var i = 0; i < list.length; i++) {
      if (_matches(list[i], where)) {
        list[i] = {...list[i], ...values};
        n++;
      }
    }
    // If no local row matched, materialize an overlay row from where+values.
    if (n == 0 && where.containsKey('id')) {
      list.add({...where, ...values});
      n = 1;
    }
    if (n > 0) {
      _mutatedTables.add(table);
      await _persistTable(table);
    }
    return n;
  }

  /// Delete rows matching [where]. Returns count deleted.
  Future<int> delete(
    String table, {
    required Map<String, dynamic> where,
  }) async {
    _ensureReady();
    final list = _tables[table];
    var n = 0;
    if (list != null) {
      final before = list.length;
      list.removeWhere((r) {
        final hit = _matches(r, where);
        if (hit) {
          final id = r['id'];
          if (id != null) _deletedIds.add('$table::$id');
        }
        return hit;
      });
      n = before - list.length;
    }
    if (where.containsKey('id')) {
      _deletedIds.add('$table::${where['id']}');
      if (n == 0) n = 1; // network row deleted via overlay
    }
    if (n > 0) {
      _mutatedTables.add(table);
      await _persistTable(table);
    }
    return n;
  }

  /// Select all rows, optionally filtered by equality [where].
  Future<List<Map<String, dynamic>>> select(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    _ensureReady();
    var list = List<Map<String, dynamic>>.from(_tables[table] ?? const []);
    list = list.where((r) {
      final id = r['id'];
      if (id != null && wasDeleted(table, id)) return false;
      return true;
    }).toList();
    if (where != null && where.isNotEmpty) {
      list = list.where((r) => _matches(r, where)).toList();
    }
    if (orderBy != null) {
      list.sort((a, b) {
        final av = a[orderBy];
        final bv = b[orderBy];
        final cmp = Comparable.compare(
          av is Comparable ? av : '$av',
          bv is Comparable ? bv : '$bv',
        );
        return ascending ? cmp : -cmp;
      });
    }
    if (limit != null && list.length > limit) {
      list = list.take(limit).toList();
    }
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> selectOne(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
    bool ascending = false,
  }) async {
    final rows = await select(
      table,
      where: where,
      orderBy: orderBy,
      ascending: ascending,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Write bytes under the session temp dir. Returns a `training://` URI
  /// (prefer registering a public URL via [registerPublicUrl] for Image.network).
  Future<String> writeFile(String relativePath, Uint8List bytes) async {
    _ensureReady();
    if (kIsWeb || _root == null) {
      _memoryFiles[relativePath] = bytes;
      await insert('_files_meta', {
        'path': relativePath,
        'size': bytes.length,
        'b64': base64Encode(bytes),
      });
      return 'training://memory/$relativePath';
    }
    final file = File('${_root!.path}/files/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return 'training://file/$_sessionId/$relativePath';
  }

  /// Map a Supabase-shaped public URL to a sandbox relative file path.
  void registerPublicUrl(String publicUrl, String relativePath) {
    _publicUrlToRelative[publicUrl] = relativePath;
    // Also register without query/fragment variants.
    final uri = Uri.tryParse(publicUrl);
    if (uri != null) {
      _publicUrlToRelative[uri.replace(query: '', fragment: '').toString()] =
          relativePath;
    }
  }

  /// Resolve local file bytes for a public / training URL (Image.network bridge).
  Future<Uint8List?> resolveUrlBytes(String url) async {
    final rel = _publicUrlToRelative[url];
    if (rel != null) return readFile(rel);

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // /storage/v1/object/public/{bucket}/{path}
    final segs = uri.pathSegments;
    final idx = segs.indexOf('object');
    if (idx >= 0 &&
        idx + 2 < segs.length &&
        (segs[idx + 1] == 'public' || segs[idx + 1] == 'sign')) {
      final bucket = segs[idx + 2];
      final path = segs.sublist(idx + 3).join('/');
      final rel = '$bucket/$path';
      final bytes = await readFile(rel);
      if (bytes != null) return bytes;
      // Also try files/ prefix layout
      return readFile('files/$rel');
    }

    if (url.startsWith('training://memory/')) {
      final rel = url.substring('training://memory/'.length);
      return readFile(rel);
    }
    if (url.startsWith('training://file/')) {
      final rest = url.substring('training://file/'.length);
      final slash = rest.indexOf('/');
      if (slash > 0) {
        return readFile(rest.substring(slash + 1));
      }
    }
    return null;
  }

  Future<Uint8List?> readFile(String relativePath) async {
    _ensureReady();
    if (_memoryFiles.containsKey(relativePath)) {
      return _memoryFiles[relativePath];
    }
    if (kIsWeb || _root == null) {
      final rows = await select('_files_meta', where: {'path': relativePath});
      if (rows.isEmpty) return null;
      final b64 = rows.last['b64']?.toString();
      if (b64 == null) return null;
      return base64Decode(b64);
    }
    final candidates = [
      File('${_root!.path}/files/$relativePath'),
      File('${_root!.path}/$relativePath'),
    ];
    for (final file in candidates) {
      if (await file.exists()) return file.readAsBytes();
    }
    return null;
  }

  /// Absolute filesystem path if the relative file exists on disk.
  Future<String?> absolutePathFor(String relativePath) async {
    if (kIsWeb || _root == null) return null;
    final file = File('${_root!.path}/files/$relativePath');
    if (await file.exists()) return file.path;
    final alt = File('${_root!.path}/$relativePath');
    if (await alt.exists()) return alt.path;
    return null;
  }

  /// Wipe current session tables + directory.
  Future<void> wipe() async {
    final sid = _sessionId;
    _tables.clear();
    _mutatedTables.clear();
    _deletedIds.clear();
    _publicUrlToRelative.clear();
    _memoryFiles.clear();
    if (!kIsWeb && _root != null) {
      try {
        if (await _root!.exists()) {
          await _root!.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('[TrainingSandbox] wipe dir error: $e');
      }
    }
    if (sid != null) {
      await wipeSessionDir(sid);
    }
    _sessionId = null;
    _root = null;
    debugPrint('[TrainingSandbox] wiped session=$sid');
  }

  /// Delete a specific `training_<sessionId>` directory.
  static Future<void> wipeSessionDir(String sessionId) async {
    if (kIsWeb) return;
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/training_$sessionId');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('[TrainingSandbox] deleted ${dir.path}');
      }
    } catch (e) {
      debugPrint('[TrainingSandbox] wipeSessionDir($sessionId): $e');
    }
  }

  /// Delete every `training_*` folder under the system temp directory.
  static Future<void> wipeAllTrainingDirs() async {
    if (kIsWeb) return;
    try {
      final tmp = await getTemporaryDirectory();
      final root = Directory(tmp.path);
      if (!await root.exists()) return;
      await for (final entity in root.list()) {
        if (entity is Directory) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('training_')) {
            try {
              await entity.delete(recursive: true);
              debugPrint('[TrainingSandbox] orphan wiped ${entity.path}');
            } catch (e) {
              debugPrint('[TrainingSandbox] orphan wipe fail: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TrainingSandbox] wipeAllTrainingDirs: $e');
    }
  }

  void _ensureReady() {
    if (_sessionId == null) {
      throw StateError(
        'TrainingSandboxStore not initialized — call TrainingMode.enter first.',
      );
    }
  }

  bool _matches(Map<String, dynamic> row, Map<String, dynamic> where) {
    for (final e in where.entries) {
      if ('${row[e.key]}' != '${e.value}') return false;
    }
    return true;
  }

  Future<void> _persistTable(String table) async {
    if (kIsWeb || _root == null) return;
    try {
      final file = File('${_root!.path}/tables/$table.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_tables[table] ?? []), flush: true);
    } catch (e) {
      debugPrint('[TrainingSandbox] persist $table: $e');
    }
  }

  Future<void> _loadTablesFromDisk() async {
    if (kIsWeb || _root == null) return;
    final tablesDir = Directory('${_root!.path}/tables');
    if (!await tablesDir.exists()) return;
    await for (final entity in tablesDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last.replaceAll('.json', '');
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is List) {
          _tables[name] = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        debugPrint('[TrainingSandbox] load $name: $e');
      }
    }
  }
}
