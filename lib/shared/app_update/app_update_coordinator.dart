import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_update_service.dart';
import '../brand/brand_service.dart';
import 'app_software_update_page.dart';
import 'app_update_chrome.dart';

/// Koordinator update bersama — Karyawan / Admin / Member.
/// Cek silent, auto-unduh, dialog konfirmasi. Install tetap butuh user.
class AppUpdateCoordinator {
  AppUpdateCoordinator({
    required this.chrome,
    this.onHasUpdate,
  }) : flavor = chrome.flavor;

  final AppUpdateChrome chrome;
  final String flavor;
  final ValueChanged<bool>? onHasUpdate;

  final AppUpdateService _service = AppUpdateService();

  static final _launchDone = <String, bool>{};
  static final _lastSilentAt = <String, DateTime>{};
  static final _dialogShown = <String, bool>{};
  static final _autoRunning = <String, bool>{};
  static final _installShown = <String, bool>{};
  static final _storageShown = <String, bool>{};
  static final _silentBusy = <String, bool>{};

  static const _resumeCooldown = Duration(minutes: 90);

  Future<void> onAppResumed(BuildContext context) async {
    try {
      final outcome =
          await _service.checkPendingInstallResult(appFlavor: flavor);
      if (!context.mounted) return;
      if (outcome.updated) {
        onHasUpdate?.call(false);
        _snack(
          context,
          'update_sukses_title'.tr(),
          'update_sukses_body'.tr(
            namedArgs: {'version': outcome.localVersion},
          ),
          chrome.success,
        );
      }
    } catch (e) {
      debugPrint('cek hasil install ($flavor): $e');
    }
    if (!context.mounted) return;
    await checkSilent(context, fromResume: true);
  }

  /// Auto-unduh saat app di-minimize (bukan [inactive] — itu ikut dialog sistem).
  Future<void> onAppPaused() async {
    if (kIsWeb) return;
    final autoOn = await _service.isAutoUpdateEnabled(appFlavor: flavor);
    if (!autoOn) return;
    try {
      await _service.downloadInBackground(appFlavor: flavor);
    } catch (e) {
      debugPrint('pause download ($flavor): $e');
    }
  }

