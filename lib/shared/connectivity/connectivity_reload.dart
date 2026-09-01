import 'package:flutter/foundation.dart';

/// Handler muat ulang data saat jaringan pulih — didaftarkan tiap shell flavor.
class ConnectivityReload {
  ConnectivityReload._();

  static final Map<Object, Future<void> Function()> _handlers = {};

  static void bind(Object owner, Future<void> Function() handler) {
    _handlers[owner] = handler;
  }

  static void unbind(Object owner) {
    _handlers.remove(owner);
  }

  static Future<void> runAll() async {
    final jobs = _handlers.values.toList(growable: false);
    for (final job in jobs) {
      try {
        await job();
      } catch (e, st) {
        debugPrint('ConnectivityReload: $e\n$st');
      }
    }
  }
}
