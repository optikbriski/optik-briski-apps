import 'apps/karyawan/karyawan_app.dart';
import 'shared/bootstrap.dart';
import 'shared/invoice/register_invoice_hub_opener.dart';
import 'shared/maps/google_maps_js.dart';

Future<void> main() async {
  // Karyawan POS/cabang: scan QR nota pelanggan → hub lifecycle (sama web admin).
  registerInvoiceHubOpener();
  await ensureGoogleMapsJs();
  await bootstrapApp(
    app: const KaryawanApp(),
    quietLocalizationLogs: true,
  );
}
