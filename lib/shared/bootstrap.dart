import 'package:easy_localization/easy_localization.dart';
import 'package:easy_logger/easy_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

final supabase = Supabase.instance.client;

/// Shared startup for Admin / Karyawan / Member entry points.
Future<void> bootstrapApp({
  required Widget app,
  bool quietLocalizationLogs = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  if (quietLocalizationLogs) {
    EasyLocalization.logger.enableLevels = [
      LevelMessages.warning,
      LevelMessages.error,
    ];
  }

  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    debugPrint('============================================================');
    debugPrint(
        '⚠️ EROR BINDING TOKEN: Supabase URL & Publishable Key belum disuntikkan!');
    debugPrint('Silakan jalankan dengan perintah berikut:');
    debugPrint(
        'flutter run -t lib/main_admin.dart --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...');
    debugPrint('============================================================');
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('id'),
        Locale('en'),
        Locale('ms'),
        Locale('zh'),
        Locale('ja'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('id'),
      child: app,
    ),
  );
}
