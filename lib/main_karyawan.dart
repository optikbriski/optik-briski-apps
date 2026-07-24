import 'apps/karyawan/karyawan_app.dart';
import 'shared/bootstrap.dart';
import 'shared/invoice/invoice_peek_page.dart';
import 'shared/invoice/invoice_qr_opener.dart';

Future<void> main() async {
  InvoiceQrOpener.open = openInvoicePeek;
  await bootstrapApp(
    app: const KaryawanApp(),
    quietLocalizationLogs: true,
  );
}
