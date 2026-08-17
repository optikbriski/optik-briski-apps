import 'package:flutter/material.dart';

import 'owner_shell.dart';

/// Entry widget for franchise Owner UX inside Karyawan APK.
/// Prefer [OwnerShell] directly from login routing.
class OwnerHome extends StatelessWidget {
  const OwnerHome({super.key});

  @override
  Widget build(BuildContext context) => const OwnerShell();
}
