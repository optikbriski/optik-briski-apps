import 'package:flutter/material.dart';

import '../../../shared/app_update/app_software_update_page.dart';
import '../../../shared/app_update_service.dart';

/// Halaman update Member — mesin bersama, kulit putih–biru.
class MemberSoftwareUpdatePage extends StatelessWidget {
  const MemberSoftwareUpdatePage({
    super.key,
    this.autoStartDownload = false,
  });

  final bool autoStartDownload;

  static const flavor = AppUpdateFlavor.member;

  @override
  Widget build(BuildContext context) {
    return AppSoftwareUpdatePage.member(
      autoStartDownload: autoStartDownload,
    );
  }
}
