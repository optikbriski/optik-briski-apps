import 'package:flutter/widgets.dart';

import 'apps/karyawan/karyawan_app.dart';
import 'apps/karyawan/register_karyawan_invoice_opener.dart';
import 'shared/bootstrap.dart';
import 'shared/karyawan/karyawan_push_service.dart';
import 'shared/maps/google_maps_js.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Scan QR LUNAS pelanggan → serah terima di HP (duty gate sesi).
  registerKaryawanInvoiceOpener();
  await ensureGoogleMapsJs();
  // Soft-init FCM: no-op jika google-services belum dipasang.
  await KaryawanPushService.ensureFirebase();
  await bootstrapApp(
    app: const KaryawanApp(),
    quietLocalizationLogs: true,
  );
}
