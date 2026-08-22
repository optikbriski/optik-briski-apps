import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optik_b_riski/shared/training/training_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recoverOnLaunch stays inactive without a recovery flag', () async {
    await TrainingMode.instance.recoverOnLaunch();
    expect(TrainingMode.instance.isActive, isFalse);
  });

  test('recoverOnLaunch clears a leftover prefs flag without Keychain', () async {
    SharedPreferences.setMockInitialValues({
      'training_mode_active': true,
      'training_mode_session_id': 'tr_orphan',
    });
    await TrainingMode.instance.recoverOnLaunch();
    expect(TrainingMode.instance.isActive, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('training_mode_active'), isNot(isTrue));
  });
}
