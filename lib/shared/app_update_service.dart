import 'dart:io';

import 'package:dio/dio.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Update APK Karyawan: auto-download aman, install tetap konfirmasi user.
class AppUpdateService {
  AppUpdateService({SupabaseClient? client, Dio? dio})
      : _client = client ?? Supabase.instance.client,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 10),
              followRedirects: true,
              validateStatus: (s) => s != null && s < 500,
            ));

  final SupabaseClient _client;
  final Dio _dio;
  final _disk = DiskSpacePlus();

  static const prefAutoUpdate = 'auto_update_karyawan';
  static const prefPendingVersion = 'update_pending_version';
  static const prefFailCount = 'update_fail_count';
  static const prefSkipForceUntil = 'update_skip_force_until_ms';
  static const prefReadyPath = 'update_ready_apk_path';
  static const prefReadyVersion = 'update_ready_apk_version';
  static const minApkBytes = 512 * 1024;
  static const storageBufferBytes = 40 * 1024 * 1024; // +40 MB buffer

  static bool _downloadBusy = false;

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
    List<int> parse(String v) {
      final core = v.split('+').first.split('-').first.trim();
      if (core.isEmpty) return [0];
      return core
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final a = parse(server);
    final b = parse(local);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static bool isSafeDownloadUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    final path = uri.path.toLowerCase();
    if (path.endsWith('.html') || path.endsWith('.htm')) return false;
    return true;
  }

  Future<bool> isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // Default ON: auto-unduh di background; install tetap konfirmasi.
    return prefs.getBool(prefAutoUpdate) ?? true;
  }

  Future<void> setAutoUpdateEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefAutoUpdate, value);
  }

  Future<bool> shouldEnforceForceUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(prefSkipForceUntil) ?? 0;
    return DateTime.now().millisecondsSinceEpoch >= until;
  }

  Future<void> registerDownloadFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt(prefFailCount) ?? 0) + 1;
    await prefs.setInt(prefFailCount, n);
    if (n >= 3) {
      final until = DateTime.now()
          .add(const Duration(hours: 6))
          .millisecondsSinceEpoch;
      await prefs.setInt(prefSkipForceUntil, until);
      await prefs.setInt(prefFailCount, 0);
    }
  }

  Future<void> clearFailureState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefFailCount);
    await prefs.remove(prefSkipForceUntil);
  }

  Future<void> markInstallPending(String expectedVersion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefPendingVersion, expectedVersion);
  }

  Future<void> clearInstallPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefPendingVersion);
  }

  Future<InstallOutcome> checkPendingInstallResult() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final local = packageInfo.version;
    final prefs = await SharedPreferences.getInstance();
    final expected = prefs.getString(prefPendingVersion);

    if (expected == null || expected.isEmpty) {
      return InstallOutcome(updated: false, localVersion: local);
    }

    final updated = compareSemver(local, expected) >= 0;
    if (updated) {
      await clearInstallPending();
      await clearFailureState();
      await clearReadyApk();
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

  Future<bool> preflightUrl(String url) async {
    if (!isSafeDownloadUrl(url)) return false;
    try {
      final head = await _dio.head(url);
      if (head.statusCode != null &&
          head.statusCode! >= 200 &&
          head.statusCode! < 400) {
        return true;
      }
    } catch (_) {}
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-3'},
        ),
      );
      final code = res.statusCode ?? 0;
      return code == 200 || code == 206;
    } catch (_) {
      return false;
    }
  }

  Future<AppUpdateInfo> checkForUpdate({String appFlavor = 'karyawan'}) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final local = packageInfo.version;

    Map<String, dynamic>? data;
    try {
      data = await _client
          .from('versi_app')
          .select()
          .eq('app_flavor', appFlavor)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (_) {
      data = null;
    }
    data ??= await _client
        .from('versi_app')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final server = (data?['versi_terbaru'] ?? local).toString().trim();
    final url = (data?['url_download'] ?? '').toString().trim();
    final forceFlag = data?['force_update'] == true;
    final notes = data?['catatan_rilis']?.toString();
    final newer = compareSemver(server, local) > 0 && url.isNotEmpty;

    var reachable = true;
    int? remoteSize;
    if (newer) {
      reachable = await preflightUrl(url);
      if (reachable) remoteSize = await probeRemoteSizeBytes(url);
    }

    final enforceForce = await shouldEnforceForceUpdate();
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

  Future<String?> readyApkPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(prefReadyPath);
    final ver = prefs.getString(prefReadyVersion);
    if (path == null || ver == null) return null;
    final f = File(path);
    if (!await f.exists()) {
      await clearReadyApk();
      return null;
    }
    return path;
  }

  Future<String?> readyApkVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefReadyVersion);
  }

  Future<void> _markReadyApk(String path, String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefReadyPath, path);
    await prefs.setString(prefReadyVersion, version);
  }

  Future<void> clearReadyApk() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(prefReadyPath);
    await prefs.remove(prefReadyPath);
    await prefs.remove(prefReadyVersion);
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

  String _apkPathFor(String version) {
    final safe = version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    return 'optik_karyawan_$safe.apk';
  }

  /// Auto-unduh di background. Tidak membuka installer.
  Future<BackgroundDownloadResult> downloadInBackground({
    String appFlavor = 'karyawan',
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

    // Sudah siap?
    final existing = await readyApkPath();
    final readyVer = await readyApkVersion();
    if (existing != null && readyVer == info.serverVersion) {
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.readyToInstall,
        info: info,
        apkPath: existing,
        message: 'Update ${info.serverVersion} sudah siap dipasang.',
      );
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

    if (_downloadBusy) {
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.downloading,
        info: info,
        message: 'Unduhan update sedang berjalan…',
      );
    }

    _downloadBusy = true;
    final dir = await getTemporaryDirectory();
    final finalPath = '${dir.path}/${_apkPathFor(info.serverVersion)}';
    final partPath = '$finalPath.part';
    final partFile = File(partPath);
    final finalFile = File(finalPath);

    try {
      if (await partFile.exists()) await partFile.delete();

      await _dio.download(
        info.downloadUrl,
        partPath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      if (!await _isValidApkFile(partFile)) {
        await registerDownloadFailure();
        if (await partFile.exists()) await partFile.delete();
        return BackgroundDownloadResult(
          status: BackgroundDownloadStatus.failed,
          info: info,
          message: 'File update tidak valid. App lama tetap aman.',
        );
      }

      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalPath);
      await _markReadyApk(finalPath, info.serverVersion);
      await clearFailureState();

      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.readyToInstall,
        info: info,
        apkPath: finalPath,
        message: 'Update ${info.serverVersion} siap. Konfirmasi untuk memasang.',
      );
    } on DioException catch (e) {
      await registerDownloadFailure();
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
      await registerDownloadFailure();
      return BackgroundDownloadResult(
        status: BackgroundDownloadStatus.failed,
        info: info,
        message: 'Gagal unduh update: $e',
      );
    } finally {
      _downloadBusy = false;
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Setelah karyawan konfirmasi — buka installer sistem.
  Future<void> confirmAndOpenInstaller({
    required String apkPath,
    required String expectedVersion,
  }) async {
    final file = File(apkPath);
    if (!await _isValidApkFile(file)) {
      await clearReadyApk();
      throw Exception('File update hilang/rusak. Akan diunduh ulang.');
    }

    await markInstallPending(expectedVersion);
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
    void Function(double progress)? onProgress,
  }) async {
    final result = await downloadInBackground(onProgress: onProgress);
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
