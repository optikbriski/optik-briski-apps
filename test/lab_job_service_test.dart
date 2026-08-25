import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/lab_job_service.dart';

void main() {
  test('jobIdFromNotifikasiIsi parses LAB_JOB uuid', () {
    expect(
      LabJobService.jobIdFromNotifikasiIsi(
        'Job baru LAB_JOB:945facc3-596c-4d1f-861f-a561d2e78091 siap',
      ),
      '945facc3-596c-4d1f-861f-a561d2e78091',
    );
    expect(LabJobService.jobIdFromNotifikasiIsi('tanpa id'), isNull);
  });

  test('status constants are stable', () {
    expect(LabJobService.statusOpen, 'OPEN');
    expect(LabJobService.statusClaimed, 'CLAIMED');
    expect(LabJobService.statusDone, 'DONE');
  });
}
