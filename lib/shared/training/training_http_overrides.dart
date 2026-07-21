import 'dart:io';

import 'package:flutter/foundation.dart';

import 'training_mode.dart';
import 'training_sandbox_store.dart';

/// Serves sandbox upload bytes on loopback so [Image.network] /
/// [CachedNetworkImage] keep working while Training Mode is active.
///
/// Supabase `getPublicUrl` is computed client-side (real host). This override
/// rewrites matching GETs to `http://127.0.0.1:<port>/...` backed by
/// [TrainingSandboxStore] files — never production storage.
class TrainingLocalFileServer {
  TrainingLocalFileServer._();
  static final TrainingLocalFileServer instance = TrainingLocalFileServer._();

  HttpServer? _server;
  int? get port => _server?.port;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (kIsWeb || _server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    debugPrint(
      '[TrainingLocalFileServer] listening on 127.0.0.1:${_server!.port}',
    );
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
      debugPrint('[TrainingLocalFileServer] stopped');
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      // path: /{bucket}/... or /files/{bucket}/...
      var rel = request.uri.path;
      if (rel.startsWith('/')) rel = rel.substring(1);
      if (rel.isEmpty) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final bytes = await TrainingSandboxStore.instance.readFile(rel);
      if (bytes == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = _guessType(rel);
      request.response.headers.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    } catch (e) {
      debugPrint('[TrainingLocalFileServer] error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  ContentType _guessType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return ContentType('image', 'png');
    if (lower.endsWith('.webp')) return ContentType('image', 'webp');
    if (lower.endsWith('.gif')) return ContentType('image', 'gif');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return ContentType('image', 'jpeg');
    }
    return ContentType.binary;
  }

  /// Loopback URL for a sandbox relative path `bucket/key...`.
  String? loopbackUrlFor(String relativePath) {
    final p = port;
    if (p == null) return null;
    return 'http://127.0.0.1:$p/$relativePath';
  }
}

/// Rewrites production storage public GETs to the loopback sandbox server.
class TrainingHttpOverrides extends HttpOverrides {
  TrainingHttpOverrides({HttpOverrides? previous}) : _previous = previous;

  final HttpOverrides? _previous;

  static HttpOverrides? _installedPrevious;
  static bool _active = false;

  static void install() {
    if (kIsWeb || _active) return;
    _installedPrevious = HttpOverrides.current;
    HttpOverrides.global = TrainingHttpOverrides(previous: _installedPrevious);
    _active = true;
    debugPrint('[TrainingHttpOverrides] installed');
  }

  static void uninstall() {
    if (!_active) return;
    HttpOverrides.global = _installedPrevious;
    _installedPrevious = null;
    _active = false;
    debugPrint('[TrainingHttpOverrides] uninstalled');
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = _previous?.createHttpClient(context) ??
        super.createHttpClient(context);
    return _RewritingHttpClient(inner);
  }
}

class _RewritingHttpClient implements HttpClient {
  _RewritingHttpClient(this._inner);
  final HttpClient _inner;

  Uri? _rewrite(Uri url) {
    if (!TrainingMode.instance.isActive) return null;
    final server = TrainingLocalFileServer.instance;
    if (!server.isRunning) return null;

    final bytesUrl = url.toString();
    // Prefer exact registry hit → relative path → loopback.
    // resolveUrlBytes proves the file exists; parse storage public path.
    final segs = url.pathSegments;
    final idx = segs.indexOf('object');
    if (idx >= 0 &&
        idx + 2 < segs.length &&
        (segs[idx + 1] == 'public' || segs[idx + 1] == 'sign')) {
      final bucket = segs[idx + 2];
      final path = segs.sublist(idx + 3).join('/');
      final rel = '$bucket/$path';
      final loop = server.loopbackUrlFor(rel);
      if (loop != null) return Uri.parse(loop);
    }

    // training:// → loopback if registered via files layout
    if (bytesUrl.startsWith('training://memory/')) {
      final rel = bytesUrl.substring('training://memory/'.length);
      final loop = server.loopbackUrlFor(rel);
      if (loop != null) return Uri.parse(loop);
    }
    if (bytesUrl.startsWith('training://file/')) {
      final rest = bytesUrl.substring('training://file/'.length);
      final slash = rest.indexOf('/');
      if (slash > 0) {
        final rel = rest.substring(slash + 1);
        final loop = server.loopbackUrlFor(rel);
        if (loop != null) return Uri.parse(loop);
      }
    }
    return null;
  }

  Future<HttpClientRequest> _get(Uri url) async {
    final rewritten = _rewrite(url);
    // Only rewrite when sandbox actually has bytes (avoid masking 404 from prod
    // reads of non-training images).
    if (rewritten != null) {
      final rel = rewritten.path.startsWith('/')
          ? rewritten.path.substring(1)
          : rewritten.path;
      final bytes = await TrainingSandboxStore.instance.readFile(rel);
      if (bytes != null) {
        return _inner.getUrl(rewritten);
      }
    }
    return _inner.getUrl(url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _get(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (method.toUpperCase() == 'GET') {
      final rewritten = _rewrite(url);
      if (rewritten != null) {
        final rel = rewritten.path.startsWith('/')
            ? rewritten.path.substring(1)
            : rewritten.path;
        final bytes = await TrainingSandboxStore.instance.readFile(rel);
        if (bytes != null) {
          return _inner.openUrl(method, rewritten);
        }
      }
    }
    return _inner.openUrl(method, url);
  }

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set maxConnectionsPerHost(int? value) =>
      _inner.maxConnectionsPerHost = value;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set userAgent(String? value) => _inner.userAgent = value;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);
  @override
  void addProxyCredentials(String host, int port, String realm,
          HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set authenticate(
          Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;
  @override
  set authenticateProxy(
          Future<bool> Function(
                  String host, int port, String scheme, String? realm)?
              f) =>
      _inner.authenticateProxy = f;
  @override
  set badCertificateCallback(
          bool Function(X509Certificate cert, String host, int port)?
              callback) =>
      _inner.badCertificateCallback = callback;
  @override
  void close({bool force = false}) => _inner.close(force: force);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _inner.delete(host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _inner.deleteUrl(url);
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _inner.get(host, port, path);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _inner.head(host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => _inner.headUrl(url);
  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      _inner.open(method, host, port, path);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _inner.patch(host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _inner.patchUrl(url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _inner.post(host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _inner.postUrl(url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _inner.put(host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _inner.putUrl(url);
  @override
  set connectionFactory(
          Future<ConnectionTask<Socket>> Function(
                  Uri url, String? proxyHost, int? proxyPort)?
              f) =>
      _inner.connectionFactory = f;
  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
}
