import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/app_update_service.dart';
import '../../shared/theme.dart';
import 'pages/member_software_update_page.dart';
import '../../shared/brand/brand_service.dart';

/// Koordinator update Member — cek silent, auto-unduh, dialog putih–biru.
/// Digunakan dari [MemberShell] supaya alur unduh/pasang tidak nge-bug.
class MemberUpdateCoordinator {
  MemberUpdateCoordinator();

  final AppUpdateService _service = AppUpdateService();
  static const flavor = MemberSoftwareUpdatePage.flavor;

  bool _dialogShown = false;
  bool _autoDownloadRunning = false;
  bool _installConfirmShown = false;
  bool _storageDialogShown = false;

  /// Hindari dialog dobel dari MemberApp + MemberShell di sesi yang sama.
  static bool _launchCheckDone = false;

  /// Resume boleh cek ulang, tapi tidak spam tiap switch-app.
  static DateTime? _lastSilentCheckAt;
  static const _resumeCheckCooldown = Duration(hours: 6);

  Future<void> onAppResumed(BuildContext context) async {
    try {
      final outcome =
          await _service.checkPendingInstallResult(appFlavor: flavor);
      if (!context.mounted) return;
      if (outcome.updated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Update berhasil — sekarang versi ${outcome.localVersion}.',
            ),
            backgroundColor: OptikMemberTokens.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('member cek hasil install: $e');
    }
    if (!context.mounted) return;
    // Blok 2.9: setelah resume, cek update baru (throttled).
    await checkSilent(context, fromResume: true);
  }

