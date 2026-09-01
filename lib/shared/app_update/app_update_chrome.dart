import 'package:flutter/material.dart';

import '../app_update_service.dart';
import '../theme.dart';

/// Warna & jenis scaffold untuk halaman/dialog update per flavor.
class AppUpdateChrome {
  const AppUpdateChrome({
    required this.flavor,
    required this.kind,
    required this.accent,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.scaffoldBg,
    required this.switchActive,
    required this.onAccent,
  });

  final String flavor;
  final AppUpdateKind kind;
  final Color accent;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color scaffoldBg;
  final Color switchActive;
  final Color onAccent;

  static const karyawan = AppUpdateChrome(
    flavor: AppUpdateFlavor.karyawan,
    kind: AppUpdateKind.karyawan,
    accent: OptikKaryawanTokens.gold,
    surface: OptikKaryawanTokens.surface,
    ink: OptikKaryawanTokens.ink,
    muted: OptikKaryawanTokens.muted,
    success: OptikKaryawanTokens.success,
    warning: Colors.orange,
    danger: Colors.redAccent,
    scaffoldBg: OptikKaryawanTokens.scaffold,
    switchActive: OptikKaryawanTokens.gold,
    onAccent: OptikKaryawanTokens.navyDeep,
  );

  static const member = AppUpdateChrome(
    flavor: AppUpdateFlavor.member,
    kind: AppUpdateKind.member,
    accent: OptikMemberTokens.blueDeep,
    surface: OptikMemberTokens.white,
    ink: OptikMemberTokens.ink,
    muted: OptikMemberTokens.inkMuted,
    success: OptikMemberTokens.success,
    warning: OptikMemberTokens.warning,
    danger: OptikMemberTokens.danger,
    scaffoldBg: OptikMemberTokens.canvas,
    switchActive: OptikMemberTokens.blue,
    onAccent: Colors.white,
  );

  static AppUpdateChrome get admin => AppUpdateChrome(
        flavor: AppUpdateFlavor.admin,
        kind: AppUpdateKind.admin,
        accent: OptikAdminTokens.navy,
        surface: OptikAdminTokens.card,
        ink: OptikAdminTokens.navy,
        muted: OptikAdminTokens.slate,
        success: OptikAdminTokens.success,
        warning: OptikAdminTokens.warning,
        danger: OptikAdminTokens.danger,
        scaffoldBg: OptikAdminTokens.bg,
        switchActive: OptikAdminTokens.ice,
        onAccent: Colors.white,
      );

  static AppUpdateChrome of(String flavor) {
    switch (AppUpdateFlavor.normalize(flavor)) {
      case AppUpdateFlavor.admin:
        return admin;
      case AppUpdateFlavor.member:
        return member;
      default:
        return karyawan;
    }
  }
}

enum AppUpdateKind { karyawan, member, admin }
