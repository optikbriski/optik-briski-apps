import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_notification_payload.dart';
import 'package:optik_b_riski/shared/member/member_realtime.dart';

void main() {
  group('MemberNotificationPayload', () {
    test('parses invoice deep link', () {
      final p = MemberNotificationPayload.parse('inv:INV-123');
      expect(p.invoice, 'INV-123');
      expect(p.onlineOrderId, isNull);
      expect(p.openOrdersList, isFalse);
    });

    test('parses online order deep link', () {
      final p = MemberNotificationPayload.parse(
        'online:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(p.onlineOrderId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(p.invoice, isNull);
    });

    test('empty prefixes fall back to orders list', () {
      expect(MemberNotificationPayload.parse('inv:').openOrdersList, isTrue);
      expect(MemberNotificationPayload.parse('online:').openOrdersList, isTrue);
      expect(MemberNotificationPayload.parse('').openOrdersList, isTrue);
      expect(MemberNotificationPayload.parse('noise').openOrdersList, isTrue);
    });

    test('legacy inv:UUID payload opens online order', () {
      const uuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      final p = MemberNotificationPayload.parse('inv:$uuid');
      expect(p.onlineOrderId, uuid);
      expect(p.invoice, isNull);
      expect(p.openOrdersList, isFalse);
    });

    test('build prefers real invoice over online id', () {
      expect(
        MemberNotificationPayload.build(
          invoice: 'A1',
          onlineOrderId: 'oid',
        ),
        'inv:A1',
      );
      expect(
        MemberNotificationPayload.build(onlineOrderId: 'oid'),
        'online:oid',
      );
      expect(MemberNotificationPayload.build(), isNull);
    });

    test('build treats UUID/ONLINE invoice placeholder as online', () {
      const uuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      expect(
        MemberNotificationPayload.build(
          invoice: uuid,
          onlineOrderId: uuid,
        ),
        'online:$uuid',
      );
      expect(
        MemberNotificationPayload.build(
          invoice: 'ONLINE',
          onlineOrderId: uuid,
        ),
        'online:$uuid',
      );
      expect(
        MemberNotificationPayload.build(invoice: uuid),
        'online:$uuid',
      );
    });

    test('resolve prefers invoice when real; else online', () {
      final withInv = MemberNotificationPayload.resolve(
        invoice: 'INV-9',
        onlineOrderId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(withInv.invoice, 'INV-9');

      final onlineOnly = MemberNotificationPayload.resolve(
        invoice: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        onlineOrderId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(onlineOnly.onlineOrderId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(onlineOnly.invoice, isNull);
    });
  });

  group('MemberRealtime.topicForPhone', () {
    test('normalizes 08… to 62… topic', () {
      expect(
        MemberRealtime.topicForPhone('081234567890'),
        'obr-member-6281234567890',
      );
    });

    test('keeps 62… topic stable', () {
      expect(
        MemberRealtime.topicForPhone('6281234567890'),
        'obr-member-6281234567890',
      );
    });
  });
}
