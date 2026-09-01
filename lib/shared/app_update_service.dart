import 'dart:io';

import 'package:dio/dio.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'brand/brand_slug_rules.dart';
import 'config.dart';
import 'training/training_mode.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.localVersion,
    required this.serverVersion,
    required this.downloadUrl,
    required this.hasUpdate,
    required this.forceUpdate,
    this.notes,
    this.urlReachable = true,
    this.remoteSizeBytes,
  });

  final String localVersion;
  final String serverVersion;
  final String downloadUrl;
  final bool hasUpdate;
  final bool forceUpdate;
  final String? notes;
  final bool urlReachable;
  final int? remoteSizeBytes;
}

class InstallOutcome {
  const InstallOutcome({
    required this.updated,
    required this.localVersion,
    this.expectedVersion,
  });

  final bool updated;
  final String localVersion;
  final String? expectedVersion;
}

class StorageCheck {
  const StorageCheck({
    required this.ok,
    required this.freeBytes,
    required this.requiredBytes,
  });

  final bool ok;
  final int freeBytes;
  final int requiredBytes;

  String get freeLabel => AppUpdateService.formatBytes(freeBytes);
  String get requiredLabel => AppUpdateService.formatBytes(requiredBytes);
}

enum BackgroundDownloadStatus {
  /// Tidak ada update / URL tidak siap.
  skipped,

  /// Sedang mengunduh (atau sudah jalan).
  downloading,

  /// APK sudah siap di device, tinggal konfirmasi install.
  readyToInstall,

  /// Storage penuh — minta user kosongkan.
  insufficientStorage,

  /// Gagal unduh (app lama aman).
  failed,
}

class BackgroundDownloadResult {
  const BackgroundDownloadResult({
    required this.status,
    this.info,
    this.storage,
    this.apkPath,
    this.message,
  });

  final BackgroundDownloadStatus status;
  final AppUpdateInfo? info;
  final StorageCheck? storage;
  final String? apkPath;
  final String? message;
}

/// Update APK in-app (Karyawan / Admin / Member): unduh aman, pasang tetap konfirmasi.
class AppUpdateFlavor {
  static const karyawan = 'karyawan';
  static const admin = 'admin';
  static const member = 'member';

  static String normalize(String raw) {
    final f = raw.trim().toLowerCase();
    if (f == admin || f == member || f == karyawan) return f;
    return fromConfig();
  }

  /// Flavor APK yang sedang jalan — jangan default karyawan di Admin/Member.
  static String fromConfig() {
    switch (currentFlavor) {
      case AppFlavor.admin:
        return admin;
      case AppFlavor.member:
        return member;
      case AppFlavor.karyawan:
      case AppFlavor.store:
        return karyawan;
    }
  }
}

