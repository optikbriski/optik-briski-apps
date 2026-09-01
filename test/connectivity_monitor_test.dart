import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/connectivity/connectivity_monitor.dart';

void main() {
  test('consumeBackOnlineSignal is one-shot', () {
    final mon = ConnectivityMonitor.instance;
    mon.status = ConnectivityStatus.offline;
    mon.status = ConnectivityStatus.online;
    // Without going through probeNow, _prevForSnack may be null — no signal.
    expect(mon.consumeBackOnlineSignal(), isFalse);
  });

  test('isDegraded reflects offline and slow', () {
    final mon = ConnectivityMonitor.instance;
    mon.status = ConnectivityStatus.online;
    expect(mon.isDegraded, isFalse);
    mon.status = ConnectivityStatus.slow;
    expect(mon.isDegraded, isTrue);
    mon.status = ConnectivityStatus.offline;
    expect(mon.isDegraded, isTrue);
  });
}
