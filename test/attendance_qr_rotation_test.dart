import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/attendance_config.dart';

void main() {
  group('AttendanceConfig QR rotation timing', () {
    test('qrSecondsUntilExpiry uses ceiling seconds', () {
      final exp = DateTime.now().add(const Duration(milliseconds: 4500));
      expect(AttendanceConfig.qrSecondsUntilExpiry(exp), 5);
      expect(
        AttendanceConfig.qrSecondsUntilExpiry(
          DateTime.now().add(const Duration(milliseconds: 500)),
        ),
        1,
      );
      expect(
        AttendanceConfig.qrSecondsUntilExpiry(
          DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        0,
      );
    });

    test('qrDelayUntilPrefetch fires before expiry', () {
      final exp = DateTime.now().add(const Duration(seconds: 5));
      final delay = AttendanceConfig.qrDelayUntilPrefetch(exp);
      expect(delay.inMilliseconds, greaterThan(3000));
      expect(delay.inMilliseconds, lessThan(3600));
    });
  });
}