  Future<void> checkSilent(
    BuildContext context, {
    bool fromResume = false,
  }) async {
    if (kIsWeb) return;
    if (_silentBusy[flavor] == true) return;
    _silentBusy[flavor] = true;
    try {
      final readyPath = await _service.readyApkPath(appFlavor: flavor);
      if (readyPath != null && context.mounted) {
        final info = await _service.checkForUpdate(appFlavor: flavor);
        if (!context.mounted) return;
        if (!info.hasUpdate) {
          await _service.clearReadyApk(appFlavor: flavor);
          onHasUpdate?.call(false);
        } else {
          onHasUpdate?.call(true);
          final result = await _service.downloadInBackground(appFlavor: flavor);
          if (context.mounted &&
              result.status == BackgroundDownloadStatus.readyToInstall) {
            await _confirmInstall(context, result);
            return;
          }
        }
      }

      if (!fromResume) {
        if (_launchDone[flavor] == true) return;
        _launchDone[flavor] = true;
      } else {
        if (_dialogShown[flavor] == true ||
            _autoRunning[flavor] == true ||
            _installShown[flavor] == true) {
          return;
        }
        final last = _lastSilentAt[flavor];
        if (last != null && DateTime.now().difference(last) < _resumeCooldown) {
          return;
        }
      }
      _lastSilentAt[flavor] = DateTime.now();

      try {
        final info = await _service.checkForUpdate(appFlavor: flavor);
        if (!info.hasUpdate || !context.mounted) {
          if (info.hasUpdate == false) onHasUpdate?.call(false);
          return;
        }
        onHasUpdate?.call(true);

        final autoOn = await _service.isAutoUpdateEnabled(appFlavor: flavor);
        if (!context.mounted) return;
        if (autoOn && info.urlReachable) {
          await _startAutoDownload(context, silent: true);
          return;
        }

        if (_dialogShown[flavor] == true || !context.mounted) return;
        _dialogShown[flavor] = true;

        final hardForce = info.forceUpdate && info.urlReachable;
        final linkWarn =
            !info.urlReachable ? '${'update_link_warn'.tr()}\n\n' : '';
        final notes = (info.notes ?? '').trim();

        await showDialog<void>(
          context: context,
          barrierDismissible: !hardForce,
          builder: (ctx) => PopScope(
            canPop: !hardForce,
            child: _dialogShell(
              ctx,
              title: hardForce ? 'update_wajib'.tr() : 'update_available'.tr(),
              body: '${'update_dialog_body'.tr(namedArgs: {
                    'server': info.serverVersion,
                    'local': info.localVersion,
                  })}\n\n$linkWarn$notes',
              cancelLabel: hardForce ? null : 'btn_nanti'.tr(),
              confirmLabel: info.urlReachable
                  ? 'update_btn_download'.tr()
                  : 'update_cek_ulang'.tr(),
              onConfirm: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AppSoftwareUpdatePage(
                      chrome: chrome,
                      autoStartDownload: info.urlReachable,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } catch (e) {
        debugPrint('cek update ($flavor): $e');
      } finally {
        _dialogShown[flavor] = false;
      }
    } finally {
      _silentBusy[flavor] = false;
    }
  }

  Future<void> _startAutoDownload(
    BuildContext context, {
    bool silent = false,
  }) async {
    if (kIsWeb || _autoRunning[flavor] == true) return;
    final autoOn = await _service.isAutoUpdateEnabled(appFlavor: flavor);
    if (!autoOn) return;

    _autoRunning[flavor] = true;
    try {
      final result = await _service.downloadInBackground(appFlavor: flavor);
      if (!context.mounted) return;

      switch (result.status) {
        case BackgroundDownloadStatus.readyToInstall:
          onHasUpdate?.call(true);
          await _confirmInstall(context, result);
        case BackgroundDownloadStatus.insufficientStorage:
          onHasUpdate?.call(true);
          await _storageDialog(context, result);
        case BackgroundDownloadStatus.downloading:
          if (!silent) {
            _snack(
              context,
              'update_unduh_bg_title'.tr(),
              'update_unduh_bg_body'.tr(),
              chrome.accent,
            );
          }
        case BackgroundDownloadStatus.failed:
          if (!silent && (result.message ?? '').isNotEmpty) {
            _snack(
              context,
              'update_fail_title'.tr(),
              result.message!,
              chrome.warning,
            );
          }
        case BackgroundDownloadStatus.skipped:
          break;
      }
    } catch (e) {
      debugPrint('auto download ($flavor): $e');
    } finally {
      _autoRunning[flavor] = false;
    }
  }

  Future<void> _storageDialog(
    BuildContext context,
    BackgroundDownloadResult result,
  ) async {
    if (_storageShown[flavor] == true || !context.mounted) return;
    _storageShown[flavor] = true;
    final st = result.storage;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _dialogShell(
          ctx,
          title: 'update_storage_title'.tr(),
          body: 'update_storage_body'.tr(namedArgs: {
            'need': st?.requiredLabel ?? '—',
            'free': st?.freeLabel ?? '-',
          }),
          cancelLabel: 'btn_mengerti'.tr(),
          confirmLabel: 'btn_coba_lagi'.tr(),
          onConfirm: () {
            Navigator.pop(ctx);
            _storageShown[flavor] = false;
            _startAutoDownload(context);
          },
        ),
      );
    } finally {
      _storageShown[flavor] = false;
    }
  }

  Future<void> _confirmInstall(
    BuildContext context,
    BackgroundDownloadResult result,
  ) async {
    if (_installShown[flavor] == true || !context.mounted) return;
    final path = result.apkPath;
    final info = result.info;
    if (path == null || info == null) return;

    _installShown[flavor] = true;
    final hardForce = info.forceUpdate;
    final notes = (info.notes ?? '').trim();

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !hardForce,
        builder: (ctx) => PopScope(
          canPop: !hardForce,
          child: _dialogShell(
            ctx,
            title: hardForce
                ? 'update_siap_wajib_title'.tr()
                : 'update_siap_title'.tr(),
            body: '${'update_siap_body'.tr(namedArgs: {
                  'version': info.serverVersion,
                })}\n\n$notes',
            cancelLabel: hardForce ? null : 'btn_nanti'.tr(),
            confirmLabel: 'btn_pasang_sekarang'.tr(),
            onConfirm: () async {
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
                  'update_install_opened'.tr(),
                  'update_installer_hint'.tr(),
                  chrome.success,
                );
              } catch (e) {
                if (!context.mounted) return;
                final pesan = e.toString().replaceAll('Exception: ', '');
                if (pesan.contains('REQUEST_INSTALL_PACKAGES')) {
                  _snack(
                    context,
                    'update_install_izin_title'.tr(),
                    'update_install_izin_body'.tr(
                      namedArgs: {'app': BrandService.name},
                    ),
                    chrome.warning,
                  );
                } else {
                  _snack(
                      context, 'update_fail_title'.tr(), pesan, chrome.danger);
                }
              }
            },
          ),
        ),
      );
    } finally {
      _installShown[flavor] = false;
    }
  }

  Widget _dialogShell(
    BuildContext ctx, {
    required String title,
    required String body,
    String? cancelLabel,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) {
    return AlertDialog(
      backgroundColor: chrome.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: chrome.muted.withValues(alpha: 0.25)),
      ),
      title: Text(
        title,
        style: TextStyle(color: chrome.ink, fontWeight: FontWeight.w800),
      ),
      content: Text(
        body.trim(),
        style: TextStyle(color: chrome.muted, height: 1.4),
      ),
      actions: [
        if (cancelLabel != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelLabel, style: TextStyle(color: chrome.muted)),
          ),
        FilledButton(
          onPressed: onConfirm,
          style: FilledButton.styleFrom(backgroundColor: chrome.accent),
          child: Text(confirmLabel),
        ),
      ],
    );
  }

  void _snack(
    BuildContext context,
    String title,
    String body,
    Color color,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title — $body'),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
