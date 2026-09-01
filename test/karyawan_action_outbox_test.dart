import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optik_b_riski/shared/karyawan/karyawan_action_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('outbox queues on network-looking errors', () async {
    final queued = await KaryawanActionOutbox.instance.enqueueIfNetworkError(
      error: Exception('SocketException: Failed host lookup'),
      kind: 'online_advance',
      payload: {'orderId': 'x', 'currentStatus': 'paid'},
    );
    expect(queued, isTrue);
    expect(await KaryawanActionOutbox.instance.pendingCount(), 1);
  });

  test('outbox does not queue business errors', () async {
    final queued = await KaryawanActionOutbox.instance.enqueueIfNetworkError(
      error: 'Order tidak ditemukan',
      kind: 'online_advance',
      payload: {'orderId': 'y', 'currentStatus': 'paid'},
    );
    expect(queued, isFalse);
    expect(await KaryawanActionOutbox.instance.pendingCount(), 0);
  });
}
