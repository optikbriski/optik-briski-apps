import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_points_grade.dart';

void main() {
  group('MemberGradeThresholds.fromStatusPoints', () {
    test('edges and exact thresholds', () {
      expect(MemberGradeThresholds.fromStatusPoints(0), MemberGrade.basic);
      expect(MemberGradeThresholds.fromStatusPoints(249), MemberGrade.basic);
      expect(MemberGradeThresholds.fromStatusPoints(250), MemberGrade.silver);
      expect(MemberGradeThresholds.fromStatusPoints(499), MemberGrade.silver);
      expect(MemberGradeThresholds.fromStatusPoints(500), MemberGrade.gold);
      expect(MemberGradeThresholds.fromStatusPoints(999), MemberGrade.gold);
      expect(MemberGradeThresholds.fromStatusPoints(1000), MemberGrade.platinum);
      expect(MemberGradeThresholds.fromStatusPoints(1999), MemberGrade.platinum);
      expect(MemberGradeThresholds.fromStatusPoints(2000), MemberGrade.diamond);
      expect(MemberGradeThresholds.fromStatusPoints(99999), MemberGrade.diamond);
    });
  });

  group('MemberGradeThresholds progress helpers', () {
    test('pointsToNext at zero and at threshold', () {
      expect(MemberGradeThresholds.pointsToNext(0), 250);
      expect(MemberGradeThresholds.pointsToNext(250), 250);
      expect(MemberGradeThresholds.pointsToNext(500), 500);
      expect(MemberGradeThresholds.pointsToNext(1000), 1000);
      expect(MemberGradeThresholds.pointsToNext(2000), 0);
    });

    test('pointsToGrade never negative', () {
      expect(
        MemberGradeThresholds.pointsToGrade(MemberGrade.silver, 300),
        0,
      );
      expect(
        MemberGradeThresholds.pointsToGrade(MemberGrade.diamond, 1500),
        500,
      );
    });

    test('progress within band and at diamond', () {
      expect(MemberGradeThresholds.progress(0), 0);
      expect(MemberGradeThresholds.progress(125), closeTo(0.5, 0.001));
      expect(MemberGradeThresholds.progress(2000), 1);
      expect(MemberGradeThresholds.trackProgress(0), 0);
      expect(MemberGradeThresholds.trackProgress(1000), 0.5);
      expect(MemberGradeThresholds.trackProgress(2000), 1);
    });

    test('isUnlocked matches unlockAt', () {
      expect(MemberGradeThresholds.isUnlocked(MemberGrade.basic, 0), isTrue);
      expect(MemberGradeThresholds.isUnlocked(MemberGrade.silver, 249), isFalse);
      expect(MemberGradeThresholds.isUnlocked(MemberGrade.silver, 250), isTrue);
      expect(
        MemberGradeThresholds.isUnlocked(MemberGrade.diamond, 1999),
        isFalse,
      );
      expect(
        MemberGradeThresholds.isUnlocked(MemberGrade.diamond, 2000),
        isTrue,
      );
    });
  });

  group('MemberPointsSnapshot', () {
    test('grade follows statusPoints not rewardPoints', () {
      const snap = MemberPointsSnapshot(
        rewardPoints: 50,
        statusPoints: 1200,
      );
      expect(snap.grade, MemberGrade.platinum);
      expect(snap.palette.label, 'Platinum');
    });
  });

  group('format + ledger labels', () {
    test('formatMemberPoints uses id grouping', () {
      expect(formatMemberPoints(80000), '80.000');
      expect(formatMemberPoints(0), '0');
    });

    test('memberPointsLedgerTitle humanizes reasons', () {
      expect(
        memberPointsLedgerTitle('purchase_10pct', invoice: 'INV-1'),
        'Invoice INV-1',
      );
      expect(memberPointsLedgerTitle('voucher_redeem'), 'Tukar voucher');
      expect(
        memberPointsLedgerTitle('voucher_release_online'),
        'Pengembalian poin voucher',
      );
      expect(memberPointsLedgerTitle('custom_bonus'), 'custom bonus');
    });
  });
}
