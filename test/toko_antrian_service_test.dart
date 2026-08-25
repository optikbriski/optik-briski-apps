import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/toko_antrian_service.dart';

void main() {
  test('TokoAntrianItem kindKey is stable for filters', () {
    expect(
      const TokoAntrianItem(
        kind: TokoAntrianKind.pickupPos,
        id: '1',
        title: 'INV',
        subtitle: 'A',
      ).kindKey,
      'pickup_pos',
    );
    expect(
      const TokoAntrianItem(
        kind: TokoAntrianKind.pickupOnline,
        id: '2',
        title: 'B',
        subtitle: 'online',
      ).kindKey,
      'pickup_online',
    );
    expect(
      const TokoAntrianItem(
        kind: TokoAntrianKind.booking,
        id: '3',
        title: 'C',
        subtitle: 'booked',
      ).kindKey,
      'booking',
    );
    expect(
      const TokoAntrianItem(
        kind: TokoAntrianKind.klaim,
        id: '4',
        title: 'D',
        subtitle: 'klaim',
      ).kindKey,
      'klaim',
    );
  });

  test('Jakarta day bounds cover local calendar day in UTC', () {
    final (start, end) = TokoAntrianService.jakartaDayBoundsUtc();
    expect(end.difference(start), const Duration(days: 1));
    expect(start.isUtc, isTrue);
    expect(end.isUtc, isTrue);
    // Batas hari Jakarta = 17:00 UTC hari sebelumnya → 17:00 UTC hari ini
    expect(start.hour, 17);
    expect(end.hour, 17);
  });

  test('TokoAntrianLoadResult surfaces partial failures', () {
    const ok = TokoAntrianLoadResult(
      items: [
        TokoAntrianItem(
          kind: TokoAntrianKind.booking,
          id: 'b1',
          title: 'x',
          subtitle: 'y',
        ),
      ],
      errors: ['pickup_pos: RLS'],
    );
    expect(ok.hasErrors, isTrue);
    expect(ok.isEmpty, isFalse);
    expect(ok.items.single.kindKey, 'booking');

    const emptyFail = TokoAntrianLoadResult(
      items: [],
      errors: ['all failed'],
    );
    expect(emptyFail.hasErrors, isTrue);
    expect(emptyFail.isEmpty, isTrue);
  });

  test('online status advance mapping', () {
    expect(TokoAntrianService.nextOnlinePickupStatus('paid'), 'packing');
    expect(TokoAntrianService.nextOnlinePickupStatus('PACKING'), 'ready');
    expect(TokoAntrianService.nextOnlinePickupStatus('ready'), 'fulfilled');
    expect(TokoAntrianService.nextOnlinePickupStatus('cancelled'), isNull);
    expect(TokoAntrianService.nextOnlinePickupStatus('fulfilled'), isNull);
  });
}
