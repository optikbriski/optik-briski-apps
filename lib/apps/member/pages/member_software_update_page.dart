import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../shared/app_update_service.dart';
import '../../../shared/theme.dart';
import '../member_layout.dart';
import '../member_widgets.dart';
import '../../../shared/brand/brand_service.dart';

/// Update APK Member — putih–biru, unduh aman, pasang tetap konfirmasi.
class MemberSoftwareUpdatePage extends StatefulWidget {
  const MemberSoftwareUpdatePage({
    super.key,
    this.autoStartDownload = false,
  });

  final bool autoStartDownload;

  static const flavor = 'member';

  @override
  State<MemberSoftwareUpdatePage> createState() =>
      _MemberSoftwareUpdatePageState();
}

class _MemberSoftwareUpdatePageState extends State<MemberSoftwareUpdatePage> {
  final _service = AppUpdateService();

  bool _isAutoUpdateOn = true;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _readyToInstall = false;
  String? _readyApkPath;
  double _downloadProgress = 0;
  String? _statusHint;
  String _localVersion = '-';
  AppUpdateInfo? _info;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      _localVersion = pkg.version;
    } catch (_) {}
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
      setState(() {
        _statusHint =
            'Link unduhan belum siap. App lama tetap aman. Periksa baris versi_app (flavor member).';
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    _isAutoUpdateOn = await _service.isAutoUpdateEnabled(
      appFlavor: MemberSoftwareUpdatePage.flavor,
    );
    try {
      _info = await _service.checkForUpdate(
        appFlavor: MemberSoftwareUpdatePage.flavor,
      );
      final readyPath = await _service.readyApkPath(
        appFlavor: MemberSoftwareUpdatePage.flavor,
      );
      final readyVer = await _service.readyApkVersion(
        appFlavor: MemberSoftwareUpdatePage.flavor,
      );
      if (readyPath != null &&
          readyVer != null &&
          _info != null &&
          readyVer == _info!.serverVersion) {
        _readyToInstall = true;
        _readyApkPath = readyPath;
        _statusHint =
            'Update ${_info!.serverVersion} sudah diunduh. Konfirmasi untuk memasang.';
      } else {
        _readyToInstall = false;
        _readyApkPath = null;
      }
      if (_info != null) _localVersion = _info!.localVersion;
    } catch (e) {
      debugPrint('member cek versi: $e');
      _statusHint = 'Gagal cek update. Coba lagi nanti — app tetap bisa dipakai.';
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _unduhUpdate() async {
    final info = _info;
    if (info == null || !info.hasUpdate || _isDownloading) return;

    if (kIsWeb) {
      _snack('Update APK hanya di HP Android.', OptikMemberTokens.warning);
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _statusHint = 'Mengunduh… App yang terpasang tidak dihapus.';
      _readyToInstall = false;
    });

    try {
      final result = await _service.downloadInBackground(
        appFlavor: MemberSoftwareUpdatePage.flavor,
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
                'Update siap. Tekan “Pasang sekarang” untuk konfirmasi.';
          });
        case BackgroundDownloadStatus.insufficientStorage:
          setState(() => _statusHint = result.message);
          await _showStorageDialog(result.storage);
        case BackgroundDownloadStatus.failed:
        case BackgroundDownloadStatus.skipped:
        case BackgroundDownloadStatus.downloading:
          setState(() => _statusHint = result.message);
          if ((result.message ?? '').isNotEmpty) {
            _snack(result.message!, OptikMemberTokens.warning);
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
          'Kosongkan storage internal sampai tersedia sekitar '
          '${st?.requiredLabel ?? 'beberapa puluh MB'} '
          '(sekarang ${st?.freeLabel ?? '-'}).\n\n'
          'App lama tetap aman. Setelah ada ruang, unduhan bisa dilanjutkan.',
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
              _unduhUpdate();
            },
            style: FilledButton.styleFrom(
              backgroundColor: OptikMemberTokens.blueDeep,
            ),
            child: const Text('Coba lagi'),
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
        backgroundColor: OptikMemberTokens.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
        ),
        title: const Text(
          'Pasang update?',
          style: TextStyle(
            color: OptikMemberTokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Versi ${info.serverVersion} akan dipasang.\n'
          'Konfirmasi lagi di layar sistem Android setelah ini.\n\n'
          'App lama tetap aman jika Anda batalkan.',
          style: const TextStyle(
            color: OptikMemberTokens.inkSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: OptikMemberTokens.blueDeep,
            ),
            child: const Text('Pasang'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _service.confirmAndOpenInstaller(
        apkPath: path,
        expectedVersion: info.serverVersion,
        appFlavor: MemberSoftwareUpdatePage.flavor,
      );
      if (!mounted) return;
      setState(() {
        _statusHint =
            'Installer terbuka. Selesaikan di layar sistem.\n'
            'Jika dibatalkan, app lama tetap bisa dipakai.';
      });
      _snack(
        'Konfirmasi instalasi di layar sistem Android.',
        OptikMemberTokens.success,
      );
    } catch (e) {
      if (!mounted) return;
      final pesan = e.toString().replaceAll('Exception: ', '');
      setState(() => _statusHint = pesan);

      if (pesan.contains('REQUEST_INSTALL_PACKAGES')) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: OptikMemberTokens.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
            ),
            title: const Text(
              'Izin instalasi diperlukan',
              style: TextStyle(
                color: OptikMemberTokens.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              'Buka Pengaturan → Akses khusus → Instal aplikasi tidak dikenal '
              '→ aktifkan untuk ${BrandService.name} Member, lalu coba lagi.\n\n'
              'App yang terpasang tidak rusak.',
              style: const TextStyle(
                color: OptikMemberTokens.inkSecondary,
                height: 1.4,
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: OptikMemberTokens.blueDeep,
                ),
                child: const Text('Mengerti'),
              ),
            ],
          ),
        );
      } else {
        _snack('Gagal buka installer: $pesan', OptikMemberTokens.danger);
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
    final m = MemberLayout.of(context);
    final info = _info;
    final adaUpdate = info?.hasUpdate ?? false;

    return MemberPremiumScaffold(
      title: 'Update aplikasi',
      subtitle: 'Versi $_localVersion',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : MemberLayout.constrain(
              context,
              ListView(
                padding: EdgeInsets.fromLTRB(
                  m.pagePadding,
                  12,
                  m.pagePadding,
                  28,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.white,
                      borderRadius:
                          BorderRadius.circular(OptikMemberTokens.radiusLg),
                      border: Border.all(color: OptikMemberTokens.line),
                      boxShadow: OptikMemberTokens.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Unduh otomatis',
                                style: TextStyle(
                                  color: OptikMemberTokens.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Download di belakang; pasang tetap perlu konfirmasi Anda',
                                style: TextStyle(
                                  color: OptikMemberTokens.inkMuted,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _isAutoUpdateOn ? 'ON' : 'OFF',
                          style: TextStyle(
                            color: _isAutoUpdateOn
                                ? OptikMemberTokens.success
                                : OptikMemberTokens.inkMuted,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CupertinoSwitch(
                          value: _isAutoUpdateOn,
                          activeColor: OptikMemberTokens.blue,
                          onChanged: (val) async {
                            await _service.setAutoUpdateEnabled(
                              val,
                              appFlavor: MemberSoftwareUpdatePage.flavor,
                            );
                            setState(() => _isAutoUpdateOn = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: m.sectionGap),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          OptikMemberTokens.blueDeep,
                          OptikMemberTokens.blueMid,
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(OptikMemberTokens.radiusLg),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          adaUpdate
                              ? Icons.system_update_rounded
                              : Icons.verified_rounded,
                          size: 56,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          adaUpdate
                              ? 'Update tersedia'
                              : 'Aplikasi sudah terbaru',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          adaUpdate
                              ? '${info!.localVersion}  →  ${info.serverVersion}'
                              : 'Versi $_localVersion',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (adaUpdate && !(info?.urlReachable ?? true)) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Link unduhan belum siap. App tetap aman dipakai.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.amber.shade200,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (adaUpdate &&
                            (info?.notes ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            info!.notes!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (adaUpdate) ...[
                          const SizedBox(height: 22),
                          if (_isDownloading)
                            Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: _downloadProgress > 0
                                        ? _downloadProgress
                                        : null,
                                    minHeight: 8,
                                    backgroundColor: Colors.white24,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Mengunduh ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          else if (_readyToInstall)
                            FilledButton.icon(
                              onPressed: _pasangUpdate,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: OptikMemberTokens.blueDeep,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(Icons.install_mobile_rounded),
                              label: const Text(
                                'Pasang sekarang',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            )
                          else
                            FilledButton.icon(
                              onPressed: (info?.urlReachable ?? false)
                                  ? _unduhUpdate
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: OptikMemberTokens.blueDeep,
                                disabledBackgroundColor: Colors.white38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text(
                                'Unduh update',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (_statusHint != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _statusHint!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _isDownloading ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Cek ulang'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Unduhan tidak mengganti app sampai Anda konfirmasi pasang. '
                    'Jika gagal, versi lama tetap jalan normal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: OptikMemberTokens.inkMuted.withOpacity(0.9),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
