import 'package:flutter/material.dart';

import 'connectivity_banner.dart';

/// Bungkus isi [MaterialApp.builder] — banner jaringan + konten.
Widget connectivityAppShell({required Widget? child}) {
  return Column(
    children: [
      const ConnectivityBanner(),
      Expanded(child: child ?? const SizedBox.shrink()),
    ],
  );
}
