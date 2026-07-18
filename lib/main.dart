import 'package:flutter/material.dart';

import 'apps/admin/admin_app.dart';
import 'apps/karyawan/karyawan_app.dart';
import 'apps/member/member_app.dart';
import 'shared/bootstrap.dart';
import 'shared/config.dart';

/// Dev launcher. Production builds should target:
/// - lib/main_admin.dart
/// - lib/main_karyawan.dart
/// - lib/main_member.dart
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
    }
  }
}
