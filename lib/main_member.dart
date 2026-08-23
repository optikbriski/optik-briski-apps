import 'apps/member/member_app.dart';
import 'shared/bootstrap.dart';
import 'shared/maps/google_maps_js.dart';

Future<void> main() async {
  await ensureGoogleMapsJs();
  await bootstrapApp(app: const MemberApp());
}