/// Update APK: auto-download aman, install tetap konfirmasi user.
class AppUpdateService {
  AppUpdateService({SupabaseClient? client, Dio? dio})
      : _client = client ?? Supabase.instance.client,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 10),
              followRedirects: false,
              validateStatus: (s) => s != null && s < 500,
            ));

  final SupabaseClient _client;
  final Dio _dio;
  final _disk = DiskSpacePlus();

  /// Prefs lama Karyawan (kompatibel). Flavor lain pakai suffix `_<flavor>`.
  static const prefAutoUpdate = 'auto_update_karyawan';
  static const prefPendingVersion = 'update_pending_version';
  static const prefFailCount = 'update_fail_count';
  static const prefSkipForceUntil = 'update_skip_force_until_ms';
  static const prefReadyPath = 'update_ready_apk_path';
  static const prefReadyVersion = 'update_ready_apk_version';
  static const minApkBytes = 512 * 1024;
  static const storageBufferBytes = 40 * 1024 * 1024; // +40 MB buffer

  static final _downloadBusy = <String, bool>{};

  static String _prefKey(String base, String appFlavor) {
    final f = AppUpdateFlavor.normalize(appFlavor);
    if (f == AppUpdateFlavor.karyawan) return base;
    return '${base}_$f';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final digits = i == 0 ? 0 : 1;
    return '${v.toStringAsFixed(digits)} ${units[i]}';
  }

  static int compareSemver(String server, String local) {
    List<int> core(String v) {
      final head = v.split('+').first.split('-').first.trim();
      if (head.isEmpty) return [0];
      return head
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    int build(String v) {
      final plus = v.split('+');
      if (plus.length < 2) return 0;
      return int.tryParse(
            plus[1].split('-').first.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0;
    }

    final a = core(server);
    final b = core(local);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return build(server).compareTo(build(local));
  }

  static bool isHttpOk(int? code) =>
      code != null && ((code >= 200 && code < 300) || code == 206);

  static bool isSafeDownloadUrl(String url) {
    return isAllowedReleaseUrl(
      url,
      flavor: AppUpdateFlavor.fromConfig(),
      channel: BrandSlugRules.releaseChannel(),
    );
  }

  /// URL APK hanya host project + bucket app-releases + nama {slug}-{flavor}-{semver}.apk.
  static bool isAllowedReleaseUrl(
    String url, {
    required String flavor,
    required String channel,
    String? supabaseHost,
    String? expectedVersion,
  }) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return false;
    }
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) return false;
    if (uri.hasPort && uri.port != 443) return false;
    final expectedHost = (supabaseHost ?? Uri.tryParse(supabaseUrl)?.host ?? '')
        .trim()
        .toLowerCase();
    if (expectedHost.isEmpty || uri.host.toLowerCase() != expectedHost) {
      return false;
    }
    if (!uri.host.toLowerCase().endsWith('.supabase.co')) return false;
    final segs = uri.pathSegments;
    if (segs.length != 6) return false;
    if (segs[0] != 'storage' ||
        segs[1] != 'v1' ||
        segs[2] != 'object' ||
        segs[3] != 'public' ||
        segs[4] != 'app-releases') {
      return false;
    }
    final parsed = BrandSlugRules.parseReleaseFilename(segs[5]);
    if (parsed == null) return false;
    final f = AppUpdateFlavor.normalize(flavor);
    if (parsed.flavor != f) return false;
    var ch = channel.trim().toLowerCase();
    if (ch == 'optik') ch = 'optik-briski';
    if (parsed.slug != ch) return false;
    if (expectedVersion != null) {
      final core = expectedVersion.split('+').first.split('-').first.trim();
      if (core.isEmpty || parsed.versi != core) return false;
    }
    return true;
  }

  Future<bool> isAutoUpdateEnabled({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    // Default ON: auto-unduh di background; install tetap konfirmasi.
    return prefs.getBool(_prefKey(prefAutoUpdate, appFlavor)) ?? true;
  }

  Future<void> setAutoUpdateEnabled(
    bool value, {
    String appFlavor = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(prefAutoUpdate, appFlavor), value);
  }

  Future<bool> shouldEnforceForceUpdate({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_prefKey(prefSkipForceUntil, appFlavor)) ?? 0;
    return DateTime.now().millisecondsSinceEpoch >= until;
  }

  Future<void> registerDownloadFailure({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final keyFail = _prefKey(prefFailCount, appFlavor);
    final keySkip = _prefKey(prefSkipForceUntil, appFlavor);
    final n = (prefs.getInt(keyFail) ?? 0) + 1;
    await prefs.setInt(keyFail, n);
    if (n >= 3) {
      final until =
          DateTime.now().add(const Duration(hours: 6)).millisecondsSinceEpoch;
      await prefs.setInt(keySkip, until);
      await prefs.setInt(keyFail, 0);
    }
  }

  Future<void> clearFailureState({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(prefFailCount, appFlavor));
    await prefs.remove(_prefKey(prefSkipForceUntil, appFlavor));
  }

  Future<void> markInstallPending(
    String expectedVersion, {
    String appFlavor = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefKey(prefPendingVersion, appFlavor), expectedVersion);
  }

  Future<void> clearInstallPending({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(prefPendingVersion, appFlavor));
  }

  Future<InstallOutcome> checkPendingInstallResult({
    String appFlavor = '',
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final local = packageInfo.version;
    final prefs = await SharedPreferences.getInstance();
    final expected = prefs.getString(_prefKey(prefPendingVersion, appFlavor));

    if (expected == null || expected.isEmpty) {
      return InstallOutcome(updated: false, localVersion: local);
    }

    final updated = compareSemver(local, expected) >= 0;
    if (updated) {
      await clearInstallPending(appFlavor: appFlavor);
      await clearFailureState(appFlavor: appFlavor);
      await clearReadyApk(appFlavor: appFlavor);
    }
    return InstallOutcome(
      updated: updated,
      localVersion: local,
      expectedVersion: expected,
    );
  }

  Future<int?> probeRemoteSizeBytes(String url) async {
    try {
      final head = await _dio.head(url);
      final len = head.headers.value('content-length');
      if (len != null) {
        final n = int.tryParse(len);
        if (n != null && n > 0) return n;
      }
    } catch (_) {}
    return null;
  }

  Future<int> freeDiskBytes() async {
    if (kIsWeb) return 0;
    try {
      final dir = await getTemporaryDirectory();
      final mb = await _disk.getFreeDiskSpaceForPath(dir.path) ??
          await _disk.getFreeDiskSpace ??
          0;
      return (mb * 1024 * 1024).round();
    } catch (_) {
      return 0;
    }
  }

  Future<StorageCheck> checkStorageForUpdate({int? remoteSizeBytes}) async {
    final free = await freeDiskBytes();
    final remote = remoteSizeBytes ?? (25 * 1024 * 1024); // fallback ~25MB
    final required = remote + storageBufferBytes;
    return StorageCheck(
      ok: free <= 0 ? true : free >= required, // jika tak terbaca, coba unduh
      freeBytes: free,
      requiredBytes: required,
    );
  }

  Future<bool> preflightUrl(
    String url, {
    required String flavor,
    required String channel,
    String? expectedVersion,
  }) async {
    if (!isAllowedReleaseUrl(
      url,
      flavor: flavor,
      channel: channel,
      expectedVersion: expectedVersion,
    )) {
      return false;
    }
    try {
      final head = await _dio.head(url);
      if (isHttpOk(head.statusCode)) return true;
    } catch (_) {}
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-3'},
        ),
      );
      if (!isHttpOk(res.statusCode)) return false;
      final bytes = res.data;
      if (bytes == null || bytes.length < 4) return false;
      return bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04;
    } catch (_) {
      return false;
    }
  }

  Future<AppUpdateInfo> checkForUpdate({String appFlavor = ''}) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final local = packageInfo.version;
    final flavor = AppUpdateFlavor.normalize(appFlavor);

    Map<String, dynamic>? data;
    final channel = BrandSlugRules.releaseChannel();
    var rpcFailed = false;
    try {
      final raw = await _client.rpc(
        'lookup_app_release',
        params: {'p_flavor': flavor, 'p_channel': channel},
      );
      if (raw is Map && raw['ok'] == true) {
        data = Map<String, dynamic>.from(raw);
      }
      // ok:false = server menolak (none/url/host). Jangan baca tabel mentah.
    } catch (_) {
      rpcFailed = true;
    }
    if (data == null && rpcFailed) {
      try {
        data = await _client
            .from('versi_app')
            .select()
            .eq('app_flavor', flavor)
            .eq('tenant_slug', channel)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {
        data = null;
      }
    }

    final server = (data?['versi_terbaru'] ?? local).toString().trim();
    final url = (data?['url_download'] ?? '').toString().trim();
    final forceFlag = data?['force_update'] == true;
    final notes = data?['catatan_rilis']?.toString();
    final urlOk = isAllowedReleaseUrl(
      url,
      flavor: flavor,
      channel: channel,
      expectedVersion: server,
    );
    final newer = compareSemver(server, local) > 0 && urlOk;

    var reachable = true;
    int? remoteSize;
    if (newer) {
      reachable = await preflightUrl(
        url,
        flavor: flavor,
        channel: channel,
        expectedVersion: server,
      );
      if (reachable) remoteSize = await probeRemoteSizeBytes(url);
    }

    final enforceForce = await shouldEnforceForceUpdate(appFlavor: flavor);
    final force = newer && forceFlag && reachable && enforceForce;

    return AppUpdateInfo(
      localVersion: local,
      serverVersion: server,
      downloadUrl: url,
      hasUpdate: newer,
      forceUpdate: force,
      notes: notes,
      urlReachable: reachable,
      remoteSizeBytes: remoteSize,
    );
  }

  Future<String?> readyApkPath({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefKey(prefReadyPath, appFlavor));
    final ver = prefs.getString(_prefKey(prefReadyVersion, appFlavor));
    if (path == null || ver == null) return null;
    final f = File(path);
    if (!await _isValidApkFile(f)) {
      await clearReadyApk(appFlavor: appFlavor);
      return null;
    }
    return path;
  }

  Future<String?> readyApkVersion({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey(prefReadyVersion, appFlavor));
  }

  Future<void> _markReadyApk(
    String path,
    String version, {
    String appFlavor = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(prefReadyPath, appFlavor), path);
    await prefs.setString(_prefKey(prefReadyVersion, appFlavor), version);
  }

  Future<void> clearReadyApk({String appFlavor = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefKey(prefReadyPath, appFlavor));
    await prefs.remove(_prefKey(prefReadyPath, appFlavor));
    await prefs.remove(_prefKey(prefReadyVersion, appFlavor));
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<bool> _isValidApkFile(File file) async {
    if (!await file.exists()) return false;
    final len = await file.length();
    if (len < minApkBytes) return false;
    final raf = await file.open();
    try {
      final header = await raf.read(4);
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          header[2] == 0x03 &&
          header[3] == 0x04;
    } finally {
      await raf.close();
    }
  }

  String _apkPathFor(String version, {String appFlavor = ''}) {
    final safe = version.replaceAll(RegExp(r'[^0-9A-Za-z._+-]'), '_');
    final flavor = AppUpdateFlavor.normalize(appFlavor);
    final channel = BrandSlugRules.releaseChannel();
    return '${channel}_${flavor}_$safe.apk';
  }

  Future<Directory> _updatesDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/apk_updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _purgeStaleApks({
    required String appFlavor,
    required String keepPath,
  }) async {
    try {
      final dir = await _updatesDir();
      final flavor = AppUpdateFlavor.normalize(appFlavor);
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(RegExp(r'[/\\]')).last;
        if (!name.contains('_${flavor}_')) continue;
        if (entity.path == keepPath || entity.path == '$keepPath.part') {
          continue;
        }
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Auto-unduh di background. Tidak membuka installer.
  Future<BackgroundDownloadResult> downloadInBackground({
    String appFlavor = '',
    void Function(double progress)? onProgress,
  }) async {
    // Training: Dio bypasses TrainingHttpClient — never download APKs mid-session.
    if (TrainingMode.instance.isActive) {
      return const BackgroundDownloadResult(
        status: BackgroundDownloadStatus.skipped,
        message: 'Mode Latihan — unduhan APK dinonaktifkan (anti-bocor).',
      );
    }
    if (kIsWeb || !Platform.isAndroid) {
      return const BackgroundDownloadResult(
        status: BackgroundDownloadStatus.skipped,
        message: 'Hanya Android',
      );
    }

    final info = await checkForUpdate(appFlavor: appFlavor);
    if (!info.hasUpdate || !info.urlReachable) {
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.skipped,
        info: info,
      );
    }

    // Sudah siap untuk versi server ini?
    final existing = await readyApkPath(appFlavor: appFlavor);
    final readyVer = await readyApkVersion(appFlavor: appFlavor);
    if (existing != null &&
        readyVer == info.serverVersion &&
        await _isValidApkFile(File(existing))) {
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.readyToInstall,
        info: info,
        apkPath: existing,
        message: 'Update ${info.serverVersion} sudah siap dipasang.',
      );
    }
    if (existing != null && readyVer != info.serverVersion) {
      await clearReadyApk(appFlavor: appFlavor);
    }

    final storage = await checkStorageForUpdate(
      remoteSizeBytes: info.remoteSizeBytes,
    );
    if (!storage.ok && storage.freeBytes > 0) {
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.insufficientStorage,
        info: info,
        storage: storage,
        message:
            'Penyimpanan kurang. Kosongkan ruang internal minimal ${storage.requiredLabel} '
            '(tersedia ${storage.freeLabel}).',
      );
    }

    final flavor = AppUpdateFlavor.normalize(appFlavor);
    if (_downloadBusy[flavor] == true) {
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.downloading,
        info: info,
        message: 'Unduhan update sedang berjalan…',
      );
    }

    _downloadBusy[flavor] = true;
    final dir = await _updatesDir();
    final finalPath =
        '${dir.path}/${_apkPathFor(info.serverVersion, appFlavor: appFlavor)}';
    final partPath = '$finalPath.part';
    final partFile = File(partPath);
    final finalFile = File(finalPath);

    try {
      if (!isAllowedReleaseUrl(
        info.downloadUrl,
        flavor: flavor,
        channel: BrandSlugRules.releaseChannel(),
        expectedVersion: info.serverVersion,
      )) {
        return BackgroundDownloadResult(
          status: BackgroundDownloadStatus.failed,
          info: info,
          message: 'URL update tidak sah. App lama tetap aman.',
        );
      }
      if (await partFile.exists()) await partFile.delete();
      await _purgeStaleApks(appFlavor: appFlavor, keepPath: finalPath);

      final resp = await _dio.download(
        info.downloadUrl,
        partPath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
      if (!isHttpOk(resp.statusCode)) {
        await registerDownloadFailure(appFlavor: appFlavor);
        if (await partFile.exists()) await partFile.delete();
        return BackgroundDownloadResult(
          status: BackgroundDownloadStatus.failed,
          info: info,
          message:
              'Server menolak unduhan (HTTP ${resp.statusCode}). App lama tetap aman.',
        );
      }

      if (!await _isValidApkFile(partFile)) {
        await registerDownloadFailure(appFlavor: appFlavor);
        if (await partFile.exists()) await partFile.delete();
        return BackgroundDownloadResult(
          status: BackgroundDownloadStatus.failed,
          info: info,
          message: 'File update tidak valid. App lama tetap aman.',
        );
      }
      final got = await partFile.length();
      final expect = info.remoteSizeBytes;
      if (expect != null && expect > 0 && (got - expect).abs() > 2048) {
        await registerDownloadFailure(appFlavor: appFlavor);
        if (await partFile.exists()) await partFile.delete();
        return BackgroundDownloadResult(
          status: BackgroundDownloadStatus.failed,
          info: info,
          message: 'Ukuran file update tidak cocok. App lama tetap aman.',
        );
      }

      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalPath);
      await _markReadyApk(
        finalPath,
        info.serverVersion,
        appFlavor: appFlavor,
      );
      await clearFailureState(appFlavor: appFlavor);

      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.readyToInstall,
        info: info,
        apkPath: finalPath,
        message:
            'Update ${info.serverVersion} siap. Konfirmasi untuk memasang.',
      );
    } on DioException catch (e) {
      await registerDownloadFailure(appFlavor: appFlavor);
      final lowSpace = (e.error?.toString() ?? '').contains('ENOSPC') ||
          (e.message ?? '').toLowerCase().contains('space');
      if (lowSpace) {
        final st = await checkStorageForUpdate(
          remoteSizeBytes: info.remoteSizeBytes,
        );
        return BackgroundDownloadResult(
          status: BackgroundDownloadStatus.insufficientStorage,
          info: info,
          storage: st,
          message:
              'Penyimpanan penuh saat unduh. Kosongkan ruang internal hingga tersedia sekitar ${st.requiredLabel}.',
        );
      }
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.failed,
        info: info,
        message: 'Gagal unduh update. App lama tetap bisa dipakai.',
      );
    } catch (e) {
      await registerDownloadFailure(appFlavor: appFlavor);
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.failed,
        info: info,
        message: 'Gagal unduh update: $e',
      );
    } finally {
      _downloadBusy[flavor] = false;
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Setelah user konfirmasi — buka installer sistem.
  Future<void> confirmAndOpenInstaller({
    required String apkPath,
    required String expectedVersion,
    String appFlavor = '',
  }) async {
    final file = File(apkPath);
    final dir = await _updatesDir();
    final prefix = '${dir.path}${Platform.pathSeparator}';
    final flavor = AppUpdateFlavor.normalize(appFlavor);
    final name = file.uri.pathSegments.isEmpty
        ? ''
        : file.uri.pathSegments.last;
    if (!file.absolute.path.startsWith(prefix) ||
        !name.contains('_${flavor}_')) {
      await clearReadyApk(appFlavor: appFlavor);
      throw Exception('File update tidak dari saluran resmi.');
    }
    if (!await _isValidApkFile(file)) {
      await clearReadyApk(appFlavor: appFlavor);
      throw Exception('File update hilang/rusak. Akan diunduh ulang.');
    }

    await markInstallPending(expectedVersion, appFlavor: appFlavor);
    final result = await OpenFile.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      final msg = result.message;
      if (msg.toLowerCase().contains('install') ||
          msg.contains('REQUEST_INSTALL')) {
        throw Exception('REQUEST_INSTALL_PACKAGES: $msg');
      }
      throw Exception('Installer tidak terbuka: ${result.message}');
    }
  }

  /// Kompatibilitas halaman update manual: unduh lalu minta konfirmasi terpisah.
  Future<String> downloadOnly(
    String url, {
    required String expectedVersion,
    String appFlavor = '',
    void Function(double progress)? onProgress,
  }) async {
    final result = await downloadInBackground(
      appFlavor: appFlavor,
      onProgress: onProgress,
    );
    if (result.status == BackgroundDownloadStatus.readyToInstall &&
        result.apkPath != null) {
      return result.apkPath!;
    }
    if (result.status == BackgroundDownloadStatus.insufficientStorage) {
      throw Exception(result.message ?? 'Storage kurang');
    }
    throw Exception(result.message ?? 'Gagal unduh');
  }
}
