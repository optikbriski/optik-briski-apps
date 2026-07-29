import 'apps/karyawan/karyawan_app.dart';
import 'shared/bootstrap.dart';
import 'shared/invoice/register_invoice_hub_opener.dart';

Future<void> main() async {
  // Karyawan POS/cabang: scan QR nota pelanggan → hub lifecycle (sama web admin).
  registerInvoiceHubOpener();
  await bootstrapApp(
    app: const KaryawanApp(),
    quietLocalizationLogs: true,
  );
}
