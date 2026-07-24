import 'apps/admin/admin_app.dart';
import 'shared/bootstrap.dart';
import 'shared/invoice/register_invoice_hub_opener.dart';

Future<void> main() async {
  registerInvoiceHubOpener();
  await bootstrapApp(app: const AdminApp());
}
