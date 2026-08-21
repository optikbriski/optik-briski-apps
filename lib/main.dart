import 'package:flutter/material.dart';

import 'apps/admin/admin_app.dart';
import 'apps/karyawan/karyawan_app.dart';
import 'apps/member/member_app.dart';
import 'apps/store/store_app.dart';
import 'shared/bootstrap.dart';
import 'shared/config.dart';

/// Dev launcher. Production builds should target:
/// - lib/main_admin.dart
/// - lib/main_karyawan.dart
/// - lib/main_member.dart
/// - lib/main_store.dart (etalase Rekasa, bukan kasir)
///
/// Owner shell is opened from Karyawan APK after login when
/// profiles.role == 'owner' (not a separate APP_FLAVOR).
Future<void> main() async {
  await bootstrapApp(app: const _FlavorRoot());
}

class _FlavorRoot extends StatelessWidget {
  const _FlavorRoot();

  @override
  Widget build(BuildContext context) {
    switch (currentFlavor) {
      case AppFlavor.karyawan:
        return const KaryawanApp();
      case AppFlavor.member:
        return const MemberApp();
      case AppFlavor.admin:
        return const AdminApp();
      case AppFlavor.store:
        return const StoreApp();
    }
  }
}
