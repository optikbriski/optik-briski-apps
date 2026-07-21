import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../shared/app_update_service.dart';

class SoftwareUpdatePage extends StatefulWidget {
  const SoftwareUpdatePage({super.key, this.autoStartDownload = false});

  /// Mulai unduh otomatis (install tetap konfirmasi).
  final bool autoStartDownload;

  @override
  State<SoftwareUpdatePage> createState() => _SoftwareUpdatePageState();
}

class _SoftwareUpdatePageState extends State<SoftwareUpdatePage> {
  final _service = AppUpdateService();

  bool _isAutoUpdateOn = true;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _readyToInstall = false;
  String? _readyApkPath;
  double _downloadProgress = 0.0;
  String? _statusHint;

  AppUpdateInfo? _info;

  @override
  void initState() {
    super.initState();
    _inisialisasiData();
  }

  Future<void> _inisialisasiData() async {
    _isAutoUpdateOn = await _service.isAutoUpdateEnabled();
    try {
      _info = await _service.checkForUpdate(appFlavor: 'karyawan');
      final readyPath = await _service.readyApkPath();
      final readyVer = await _service.readyApkVersion();
      if (readyPath != null &&
          readyVer != null &&
          _info != null &&
          readyVer == _info!.serverVersion) {
        _readyToInstall = true;
        _readyApkPath = readyPath;
        _statusHint =
            'Update ${_info!.serverVersion} sudah diunduh. Konfirmasi untuk memasang.';
      }
    } catch (e) {
      debugPrint('cek versi: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (widget.autoStartDownload &&
        (_info?.hasUpdate ?? false) &&
        (_info?.urlReachable ?? false) &&
        !_readyToInstall &&
        !kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _unduhUpdate();
      });
    } else if (widget.autoStartDownload &&
        (_info?.hasUpdate ?? false) &&
        !(_info?.urlReachable ?? true)) {
      setState(() {
        _statusHint =
            'Link APK belum bisa diakses. App lama tetap aman. Periksa URL di versi_app.';
      });
    }
  }

  Future<void> _unduhUpdate() async {
    final info = _info;
    if (info == null || !info.hasUpdate || _isDownloading) return;

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Update APK hanya di HP Android (bukan browser).'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusHint = 'Mengunduh… App yang terpasang tidak dihapus.';
      _readyToInstall = false;
    });

    try {
      final result = await _service.downloadInBackground(
        appFlavor: 'karyawan',
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
          final st = result.storage;
          setState(() {
            _statusHint = result.message;
          });
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              title: const Text('Penyimpanan kurang'),
              content: Text(
                'Kosongkan storage internal HP sampai tersedia sekitar '
                '${st?.requiredLabel ?? 'beberapa puluh MB'} '
                '(sekarang ${st?.freeLabel ?? '-'}).\n\n'
                'Setelah ada ruang cukup, unduhan bisa dilanjutkan.',
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
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        case BackgroundDownloadStatus.failed:
        case BackgroundDownloadStatus.skipped:
        case BackgroundDownloadStatus.downloading:
          setState(() => _statusHint = result.message);
          if ((result.message ?? '').isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(result.message!),
              backgroundColor: Colors.orange,
            ));
          }
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _pasangUpdate() async {
    final info = _info;
    final path = _readyApkPath;
    if (info == null || path == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('Pasang update?'),
        content: Text(
          'Versi ${info.serverVersion} akan dipasang.\n'
          'Konfirmasi lagi di layar sistem Android setelah ini.\n\n'
          'App lama tetap aman jika Anda batalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
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
      );
      if (!mounted) return;
      setState(() {
        _statusHint =
            'Installer terbuka. Selesaikan di layar sistem.\n'
            'Jika dibatalkan, app lama tetap bisa dipakai.';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Konfirmasi instalasi di layar sistem Android.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      final pesan = e.toString().replaceAll('Exception: ', '');
      setState(() => _statusHint = pesan);

      if (pesan.contains('REQUEST_INSTALL_PACKAGES')) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text('Izin instalasi diperlukan'),
            content: const Text(
              'Buka Pengaturan → Akses khusus → Instal aplikasi tidak dikenal → aktifkan untuk Optik B. Riski, lalu coba lagi.\n\nApp yang terpasang tidak rusak.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Mengerti'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal buka installer: $pesan'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final adaUpdate = info?.hasUpdate ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: Text("update_title".tr(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF121A2B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : Column(
              children: [
                Container(
                  color: const Color(0xFF121A2B),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("update_auto".tr(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15)),
                            const Text(
                              'Auto-unduh di background; pasang tetap perlu konfirmasi',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                          _isAutoUpdateOn
                              ? "update_on".tr()
                              : "update_off".tr(),
                          style: TextStyle(
                              color: _isAutoUpdateOn
                                  ? Colors.greenAccent
                                  : Colors.grey,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      CupertinoSwitch(
                        value: _isAutoUpdateOn,
                        activeColor: Colors.blueAccent,
                        onChanged: (val) async {
                          await _service.setAutoUpdateEnabled(val);
                          setState(() => _isAutoUpdateOn = val);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!adaUpdate) ...[
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 64, color: Colors.greenAccent),
                            const SizedBox(height: 20),
                            Text("update_up_to_date".tr(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text(
                                "${"update_version".tr()} ${info?.localVersion ?? '-'}",
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 14)),
                          ] else ...[
                            const Icon(Icons.system_update_rounded,
                                size: 64, color: Colors.blueAccent),
                            const SizedBox(height: 20),
                            Text("update_available".tr(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text(
                              '${info!.localVersion} → ${info.serverVersion}',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 14),
                            ),
                            if (!info.urlReachable) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'Link unduhan belum siap. App yang terpasang tetap aman dipakai.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.orangeAccent, height: 1.35),
                              ),
                            ],
                            if ((info.notes ?? '').isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                info.notes!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white70, height: 1.4),
                              ),
                            ],
                            const SizedBox(height: 28),
                            if (_isDownloading)
                              Column(
                                children: [
                                  LinearProgressIndicator(
                                    value: _downloadProgress > 0
                                        ? _downloadProgress
                                        : null,
                                    backgroundColor: Colors.grey.shade800,
                                    color: Colors.blueAccent,
                                    minHeight: 6,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${"update_downloading".tr()} ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        color: Colors.grey.shade400),
                                  ),
                                ],
                              )
                            else if (_readyToInstall)
                              FilledButton.icon(
                                onPressed: _pasangUpdate,
                                icon: const Icon(Icons.install_mobile_rounded),
                                label: const Text('Pasang sekarang'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 28, vertical: 14),
                                ),
                              )
                            else
                              FilledButton.icon(
                                onPressed: info.urlReachable
                                    ? _unduhUpdate
                                    : null,
                                icon: const Icon(Icons.download_rounded),
                                label: Text("update_btn_download".tr()),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 28, vertical: 14),
                                ),
                              ),
                          ],
                          if (_statusHint != null) ...[
                            const SizedBox(height: 20),
                            Text(
                              _statusHint!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                  height: 1.4),
                            ),
                          ],
                          const SizedBox(height: 28),
                          TextButton.icon(
                            onPressed: _isDownloading
                                ? null
                                : () async {
                                    setState(() => _isLoading = true);
                                    await _inisialisasiData();
                                  },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Cek ulang'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
