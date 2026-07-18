import 'apps/karyawan/karyawan_app.dart';
import 'shared/bootstrap.dart';

Future<void> main() async {
  await bootstrapApp(
    app: const KaryawanApp(),
    quietLocalizationLogs: true,
  );
}
