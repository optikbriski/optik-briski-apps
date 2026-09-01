import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../apps/member/member_layout.dart';
import '../../apps/member/member_widgets.dart';
import '../app_update_service.dart';
import '../admin/admin_nav_badge_service.dart';
import '../brand/brand_service.dart';
import '../theme.dart';
import '../widgets/admin/admin_premium.dart';
import 'app_update_chrome.dart';

/// Halaman update APK bersama — Karyawan / Admin / Member.
class AppSoftwareUpdatePage extends StatefulWidget {
  const AppSoftwareUpdatePage({
    super.key,
    required this.chrome,
    this.autoStartDownload = false,
    this.embedded = false,
  });

  const AppSoftwareUpdatePage.karyawan({
    super.key,
    this.autoStartDownload = false,
    this.embedded = false,
  }) : chrome = AppUpdateChrome.karyawan;

  const AppSoftwareUpdatePage.member({
    super.key,
    this.autoStartDownload = false,
    this.embedded = false,
  }) : chrome = AppUpdateChrome.member;

  AppSoftwareUpdatePage.admin({
    super.key,
    this.autoStartDownload = false,
    this.embedded = true,
  }) : chrome = AppUpdateChrome.admin;

  final AppUpdateChrome chrome;
  final bool autoStartDownload;

  /// Admin sidebar: tanpa AppBar dobel (panel sudah punya judul).
  final bool embedded;

  @override
  State<AppSoftwareUpdatePage> createState() => _AppSoftwareUpdatePageState();
}

class _AppSoftwareUpdatePageState extends State<AppSoftwareUpdatePage> {
  final _service = AppUpdateService();

  bool _isAutoUpdateOn = true;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _readyToInstall = false;
  String? _readyApkPath;
  double _downloadProgress = 0;
  String? _statusHint;
  AppUpdateInfo? _info;

  String get _flavor => widget.chrome.flavor;
  AppUpdateChrome get _c => widget.chrome;

  @override
  void initState() {
    super.initState();
    if (widget.chrome.flavor == AppUpdateFlavor.admin) {
      unawaited(AdminNavBadgeService.instance.markEntitySeen(
        'update_apk',
        AdminNavBadgeService.apkEntityId,
      ));
    }
    _boot();
  }

