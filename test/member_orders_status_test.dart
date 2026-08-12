import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_orders_status.dart';

void main() {
  group('MemberOrdersStatus.isActiveSale', () {
    test('includes unpaid DP / in production / siap diambil', () {
      expect(
        MemberOrdersStatus.isActiveSale({
          'tracking_status': 'DIPROSES_DI_CABANG',
          'status_pembayaran': 'DP',
          'sisa_tagihan': 100000,
        }),
        isTrue,
      );
      expect(
        MemberOrdersStatus.isActiveSale({
          'tracking_status': 'SIAP_DIAMBIL',
          'status_pembayaran': 'LUNAS',
          'sisa_tagihan': 0,
        }),
        isTrue,
      );
    });

    test('excludes sudah diambil and cancelled', () {
      expect(
        MemberOrdersStatus.isActiveSale({
          'tracking_status': 'DIAMBIL',
          'diambil_at': '2026-08-01T10:00:00Z',
        }),
        isFalse,
      );
      expect(
        MemberOrdersStatus.isActiveSale({
          'tracking_status': 'BATAL_VOUCHER',
          'status_pembayaran': 'BATAL',
        }),
        isFalse,
      );
    });
  });

  group('MemberOrdersStatus.isActiveOnline', () {
    test('includes pending/paid/ready; excludes terminal', () {
      expect(
        MemberOrdersStatus.isActiveOnline({'status': 'pending_payment'}),
        isTrue,
      );
      expect(MemberOrdersStatus.isActiveOnline({'status': 'paid'}), isTrue);
      expect(MemberOrdersStatus.isActiveOnline({'status': 'ready'}), isTrue);
      expect(
        MemberOrdersStatus.isActiveOnline({'status': 'fulfilled'}),
        isFalse,
      );
      expect(
        MemberOrdersStatus.isActiveOnline({'status': 'cancelled'}),
        isFalse,
      );
      expect(
        MemberOrdersStatus.isActiveOnline({'status': 'expired'}),
        isFalse,
      );
    });
  });

  group('MemberOrdersStatus.merge', () {
    test('onlyActive excludes diambil + cancelled sales', () {
      final rows = MemberOrdersStatus.merge(
        sales: [
          {
            'id': 's1',
            'no_invoice': 'INV-1',
            'tracking_status': 'SIAP_DIAMBIL',
            'created_at': '2026-08-10T10:00:00Z',
          },
          {
            'id': 's2',
            'no_invoice': 'INV-2',
            'tracking_status': 'DIAMBIL',
            'diambil_at': '2026-08-09T10:00:00Z',
            'created_at': '2026-08-09T10:00:00Z',
          },
          {
            'id': 's3',
            'no_invoice': 'INV-3',
            'tracking_status': 'BATAL_VOUCHER',
            'status_pembayaran': 'BATAL',
            'created_at': '2026-08-08T10:00:00Z',
          },
        ],
        online: const [],
        onlyActive: true,
      );
      expect(rows.length, 1);
      expect(rows.single.sale?['id'], 's1');
    });

    test('dedupe hides online when linked sale is in active list', () {
      final rows = MemberOrdersStatus.merge(
        sales: [
          {
            'id': 's1',
            'online_order_id': 'o1',
            'tracking_status': 'DIPROSES',
            'created_at': '2026-08-10T10:00:00Z',
          },
        ],
        online: [
          {
            'id': 'o1',
            'sale_id': 's1',
            'status': 'paid',
            'created_at': '2026-08-10T09:00:00Z',
          },
        ],
        onlyActive: true,
      );
      expect(rows.length, 1);
      expect(rows.single.isOnline, isFalse);
      expect(rows.single.sale?['id'], 's1');
    });

    test('does not drop active online when linked sale is taken (filtered out)',
        () {
      final rows = MemberOrdersStatus.merge(
        sales: [
          {
            'id': 's1',
            'online_order_id': 'o1',
            'tracking_status': 'DIAMBIL',
            'diambil_at': '2026-08-10T12:00:00Z',
            'created_at': '2026-08-10T10:00:00Z',
          },
        ],
        online: [
          {
            'id': 'o1',
            'sale_id': 's1',
            'status': 'ready',
            'created_at': '2026-08-10T09:00:00Z',
          },
        ],
        onlyActive: true,
      );
      expect(rows.length, 1);
      expect(rows.single.isOnline, isTrue);
      expect(rows.single.online?['id'], 'o1');
    });

    test('keeps orphan active online when sale_id missing from sales list', () {
      final rows = MemberOrdersStatus.merge(
        sales: const [],
        online: [
          {
            'id': 'o9',
            'sale_id': 'missing-sale',
            'status': 'pending_payment',
            'created_at': '2026-08-11T08:00:00Z',
          },
        ],
        onlyActive: true,
      );
      expect(rows.length, 1);
      expect(rows.single.online?['id'], 'o9');
    });

    test('riwayat keeps terminal rows', () {
      final rows = MemberOrdersStatus.merge(
        sales: [
          {
            'id': 's2',
            'tracking_status': 'DIAMBIL',
            'diambil_at': '2026-08-09T10:00:00Z',
            'created_at': '2026-08-09T10:00:00Z',
          },
        ],
        online: [
          {
            'id': 'o2',
            'status': 'fulfilled',
            'created_at': '2026-08-08T10:00:00Z',
          },
        ],
        onlyActive: false,
      );
      expect(rows.length, 2);
    });

    test('riwayat is full history (active + terminal), newest first', () {
      final rows = MemberOrdersStatus.merge(
        sales: [
          {
            'id': 's-active',
            'tracking_status': 'SIAP_DIAMBIL',
            'created_at': '2026-08-11T10:00:00Z',
          },
          {
            'id': 's-taken',
            'tracking_status': 'DIAMBIL',
            'diambil_at': '2026-08-10T10:00:00Z',
            'created_at': '2026-08-10T10:00:00Z',
          },
          {
            'id': 's-batal',
            'tracking_status': 'BATAL',
            'status_pembayaran': 'BATAL',
            'created_at': '2026-08-09T10:00:00Z',
          },
        ],
        online: [
          {
            'id': 'o-fulfilled',
            'status': 'fulfilled',
            'created_at': '2026-08-08T10:00:00Z',
          },
          {
            'id': 'o-cancelled',
            'status': 'cancelled',
            'created_at': '2026-08-07T10:00:00Z',
          },
          {
            'id': 'o-expired',
            'status': 'expired',
            'created_at': '2026-08-06T10:00:00Z',
          },
          {
            'id': 'o-active',
            'status': 'paid',
            'created_at': '2026-08-12T08:00:00Z',
          },
        ],
        onlyActive: false,
      );
      expect(rows.length, 7);
      expect(rows.first.online?['id'] ?? rows.first.sale?['id'], 'o-active');
      expect(rows.last.online?['id'], 'o-expired');
      final ids = rows
          .map((r) => r.isOnline ? r.online!['id'] : r.sale!['id'])
          .toSet();
      expect(
        ids,
        containsAll([
          's-active',
          's-taken',
          's-batal',
          'o-fulfilled',
          'o-cancelled',
          'o-expired',
          'o-active',
        ]),
      );
    });

    test('riwayat dedupes linked sale+online to one sale card', () {
      final rows = MemberOrdersStatus.merge(
        sales: [
          {
            'id': 's1',
            'online_order_id': 'o1',
            'tracking_status': 'DIAMBIL',
            'diambil_at': '2026-08-10T12:00:00Z',
            'created_at': '2026-08-10T10:00:00Z',
          },
        ],
        online: [
          {
            'id': 'o1',
            'sale_id': 's1',
            'status': 'fulfilled',
            'created_at': '2026-08-10T09:00:00Z',
          },
        ],
        onlyActive: false,
      );
      expect(rows.length, 1);
      expect(rows.single.isOnline, isFalse);
      expect(rows.single.sale?['id'], 's1');
    });
  });

  group('MemberOrdersStatus.payBadge', () {
    test('DP when open; LUNAS when settled; null when cancelled', () {
      expect(
        MemberOrdersStatus.payBadge({
          'status_pembayaran': 'DP',
          'sisa_tagihan': 50000,
        }),
        'DP',
      );
      expect(
        MemberOrdersStatus.payBadge({
          'status_pembayaran': 'LUNAS',
          'sisa_tagihan': 0,
        }),
        'LUNAS',
      );
      expect(
        MemberOrdersStatus.payBadge({
          'tracking_status': 'BATAL_VOUCHER',
          'status_pembayaran': 'BATAL',
          'sisa_tagihan': 100000,
        }),
        isNull,
      );
    });
  });
}
