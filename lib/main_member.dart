import 'apps/member/member_app.dart';
import 'shared/bootstrap.dart';

Future<void> main() async {
  await bootstrapApp(app: const MemberApp());
}
