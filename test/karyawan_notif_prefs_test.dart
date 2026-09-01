import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/karyawan_notif_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('wantSop respects toggle when off duty', () async {
    SharedPreferences.setMockInitialValues({KaryawanNotifPrefs.keySop: false});
    expect(await KaryawanNotifPrefs.wantSop(onDuty: false), isFalse);
    expect(await KaryawanNotifPrefs.wantSop(onDuty: true), isTrue);
  });

  test('wantShift auto-on while on duty', () async {
    SharedPreferences.setMockInitialValues({KaryawanNotifPrefs.keyShift: false});
    expect(await KaryawanNotifPrefs.wantShift(onDuty: false), isFalse);
    expect(await KaryawanNotifPrefs.wantShift(onDuty: true), isTrue);
  });

  test('defaults on when prefs missing', () async {
    expect(await KaryawanNotifPrefs.wantSop(onDuty: false), isTrue);
    expect(await KaryawanNotifPrefs.wantShift(onDuty: false), isTrue);
  });
}
