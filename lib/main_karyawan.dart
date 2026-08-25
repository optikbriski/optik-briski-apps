import 'apps/karyawan/karyawan_app.dart';
import 'apps/karyawan/register_karyawan_invoice_opener.dart';
import 'shared/bootstrap.dart';
import 'shared/maps/google_maps_js.dart';

Future<void> main() async {
  // Scan QR LUNAS pelanggan → serah terima di HP (duty gate sesi).
  registerKaryawanInvoiceOpener();
  await ensureGoogleMapsJs();
  await bootstrapApp(
    app: const KaryawanApp(),
    quietLocalizationLogs: true,
  );
}
