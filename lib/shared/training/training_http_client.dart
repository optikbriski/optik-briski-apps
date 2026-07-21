import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'training_mode.dart';
import 'training_rpc_stubs.dart';
import 'training_sandbox_store.dart';

/// Central Supabase HTTP interceptor for Training Mode.
///
/// Injected once via `Supabase.initialize(httpClient: ...)`. While training
/// is inactive → pass-through. While active:
/// - REST/Storage/RPC **mutations** → [TrainingSandboxStore] (never network)
/// - REST **reads** → merge network (if online) with sandbox overlays
/// - Auth session refresh / GET user → pass-through (keep session)
/// - Destructive auth → blocked
/// - Any mutation that would escape → **fail closed** ([StateError])
class TrainingHttpClient extends http.BaseClient {
  TrainingHttpClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Debug/test: number of mutations blocked from reaching the network.
  static int debugBlockedMutations = 0;

  /// Debug/test: when true, [_inner] must never receive mutating Supabase calls
  /// while training is active (asserted in debug).
  static bool debugAssertFailClosed = kDebugMode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!TrainingMode.instance.isActive) {
      return _inner.send(request);
    }

    final uri = request.url;
    final method = request.method.toUpperCase();
    final path = uri.path;

    // --- Auth ---
    if (path.contains('/auth/v1/')) {
      return _handleAuth(request, method, path);
    }

    // --- Edge Functions ---
    if (path.contains('/functions/v1/')) {
      return _handleFunctions(request, method, path);
    }

    // --- Storage ---
    if (path.contains('/storage/v1/')) {
      return _handleStorage(request, method, path);
    }

    // --- PostgREST ---
    if (path.contains('/rest/v1/')) {
      return _handleRest(request, method, path);
    }

    // Realtime is websocket — not via this client. Unknown Supabase HTTP:
    if (_isSupabaseHost(uri)) {
      if (_isMutatingMethod(method)) {
        return _failClosed(method, uri, 'unknown supabase endpoint');
      }
      // Safe read of unknown path — pass-through (GET/HEAD only).
      return _passThrough(request);
    }

    // Non-Supabase host while training: never forward mutations.
    if (_isMutatingMethod(method)) {
      return _failClosed(method, uri, 'non-supabase mutation');
    }
    return _passThrough(request);
  }

  /// Sole network gateway while [TrainingMode.isActive].
  ///
  /// **Fail-closed:** mutating methods never reach [_inner] unless explicitly
  /// allowlisted (auth token/session keep-alive only).
  Future<http.StreamedResponse> _passThrough(
    http.BaseRequest request, {
    bool allowAuthSessionMutation = false,
  }) async {
    final method = request.method.toUpperCase();
    if (_isMutatingMethod(method) && !allowAuthSessionMutation) {
      return _failClosed(
        method,
        request.url,
        'pass-through mutation forbidden',
      );
    }
    if (debugAssertFailClosed &&
        _isMutatingMethod(method) &&
        !allowAuthSessionMutation) {
      // Unreachable if fail-closed above works; kept as belt-and-suspenders.
      assert(false, 'TrainingHttpClient leaked mutating pass-through');
    }
    return _inner.send(request);
  }

  Future<http.StreamedResponse> _handleAuth(
    http.BaseRequest request,
    String method,
    String path,
  ) async {
    final lower = path.toLowerCase();
    // Keep session alive (token refresh / session) — only allowlisted mutations.
    final isSessionKeepAlive =
        lower.contains('/token') || lower.contains('/session');
    final passThrough = (lower.contains('/user') && method == 'GET') ||
        isSessionKeepAlive ||
        lower.endsWith('/health') ||
        method == 'GET';

    final destructive =
        (lower.contains('/user') &&
                (method == 'PUT' || method == 'PATCH' || method == 'DELETE')) ||
            (lower.contains('/logout') && method == 'POST') ||
            lower.contains('/recover') ||
            (lower.contains('/verify') && method == 'POST');

    if (destructive) {
      return _failClosed(method, request.url, 'auth mutation blocked');
    }
    if (passThrough) {
      return _passThrough(
        request,
        allowAuthSessionMutation: isSessionKeepAlive,
      );
    }
    // Other auth POSTs (e.g. reauth) — block to be safe.
    if (_isMutatingMethod(method)) {
      return _failClosed(method, request.url, 'auth mutation blocked');
    }
    return _passThrough(request);
  }

  Future<http.StreamedResponse> _handleFunctions(
    http.BaseRequest request,
    String method,
    String path,
  ) async {
    // Never hit production edge functions during training (AWS, etc.).
    if (_isMutatingMethod(method) || method == 'GET') {
      debugBlockedMutations++;
      final name = path.split('/functions/v1/').last.split('?').first;
      final body = jsonEncode(_trainingFunctionStub(name));
      return _jsonResponse(request, 200, body);
    }
    return _failClosed(method, request.url, 'functions');
  }

  /// Per-function stub shapes so callers don't retry / mis-parse mid-training.
  Map<String, dynamic> _trainingFunctionStub(String name) {
    final base = <String, dynamic>{
      'ok': true,
      'training': true,
      'function': name,
    };
    switch (name) {
      case 'send-invoice-email':
        return {
          ...base,
          'sent': false,
          'message': 'Training stub — email not sent.',
        };
      case 'aws-face-liveness':
      case 'aws-rekognition':
        return {
          ...base,
          'matched': true,
          'face_id': 'sb_face_${DateTime.now().millisecondsSinceEpoch}',
          'confidence': 99.0,
          'isLive': true,
        };
      case 'ktp-ocr':
        return {
          ...base,
          'nik': '0000000000000000',
          'nama': 'TRAINING STUB',
          'message': 'Training stub — OCR not run.',
        };
      default:
        return {
          ...base,
          'matched': true,
          'face_id': 'sb_face_${DateTime.now().millisecondsSinceEpoch}',
        };
    }
  }

  Future<http.StreamedResponse> _handleStorage(
    http.BaseRequest request,
    String method,
    String path,
  ) async {
    final store = TrainingSandboxStore.instance;

    // Upload: POST/PUT /storage/v1/object/{bucket}/{path}
    if (path.contains('/object/') &&
        !path.contains('/object/list') &&
        !path.contains('/object/sign') &&
        !path.contains('/object/public') &&
        !path.contains('/object/info') &&
        (method == 'POST' || method == 'PUT')) {
      debugBlockedMutations++;
      final parsed = _parseStorageObjectPath(path);
      if (parsed == null) {
        return _failClosed(method, request.url, 'storage upload parse');
      }
      final bytes = await _readRequestBytes(request);
      final relative = '${parsed.bucket}/${parsed.objectPath}';
      await store.writeFile(relative, bytes);
      final publicUrl =
          '$supabaseUrl/storage/v1/object/public/${parsed.bucket}/${parsed.objectPath}';
      store.registerPublicUrl(publicUrl, relative);
      final key = '${parsed.bucket}/${parsed.objectPath}';
      return _jsonResponse(
        request,
        200,
        jsonEncode({'Key': key, 'key': key, 'Id': key}),
      );
    }

    // Delete object
    if (path.contains('/object/') && method == 'DELETE') {
      debugBlockedMutations++;
      return _jsonResponse(request, 200, jsonEncode([]));
    }

    // Public / signed download via storage API (not Image.network)
    if (method == 'GET' &&
        (path.contains('/object/public/') || path.contains('/object/'))) {
      final parsed = _parseStorageObjectPath(path);
      if (parsed != null) {
        final relative = '${parsed.bucket}/${parsed.objectPath}';
        final bytes = await store.readFile(relative);
        if (bytes != null) {
          return http.StreamedResponse(
            Stream.value(bytes),
            200,
            request: request,
            headers: {
              'content-type': 'application/octet-stream',
              'content-length': '${bytes.length}',
            },
          );
        }
      }
      // Fall through to network for non-sandbox assets (read-only OK).
      return _passThrough(request);
    }

    // list / move / copy etc. — mutate-ish → sandbox success
    if (_isMutatingMethod(method)) {
      debugBlockedMutations++;
      return _jsonResponse(request, 200, jsonEncode({'training': true}));
    }

    return _passThrough(request);
  }

  Future<http.StreamedResponse> _handleRest(
    http.BaseRequest request,
    String method,
    String path,
  ) async {
    final after = path.split('/rest/v1/').last;
    if (after.startsWith('rpc/')) {
      return _handleRpc(request, method, after.substring(4));
    }

    final table = after.split('?').first.split('/').first;
    if (table.isEmpty) {
      return _failClosed(method, request.url, 'empty table');
    }

    if (method == 'GET' || method == 'HEAD') {
      return _handleRestGet(request, method, table);
    }

    if (method == 'POST' ||
        method == 'PATCH' ||
        method == 'PUT' ||
        method == 'DELETE') {
      return _handleRestMutation(request, method, table);
    }

    return _failClosed(method, request.url, 'rest unknown method');
  }

  Future<http.StreamedResponse> _handleRpc(
    http.BaseRequest request,
    String method,
    String fnAndQuery,
  ) async {
    final fn = fnAndQuery.split('?').first;
    // RPCs are almost always POST and may mutate — never hit prod.
    if (method != 'GET' && method != 'HEAD') {
      debugBlockedMutations++;
    }
    Map<String, dynamic>? params;
    if (request is http.Request && request.body.isNotEmpty) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map) {
        params = Map<String, dynamic>.from(decoded);
      }
    }
    final result = await TrainingRpcStubs.handle(fn, params);
    final prefer = request.headers['Prefer'] ?? '';
    final accept = request.headers['Accept'] ?? '';
    if (result == null) {
      if (accept.contains('application/vnd.pgrst.object+json')) {
        return _jsonResponse(request, 406, jsonEncode({
          'message': 'JSON object requested, multiple (or no) rows returned',
          'code': 'PGRST116',
        }));
      }
      return _jsonResponse(request, 204, '');
    }
    final body = jsonEncode(result);
    if (prefer.contains('return=minimal')) {
      return _jsonResponse(request, 204, '');
    }
    return _jsonResponse(request, 200, body);
  }

  Future<http.StreamedResponse> _handleRestGet(
    http.BaseRequest request,
    String method,
    String table,
  ) async {
    // Curriculum isolation: serve sandbox only — never pull live rows into
    // training (keeps "start from zero" + zero mix with production).
    final store = TrainingSandboxStore.instance;
    if (method == 'HEAD') {
      final local = await store.select(table);
      final filtered =
          _applyPostgrestFilters(local, request.url.queryParameters);
      return http.StreamedResponse(
        const Stream.empty(),
        200,
        request: request,
        headers: {
          'content-type': 'application/json',
          'content-range': '0-${filtered.isEmpty ? 0 : filtered.length - 1}/${filtered.length}',
        },
      );
    }

    final local = await store.select(table);
    final filtered =
        _applyPostgrestFilters(local, request.url.queryParameters);
    return _encodeRestGetResponse(request, filtered);
  }

  Future<http.StreamedResponse> _handleRestMutation(
    http.BaseRequest request,
    String method,
    String table,
  ) async {
    debugBlockedMutations++;
    if (debugAssertFailClosed) {
      // Fail-closed guarantee: we never call _inner for this path.
      assert(TrainingMode.instance.isActive);
    }

    final store = TrainingSandboxStore.instance;
    final prefer = request.headers['Prefer'] ?? '';
    final accept = request.headers['Accept'] ?? '';
    final wantRepresentation = prefer.contains('return=representation') ||
        accept.contains('application/vnd.pgrst.object+json');
    final wantObject = accept.contains('application/vnd.pgrst.object+json');

    final where = _equalityFilters(request.url.queryParameters);
    List<Map<String, dynamic>> affected = [];

    if (method == 'DELETE') {
      if (where.isEmpty) {
        // Refuse unbounded delete in training — succeed with empty result.
        affected = [];
      } else {
        if (wantRepresentation) {
          affected = await store.select(table, where: where);
        }
        await store.delete(table, where: where);
      }
    } else {
      final raw = await _readRequestBytes(request);
      final decoded = raw.isEmpty ? null : jsonDecode(utf8.decode(raw));

      if (method == 'POST') {
        final items = <Map<String, dynamic>>[];
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) items.add(Map<String, dynamic>.from(e));
          }
        } else if (decoded is Map) {
          items.add(Map<String, dynamic>.from(decoded));
        }
        final onConflict =
            (request.url.queryParameters['on_conflict'] ?? '').trim();
        final mergeDup = prefer.contains('resolution=merge-duplicates');
        final ignoreDup = prefer.contains('resolution=ignore-duplicates');
        for (final row in items) {
          final toko = row['toko_id']?.toString();
          if (toko != null &&
              toko.isNotEmpty &&
              toko != 'PUSAT' &&
              toko != 'CABANG-PUSAT') {
            try {
              TrainingMode.instance.assertSameToko(toko);
            } catch (_) {
              // Soft: still store but log — UI may send locked toko always.
              debugPrint('[TrainingHttpClient] toko scope warn for $table');
            }
          }
          // PostgREST upsert: POST ?on_conflict=col + Prefer resolution=...
          if (onConflict.isNotEmpty) {
            final key = onConflict.split(',').first.trim();
            final keyVal = row[key];
            if (keyVal != null) {
              final existing =
                  await store.selectOne(table, where: {key: keyVal});
              if (existing != null) {
                if (ignoreDup && !mergeDup) {
                  affected.add(existing);
                  continue;
                }
                final merged = Map<String, dynamic>.from(existing)
                  ..addAll(row)
                  ..['id'] = existing['id'];
                await store.update(table, merged, where: {key: keyVal});
                affected.add(
                  await store.selectOne(table, where: {key: keyVal}) ??
                      merged,
                );
                continue;
              }
            }
          }
          affected.add(await store.insert(table, row));
        }
      } else if (method == 'PATCH' || method == 'PUT') {
        final values = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        if (where.isEmpty) {
          // Upsert-style PUT without filters — insert.
          affected.add(await store.insert(table, values));
        } else {
          await store.update(table, values, where: where);
          affected = await store.select(table, where: where);
          if (affected.isEmpty) {
            affected.add(await store.insert(table, {...where, ...values}));
          }
        }
      }
    }

    if (!wantRepresentation || prefer.contains('return=minimal')) {
      return _jsonResponse(request, method == 'POST' ? 201 : 204, '');
    }

    if (wantObject) {
      if (affected.length == 1) {
        return _jsonResponse(request, method == 'POST' ? 201 : 200,
            jsonEncode(affected.first));
      }
      if (affected.isEmpty) {
        return _jsonResponse(
          request,
          406,
          jsonEncode({
            'message': 'JSON object requested, multiple (or no) rows returned',
            'code': 'PGRST116',
          }),
        );
      }
      // multiple → still return first for training UX
      return _jsonResponse(
          request, method == 'POST' ? 201 : 200, jsonEncode(affected.first));
    }

    return _jsonResponse(
      request,
      method == 'POST' ? 201 : 200,
      jsonEncode(affected),
    );
  }

  // --- helpers ---

  bool _isSupabaseHost(Uri uri) {
    if (supabaseUrl.isEmpty) return true;
    final base = Uri.tryParse(supabaseUrl);
    if (base == null) return true;
    return uri.host == base.host;
  }

  bool _isMutatingMethod(String method) =>
      method == 'POST' ||
      method == 'PUT' ||
      method == 'PATCH' ||
      method == 'DELETE';

  Future<http.StreamedResponse> _failClosed(
    String method,
    Uri uri,
    String reason,
  ) async {
    debugBlockedMutations++;
    final msg =
        'PRODUCTION WRITE BLOCKED during Training Mode: $method $uri ($reason)';
    debugPrint('[TrainingHttpClient] FAIL-CLOSED $msg');
    throw StateError(msg);
  }

  Future<Uint8List> _readRequestBytes(http.BaseRequest request) async {
    if (request is http.Request) {
      return request.bodyBytes;
    }
    if (request is http.MultipartRequest) {
      // Reconstruct body from finalized stream.
      final streamed = http.ByteStream(request.finalize());
      return streamed.toBytes();
    }
    return request.finalize().toBytes();
  }

  _StoragePath? _parseStorageObjectPath(String path) {
    // .../storage/v1/object/{bucket}/{path}
    // .../storage/v1/object/public/{bucket}/{path}
    final marker = '/object/';
    final i = path.indexOf(marker);
    if (i < 0) return null;
    var rest = path.substring(i + marker.length);
    if (rest.startsWith('public/')) rest = rest.substring('public/'.length);
    if (rest.startsWith('sign/')) rest = rest.substring('sign/'.length);
    if (rest.startsWith('upload/sign/')) {
      rest = rest.substring('upload/sign/'.length);
    }
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    return _StoragePath(
      bucket: Uri.decodeComponent(rest.substring(0, slash)),
      objectPath: Uri.decodeComponent(rest.substring(slash + 1)),
    );
  }

  Map<String, dynamic> _equalityFilters(Map<String, String> query) {
    final where = <String, dynamic>{};
    for (final e in query.entries) {
      if (e.key == 'select' ||
          e.key == 'order' ||
          e.key == 'limit' ||
          e.key == 'offset' ||
          e.key == 'or' ||
          e.key == 'and') {
        continue;
      }
      final v = e.value;
      if (v.startsWith('eq.')) {
        where[e.key] = _coerce(v.substring(3));
      }
    }
    return where;
  }

  List<Map<String, dynamic>> _applyPostgrestFilters(
    List<Map<String, dynamic>> rows,
    Map<String, String> query,
  ) {
    var list = List<Map<String, dynamic>>.from(rows);
    for (final e in query.entries) {
      if (e.key == 'select' ||
          e.key == 'order' ||
          e.key == 'limit' ||
          e.key == 'offset') {
        continue;
      }
      // PostgREST or=(col.op.val,col2.op.val2)
      if (e.key == 'or') {
        var raw = e.value;
        if (raw.startsWith('(') && raw.endsWith(')')) {
          raw = raw.substring(1, raw.length - 1);
        }
        final clauses = _splitCsvRespectingDots(raw);
        list = list.where((r) {
          for (final clause in clauses) {
            if (_matchFlatFilter(r, clause)) return true;
          }
          return false;
        }).toList();
        continue;
      }
      final v = e.value;
      if (v.startsWith('eq.')) {
        final expect = _coerce(v.substring(3));
        list = list.where((r) => '${r[e.key]}' == '$expect').toList();
      } else if (v.startsWith('neq.')) {
        final expect = _coerce(v.substring(4));
        list = list.where((r) => '${r[e.key]}' != '$expect').toList();
      } else if (v.startsWith('gt.')) {
        final expect = _coerce(v.substring(3));
        list = list.where((r) => _cmp(r[e.key], expect) > 0).toList();
      } else if (v.startsWith('gte.')) {
        final expect = _coerce(v.substring(4));
        list = list.where((r) => _cmp(r[e.key], expect) >= 0).toList();
      } else if (v.startsWith('lt.')) {
        final expect = _coerce(v.substring(3));
        list = list.where((r) => _cmp(r[e.key], expect) < 0).toList();
      } else if (v.startsWith('lte.')) {
        final expect = _coerce(v.substring(4));
        list = list.where((r) => _cmp(r[e.key], expect) <= 0).toList();
      } else if (v.startsWith('is.')) {
        final kind = v.substring(3);
        if (kind == 'null') {
          list = list.where((r) => r[e.key] == null).toList();
        } else if (kind == 'true') {
          list = list.where((r) => r[e.key] == true).toList();
        } else if (kind == 'false') {
          list = list.where((r) => r[e.key] == false).toList();
        }
      } else if (v.startsWith('in.')) {
        final inner = v.substring(3);
        // in.(a,b,c)
        var s = inner;
        if (s.startsWith('(') && s.endsWith(')')) {
          s = s.substring(1, s.length - 1);
        }
        final parts = s.split(',').map((e) => e.trim()).toSet();
        list = list.where((r) => parts.contains('${r[e.key]}')).toList();
      } else if (v.startsWith('ilike.') || v.startsWith('like.')) {
        final pattern = v.substring(v.indexOf('.') + 1).replaceAll('%', '.*');
        final re = RegExp('^$pattern\$', caseSensitive: v.startsWith('like.'));
        list = list.where((r) => re.hasMatch('${r[e.key] ?? ''}')).toList();
      }
    }

    final order = query['order'];
    if (order != null && order.isNotEmpty) {
      // col.asc or col.desc
      final parts = order.split('.');
      final col = parts.first;
      final asc = !(parts.length > 1 && parts[1].startsWith('desc'));
      list.sort((a, b) {
        final c = _cmp(a[col], b[col]);
        return asc ? c : -c;
      });
    }

    final offset = int.tryParse(query['offset'] ?? '');
    if (offset != null && offset > 0 && offset < list.length) {
      list = list.sublist(offset);
    } else if (offset != null && offset >= list.length) {
      list = [];
    }

    final limit = int.tryParse(query['limit'] ?? '');
    if (limit != null && list.length > limit) {
      list = list.take(limit).toList();
    }

    return list;
  }

  /// Split `a.ilike.%x%,b.eq.y` on commas (simple; values rarely contain commas).
  List<String> _splitCsvRespectingDots(String raw) {
    return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// Match a single PostgREST clause `column.op.value` against [row].
  bool _matchFlatFilter(Map<String, dynamic> row, String clause) {
    final firstDot = clause.indexOf('.');
    if (firstDot <= 0) return false;
    final col = clause.substring(0, firstDot);
    final rest = clause.substring(firstDot + 1);
    final secondDot = rest.indexOf('.');
    if (secondDot <= 0) return false;
    final op = rest.substring(0, secondDot);
    final rawVal = rest.substring(secondDot + 1);
    final cell = '${row[col] ?? ''}';
    switch (op) {
      case 'eq':
        return cell == '${_coerce(rawVal)}';
      case 'neq':
        return cell != '${_coerce(rawVal)}';
      case 'ilike':
      case 'like':
        final pattern = rawVal.replaceAll('%', '.*');
        return RegExp('^$pattern\$', caseSensitive: op == 'like')
            .hasMatch(cell);
      default:
        return false;
    }
  }

  dynamic _coerce(String raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    if (raw == 'null') return null;
    final n = num.tryParse(raw);
    if (n != null) return n;
    // strip quotes
    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  int _cmp(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  http.StreamedResponse _encodeRestGetResponse(
    http.BaseRequest request,
    List<Map<String, dynamic>> rows,
  ) {
    final accept = request.headers['Accept'] ?? '';
    if (accept.contains('application/vnd.pgrst.object+json')) {
      if (rows.length == 1) {
        return _jsonResponse(request, 200, jsonEncode(rows.first));
      }
      if (rows.isEmpty) {
        // postgrest-dart maybeSingle maps 406 + details "0 rows" → null.
        return _jsonResponse(
          request,
          406,
          jsonEncode({
            'message': 'JSON object requested, multiple (or no) rows returned',
            'code': 'PGRST116',
            'details': 'Results contain 0 rows',
          }),
        );
      }
      return _jsonResponse(
        request,
        406,
        jsonEncode({
          'message': 'JSON object requested, multiple (or no) rows returned',
          'code': 'PGRST116',
        }),
      );
    }
    final body = jsonEncode(rows);
    final total = rows.length;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'content-range': total == 0 ? '*/0' : '0-${total - 1}/$total',
        'content-length': '${utf8.encode(body).length}',
      },
    );
  }

  http.StreamedResponse _jsonResponse(
    http.BaseRequest request,
    int status,
    String body,
  ) {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      request: request,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        if (body.isNotEmpty) 'content-length': '${bytes.length}',
      },
    );
  }

  @override
  void close() {
    _inner.close();
  }
}

class _StoragePath {
  _StoragePath({required this.bucket, required this.objectPath});
  final String bucket;
  final String objectPath;
}
