import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/attendance/attendance_dinas.dart';

void main() {
  test('todayKey pakai kalender Asia/Jakarta bukan zona perangkat', () {
    final utc = DateTime.utc(2026, 8, 26, 17, 30); // 00:30 WIB 27 Aug
    expect(AttendanceDinas.todayKey(utc), '2026-08-27');
    final still26 = DateTime.utc(2026, 8, 26, 16, 59); // 23:59 WIB 26 Aug
    expect(AttendanceDinas.todayKey(still26), '2026-08-26');
    expect(AttendanceDinas.todayKey(DateTime.utc(2026, 8, 27, 0, 0)), '2026-08-27');
  });

  test('nowWall adalah jam dinding UTC+7', () {
    final utc = DateTime.utc(2026, 8, 27, 17, 5, 9);
    final wall = AttendanceDinas.nowWall(utc);
    expect(wall.year, 2026);
    expect(wall.month, 8);
    expect(wall.day, 28);
    expect(wall.hour, 0);
    expect(wall.minute, 5);
    expect(wall.second, 9);
  });
}
