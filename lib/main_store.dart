import 'apps/store/store_app.dart';
import 'shared/bootstrap.dart';

/// APK Rekasa: katalog + jual beli + kontrak. Bukan kasir toko.
Future<void> main() async {
  await bootstrapApp(app: const StoreApp());
}
