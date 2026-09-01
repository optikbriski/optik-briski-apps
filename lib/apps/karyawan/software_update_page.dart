import 'package:flutter/material.dart';

import '../../shared/app_update/app_software_update_page.dart';

/// Halaman update Karyawan — mesin bersama, kulit Charming Seaside.
class SoftwareUpdatePage extends StatelessWidget {
  const SoftwareUpdatePage({super.key, this.autoStartDownload = false});

  final bool autoStartDownload;

  @override
  Widget build(BuildContext context) {
    return AppSoftwareUpdatePage.karyawan(
      autoStartDownload: autoStartDownload,
    );
  }
}
