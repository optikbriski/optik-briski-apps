import 'apps/admin/admin_app.dart';
import 'shared/bootstrap.dart';

Future<void> main() async {
  await bootstrapApp(app: const AdminApp());
}
