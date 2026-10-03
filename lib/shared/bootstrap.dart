import 'package:easy_localization/easy_localization.dart';
import 'package:easy_logger/easy_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'brand/brand_chrome.dart';
import 'brand/brand_service.dart';
import 'config.dart';
import 'admin_appearance.dart';
import 'tenant/tenant_modules.dart';
import 'tenant/tenant_service.dart';
import 'training/training_http_client.dart';

final supabase = Supabase.instance.client;

/// Chrome CanvasKit kadang melempar ini saat tombol back menutup permukaan
/// gambar, sebelum field internalnya siap. Aplikasi masih hidup; jangan
/// ganti seluruh layar dengan halaman error.
void _keepWebAliveOnCanvasContextLost() {
  if (!kIsWeb) return;
  bool ignored(Object error) =>
      error.toString().contains('_handledContextLostEvent');

  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (ignored(details.exception)) return;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  final previousZone = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    if (ignored(error)) return true;
    if (previousZone != null) return previousZone(error, stack);
    return false;
  };
}

/// Shared startup for Admin / Karyawan / Member entry points.
///
/// Injects [TrainingHttpClient] so Admin Training Mode (entered mid-session)
/// can intercept every Supabase REST/Storage/RPC call without re-init.
/// Karyawan does not enter Training Mode; the client is inert when inactive.
Future<void> bootstrapApp({
  required Widget app,
  bool quietLocalizationLogs = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  _keepWebAliveOnCanvasContextLost();
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
    httpClient: TrainingHttpClient(),
  );
  await TenantService.instance.loadLocal();
  if (isRekasaStorefront) {
    BrandService.bind(AppBrand.rekasaShell);
    TenantModules.instance.sealStorefront();
  } else if (isBrandedStoreApk) {
    await TenantService.instance.bindBrandedStoreApk();
    await BrandService.load();
    await TenantModules.instance.load();
  } else {
    await TenantService.instance.ensureResolved();
    await BrandService.load();
    await TenantModules.instance.load();
  }
  BrandChrome.attach();
  await AdminAppearance.instance.load();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('id'),
        Locale('en'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('id'),
      child: app,
    ),
  );
}
