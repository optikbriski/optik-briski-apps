import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';
import 'connectivity_monitor.dart';
import 'connectivity_reload.dart';

/// Banner atas layar saat offline / koneksi lambat — semua flavor APK.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    ConnectivityMonitor.instance.attach();
    ConnectivityMonitor.instance.addListener(_onStatus);
  }

  @override
  void dispose() {
    ConnectivityMonitor.instance.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    if (!mounted) return;
    setState(() {});

    if (ConnectivityMonitor.instance.consumeBackOnlineSignal()) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearMaterialBanners();
      messenger?.showSnackBar(
        SnackBar(
          content: Text('connectivity_back_online'.tr()),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Auto-sync data terdaftar (POS stok/RO, dashboard, karyawan, member).
      unawaited(ConnectivityReload.runAll());
    }
  }

  Future<void> _onReload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    final ok = await ConnectivityMonitor.instance.probeAndReload();
    if (!mounted) return;
    setState(() => _reloading = false);

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('connectivity_still_offline'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('connectivity_reload_ok'.tr()),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ConnectivityMonitor.instance.status;
    if (status == ConnectivityStatus.online ||
        status == ConnectivityStatus.checking) {
      return const SizedBox.shrink();
    }

    final skin = _skinForFlavor(currentFlavor);
    final offline = status == ConnectivityStatus.offline;

    return Material(
      color: offline ? skin.offlineBg : skin.slowBg,
      elevation: 3,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                offline ? Icons.wifi_off_rounded : Icons.network_check_rounded,
                color: skin.onBg,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      offline
                          ? 'connectivity_offline_title'.tr()
                          : 'connectivity_slow_title'.tr(),
                      style: TextStyle(
                        color: skin.onBg,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offline
                          ? 'connectivity_offline_body'.tr()
                          : 'connectivity_slow_body'.tr(),
                      style: TextStyle(
                        color: skin.onBg.withOpacity(0.92),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _reloading ? null : () => unawaited(_onReload()),
                    style: TextButton.styleFrom(
                      foregroundColor: skin.onBg,
                      backgroundColor: skin.onBg.withOpacity(0.2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: _reloading
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: skin.onBg,
                            ),
                          )
                        : Icon(Icons.refresh_rounded, size: 16, color: skin.onBg),
                    label: Text(
                      'connectivity_reload'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _reloading
                        ? null
                        : () => unawaited(
                              ConnectivityMonitor.instance.probeNow(),
                            ),
                    style: TextButton.styleFrom(
                      foregroundColor: skin.onBg.withOpacity(0.9),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'connectivity_retry'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectivitySkin {
  const _ConnectivitySkin({
    required this.offlineBg,
    required this.slowBg,
    required this.onBg,
  });

  final Color offlineBg;
  final Color slowBg;
  final Color onBg;
}

_ConnectivitySkin _skinForFlavor(AppFlavor flavor) {
  switch (flavor) {
    case AppFlavor.karyawan:
      return _ConnectivitySkin(
        offlineBg: OptikKaryawanTokens.danger,
        slowBg: OptikKaryawanTokens.warning,
        onBg: OptikKaryawanTokens.navyDeep,
      );
    case AppFlavor.member:
      return _ConnectivitySkin(
        offlineBg: OptikMemberTokens.danger,
        slowBg: OptikMemberTokens.warning,
        onBg: Colors.white,
      );
    case AppFlavor.admin:
    case AppFlavor.store:
      return _ConnectivitySkin(
        offlineBg: OptikAdminTokens.danger,
        slowBg: OptikAdminTokens.warning,
        onBg: OptikAdminTokens.snow,
      );
  }
}