  Future<void> _boot() async {
    await _refresh();
    if (widget.autoStartDownload &&
        (_info?.hasUpdate ?? false) &&
        (_info?.urlReachable ?? false) &&
        !_readyToInstall &&
        !kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unduhUpdate();
      });
    } else if (widget.autoStartDownload &&
        (_info?.hasUpdate ?? false) &&
        !(_info?.urlReachable ?? true)) {
      if (!mounted) return;
      setState(() => _statusHint = 'update_link_apk_fail'.tr());
    }
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _isLoading = true);
    _isAutoUpdateOn = await _service.isAutoUpdateEnabled(appFlavor: _flavor);
    try {
      _info = await _service.checkForUpdate(appFlavor: _flavor);
      final readyPath = await _service.readyApkPath(appFlavor: _flavor);
      final readyVer = await _service.readyApkVersion(appFlavor: _flavor);
      if (readyPath != null &&
          readyVer != null &&
          _info != null &&
          readyVer == _info!.serverVersion) {
        _readyToInstall = true;
        _readyApkPath = readyPath;
        _statusHint = 'update_ready_hint'.tr(
          namedArgs: {'version': _info!.serverVersion},
        );
      } else {
        _readyToInstall = false;
        _readyApkPath = null;
      }
    } catch (e) {
      debugPrint('cek versi ($_flavor): $e');
      _statusHint = 'update_cek_gagal'.tr();
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _unduhUpdate() async {
    final info = _info;
    if (info == null || !info.hasUpdate || _isDownloading) return;

    if (kIsWeb) {
      _snack('update_web_android'.tr(), _c.warning);
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _statusHint = 'update_mengunduh_hint'.tr();
      _readyToInstall = false;
    });

    try {
      final result = await _service.downloadInBackground(
        appFlavor: _flavor,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;

      switch (result.status) {
        case BackgroundDownloadStatus.readyToInstall:
          setState(() {
            _readyToInstall = true;
            _readyApkPath = result.apkPath;
            _statusHint = result.message ??
                'update_ready_hint'.tr(
                  namedArgs: {'version': info.serverVersion},
                );
          });
        case BackgroundDownloadStatus.insufficientStorage:
          setState(() => _statusHint = result.message);
          await _showStorageDialog(result.storage);
        case BackgroundDownloadStatus.failed:
        case BackgroundDownloadStatus.skipped:
        case BackgroundDownloadStatus.downloading:
          setState(() => _statusHint = result.message);
          if ((result.message ?? '').isNotEmpty) {
            _snack(result.message!, _c.warning);
          }
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _showStorageDialog(StorageCheck? st) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'update_storage_title'.tr(),
          style: TextStyle(color: _c.ink, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'update_storage_body'.tr(namedArgs: {
            'need': st?.requiredLabel ?? '—',
            'free': st?.freeLabel ?? '-',
          }),
          style: TextStyle(color: _c.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('btn_mengerti'.tr()),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _unduhUpdate();
            },
            style: FilledButton.styleFrom(backgroundColor: _c.accent),
            child: Text('btn_coba_lagi'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _pasangUpdate() async {
    final info = _info;
    final path = _readyApkPath;
    if (info == null || path == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'update_pasang_title'.tr(),
          style: TextStyle(color: _c.ink, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'update_pasang_body'.tr(namedArgs: {'version': info.serverVersion}),
          style: TextStyle(color: _c.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('btn_nanti'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _c.accent),
            child: Text('btn_pasang_sekarang'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _service.confirmAndOpenInstaller(
        apkPath: path,
        expectedVersion: info.serverVersion,
        appFlavor: _flavor,
      );
      if (!mounted) return;
      setState(() => _statusHint = 'update_installer_hint'.tr());
      _snack('update_install_opened'.tr(), _c.success);
    } catch (e) {
      if (!mounted) return;
      final pesan = e.toString().replaceAll('Exception: ', '');
      setState(() => _statusHint = pesan);
      if (pesan.contains('REQUEST_INSTALL_PACKAGES')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _c.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'update_install_izin_title'.tr(),
              style: TextStyle(color: _c.ink, fontWeight: FontWeight.w800),
            ),
            content: Text(
              'update_install_izin_body'.tr(
                namedArgs: {'app': BrandService.name},
              ),
              style: TextStyle(color: _c.muted, height: 1.4),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(backgroundColor: _c.accent),
                child: Text('btn_mengerti'.tr()),
              ),
            ],
          ),
        );
      } else {
        _snack('${'update_fail_title'.tr()}: $pesan', _c.danger);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? Center(child: CircularProgressIndicator(color: _c.accent))
        : _buildBody();

    switch (_c.kind) {
      case AppUpdateKind.member:
        return MemberPremiumScaffold(
          title: 'update_title'.tr(),
          subtitle: '${'update_version'.tr()} ${_info?.localVersion ?? '-'}',
          body: MemberLayout.constrain(context, body),
        );
      case AppUpdateKind.admin:
        if (widget.embedded) {
          return PremiumScaffold(body: body);
        }
        return PremiumScaffold(
          appBar: PremiumAppBar(
            title: 'update_title'.tr(),
            subtitle: '${'update_version'.tr()} ${_info?.localVersion ?? '-'}',
          ),
          body: body,
        );
      case AppUpdateKind.karyawan:
        return Scaffold(
          backgroundColor: _c.scaffoldBg,
          appBar: AppBar(
            title: Text(
              'update_title'.tr(),
              style: TextStyle(fontWeight: FontWeight.bold, color: _c.ink),
            ),
            backgroundColor: _c.surface,
            foregroundColor: _c.ink,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: OptikKaryawanTokens.border),
            ),
          ),
          body: body,
        );
    }
  }

  Widget _buildBody() {
    final info = _info;
    final adaUpdate = info?.hasUpdate ?? false;
    final pad = _c.kind == AppUpdateKind.admin
        ? const EdgeInsets.fromLTRB(20, 16, 20, 28)
        : const EdgeInsets.all(24);

    return ListView(
      padding: pad,
      children: [
        _autoTile(),
        const SizedBox(height: 18),
        _statusCard(info, adaUpdate),
        if (_statusHint != null) ...[
          const SizedBox(height: 14),
          Text(
            _statusHint!,
            textAlign: TextAlign.center,
            style: TextStyle(color: _c.muted, fontSize: 12.5, height: 1.4),
          ),
        ],
        const SizedBox(height: 18),
        Center(
          child: TextButton.icon(
            onPressed: _isDownloading ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('update_cek_ulang'.tr()),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'update_safe_note'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(color: _c.muted, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }

  Widget _autoTile() {
    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'update_auto'.tr(),
                style: TextStyle(
                  color: _c.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'update_auto_hint'.tr(),
                style: TextStyle(color: _c.muted, fontSize: 12, height: 1.3),
              ),
            ],
          ),
        ),
        Text(
          _isAutoUpdateOn ? 'update_on'.tr() : 'update_off'.tr(),
          style: TextStyle(
            color: _isAutoUpdateOn ? _c.success : _c.muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        CupertinoSwitch(
          value: _isAutoUpdateOn,
          activeTrackColor: _c.switchActive,
          onChanged: (val) async {
            await _service.setAutoUpdateEnabled(val, appFlavor: _flavor);
            setState(() => _isAutoUpdateOn = val);
          },
        ),
      ],
    );

    if (_c.kind == AppUpdateKind.admin) {
      return PremiumPanel(child: row);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _c.muted.withValues(alpha: 0.2)),
      ),
      child: row,
    );
  }

  Widget _statusCard(AppUpdateInfo? info, bool adaUpdate) {
    final inner = Column(
      children: [
        Icon(
          adaUpdate
              ? Icons.system_update_rounded
              : Icons.check_circle_outline_rounded,
          size: 56,
          color: adaUpdate ? _c.accent : _c.success,
        ),
        const SizedBox(height: 16),
        Text(
          adaUpdate
              ? 'update_available'.tr()
              : 'update_up_to_date'.brandTr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _c.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          adaUpdate
              ? '${info!.localVersion}  →  ${info.serverVersion}'
              : '${'update_version'.tr()} ${info?.localVersion ?? '-'}',
          style: TextStyle(color: _c.muted, fontWeight: FontWeight.w600),
        ),
        if (adaUpdate && !(info?.urlReachable ?? true)) ...[
          const SizedBox(height: 12),
          Text(
            'update_link_belum_siap'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: _c.warning, height: 1.35),
          ),
        ],
        if (adaUpdate && (info?.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            info!.notes!,
            textAlign: TextAlign.center,
            style: TextStyle(color: _c.muted, height: 1.4),
          ),
        ],
        if (adaUpdate) ...[
          const SizedBox(height: 22),
          if (_isDownloading)
            Column(
              children: [
                LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  backgroundColor: _c.muted.withValues(alpha: 0.2),
                  color: _c.accent,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 10),
                Text(
                  '${'update_downloading'.tr()} ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: _c.muted, fontWeight: FontWeight.w700),
                ),
              ],
            )
          else if (_readyToInstall)
            FilledButton.icon(
              onPressed: _pasangUpdate,
              icon: const Icon(Icons.install_mobile_rounded),
              label: Text('btn_pasang_sekarang'.tr()),
              style: FilledButton.styleFrom(
                backgroundColor: _c.accent,
                foregroundColor: _c.onAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            )
          else
            FilledButton.icon(
              onPressed: (info?.urlReachable ?? false) ? _unduhUpdate : null,
              icon: const Icon(Icons.download_rounded),
              label: Text('update_btn_download'.tr()),
              style: FilledButton.styleFrom(
                backgroundColor: _c.accent,
                foregroundColor: _c.onAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
        ],
      ],
    );

    if (_c.kind == AppUpdateKind.admin) {
      return PremiumPanel(padding: const EdgeInsets.all(22), child: inner);
    }
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _c.muted.withValues(alpha: 0.18)),
      ),
      child: inner,
    );
  }
}