  Future<void> checkSilent(
    BuildContext context, {
    bool fromResume = false,
  }) async {
    if (kIsWeb) return;
    if (!fromResume) {
      if (_launchCheckDone) return;
      _launchCheckDone = true;
    } else {
      if (_dialogShown || _autoDownloadRunning || _installConfirmShown) return;
      final last = _lastSilentCheckAt;
      if (last != null &&
          DateTime.now().difference(last) < _resumeCheckCooldown) {
        return;
      }
    }
    _lastSilentCheckAt = DateTime.now();
    try {
      final info = await _service.checkForUpdate(appFlavor: flavor);
      if (!info.hasUpdate || !context.mounted) return;

      final autoOn = await _service.isAutoUpdateEnabled(appFlavor: flavor);
      if (!context.mounted) return;
      if (autoOn && info.urlReachable) {
        await _startAutoDownload(context, silent: true);
        return;
      }

      if (_dialogShown || !context.mounted) return;
      _dialogShown = true;

      final hardForce = info.forceUpdate && info.urlReachable;

      await showDialog<void>(
        context: context,
        barrierDismissible: !hardForce,
        builder: (ctx) => PopScope(
          canPop: !hardForce,
          child: AlertDialog(
            backgroundColor: OptikMemberTokens.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
            ),
            title: Text(
              hardForce ? 'Update wajib' : 'Update tersedia',
              style: const TextStyle(
                color: OptikMemberTokens.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              'Versi baru ${info.serverVersion} siap '
              '(saat ini ${info.localVersion}).\n'
              'Unduh bisa otomatis; pemasangan tetap butuh konfirmasi Anda.\n\n'
              '${!info.urlReachable ? '⚠️ Link unduhan belum siap. Anda tetap bisa pakai app.\n\n' : ''}'
              '${info.notes ?? ''}',
              style: const TextStyle(
                color: OptikMemberTokens.inkSecondary,
                height: 1.4,
              ),
            ),
            actions: [
              if (!hardForce)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Nanti'),
                ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemberSoftwareUpdatePage(
                        autoStartDownload: info.urlReachable,
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: OptikMemberTokens.blueDeep,
                ),
                child: Text(
                  info.urlReachable ? 'Unduh update' : 'Cek update',
                ),
              ),
            ],
          ),
        ),
      );
      _dialogShown = false;
    } catch (e) {
      debugPrint('member cek update: $e');
    }
  }

  Future<void> _startAutoDownload(
    BuildContext context, {
    bool silent = false,
  }) async {
    if (kIsWeb || _autoDownloadRunning) return;
    final autoOn = await _service.isAutoUpdateEnabled(appFlavor: flavor);
    if (!autoOn) return;

    _autoDownloadRunning = true;
    try {
      final result = await _service.downloadInBackground(appFlavor: flavor);
      if (!context.mounted) return;

      switch (result.status) {
        case BackgroundDownloadStatus.readyToInstall:
          await _confirmInstall(context, result);
        case BackgroundDownloadStatus.insufficientStorage:
          await _storageDialog(context, result);
        case BackgroundDownloadStatus.downloading:
          if (!silent) {
            _snack(
              context,
              'Update diunduh di belakang. App tetap bisa dipakai.',
              OptikMemberTokens.blue,
            );
          }
        case BackgroundDownloadStatus.failed:
          if (!silent && (result.message ?? '').isNotEmpty) {
            _snack(context, result.message!, OptikMemberTokens.warning);
          }
        case BackgroundDownloadStatus.skipped:
          break;
      }
    } catch (e) {
      debugPrint('member auto download: $e');
    } finally {
      _autoDownloadRunning = false;
    }
  }

  Future<void> _storageDialog(
    BuildContext context,
    BackgroundDownloadResult result,
  ) async {
    if (_storageDialogShown || !context.mounted) return;
    _storageDialogShown = true;
    final st = result.storage;
    final butuh = st?.requiredLabel ?? 'beberapa puluh MB';
    final sisa = st?.freeLabel ?? '-';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikMemberTokens.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
        ),
        title: const Text(
          'Penyimpanan kurang',
          style: TextStyle(
            color: OptikMemberTokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Storage internal tidak cukup untuk mengunduh update.\n\n'
          'Dibutuhkan sekitar $butuh (tersedia $sisa).\n\n'
          'Kosongkan ruang, lalu buka lagi aplikasi — unduhan dilanjutkan otomatis.',
          style: const TextStyle(
            color: OptikMemberTokens.inkSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _storageDialogShown = false;
              _startAutoDownload(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: OptikMemberTokens.blueDeep,
            ),
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
    _storageDialogShown = false;
  }

  Future<void> _confirmInstall(
    BuildContext context,
    BackgroundDownloadResult result,
  ) async {
    if (_installConfirmShown || !context.mounted) return;
    final path = result.apkPath;
    final info = result.info;
    if (path == null || info == null) return;

    _installConfirmShown = true;
    final hardForce = info.forceUpdate;

    await showDialog<void>(
      context: context,
      barrierDismissible: !hardForce,
      builder: (ctx) => PopScope(
        canPop: !hardForce,
        child: AlertDialog(
          backgroundColor: OptikMemberTokens.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
          ),
          title: Text(
            hardForce ? 'Update wajib siap dipasang' : 'Update siap dipasang',
            style: const TextStyle(
              color: OptikMemberTokens.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Versi ${info.serverVersion} sudah diunduh.\n'
            'Pasang sekarang? App lama tetap aman sampai instalasi selesai.\n\n'
            '${info.notes ?? ''}',
            style: const TextStyle(
              color: OptikMemberTokens.inkSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            if (!hardForce)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Nanti'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _service.confirmAndOpenInstaller(
                    apkPath: path,
                    expectedVersion: info.serverVersion,
                    appFlavor: flavor,
                  );
                  if (!context.mounted) return;
                  _snack(
                    context,
                    'Konfirmasi di layar sistem untuk memasang update.',
                    OptikMemberTokens.success,
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  final pesan = e.toString().replaceAll('Exception: ', '');
                  if (pesan.contains('REQUEST_INSTALL_PACKAGES')) {
                    _snack(
                      context,
                      'Aktifkan “Instal aplikasi tidak dikenal” untuk ${BrandService.name} Member.',
                      OptikMemberTokens.warning,
                    );
                  } else {
                    _snack(context, pesan, OptikMemberTokens.danger);
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: OptikMemberTokens.blueDeep,
              ),
              child: const Text('Pasang sekarang'),
            ),
          ],
        ),
      ),
    );
    _installConfirmShown = false;
  }

  void _snack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
