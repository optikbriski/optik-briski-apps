import 'apps/admin/admin_app.dart';
import 'shared/bootstrap.dart';
import 'shared/brand/rekasa_public_host_stub.dart'
    if (dart.library.html) 'shared/brand/rekasa_public_host_web.dart';
import 'shared/invoice/register_invoice_hub_opener.dart';
import 'shared/maps/google_maps_js.dart';

Future<void> main() async {
  redirectRekasaPublicHostIfNeeded();
  registerInvoiceHubOpener();
  await ensureGoogleMapsJs();
  await bootstrapApp(app: const AdminApp());
}
