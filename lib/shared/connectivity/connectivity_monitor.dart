import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'connectivity_reload.dart';

/// Status jaringan aplikasi — dipakai banner global di semua flavor APK.
enum ConnectivityStatus {
  /// Belum dicek / sedang cek pertama.
  checking,

  /// Reachable + respons cepat.
  online,

  /// Tidak ada internet / server tidak terjangkau.
  offline,

  /// Terhubung tapi respons lambat (WiFi/data lemot).
  slow,
}

/// Pantau koneksi internet (HEAD Supabase) + lifecycle resume.
class ConnectivityMonitor extends ChangeNotifier with WidgetsBindingObserver {
  ConnectivityMonitor._();

  static final ConnectivityMonitor instance = ConnectivityMonitor._();

  static const Duration _probeInterval = Duration(seconds: 18);
  static const Duration _probeTimeout = Duration(seconds: 6);
  static const int _slowMs = 2800;

  ConnectivityStatus status = ConnectivityStatus.checking;
  bool _attached = false;
  bool _probing = false;
  Timer? _timer;
  ConnectivityStatus? _prevForSnack;

  bool get isDegraded =>
      status == ConnectivityStatus.offline || status == ConnectivityStatus.slow;

  void attach() {
    if (_attached || kIsWeb) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_probeInterval, (_) => unawaited(probeNow()));
    unawaited(probeNow());
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(probeNow());
    }
  }

  /// Cek ulang manual (tombol banner).
  Future<void> probeNow() async {
    if (_probing) return;
    _probing = true;
    final was = status;
    if (was == ConnectivityStatus.checking) {
      notifyListeners();
    }

    final next = await _probeOnce();
    _probing = false;

    if (status != next) {
      _prevForSnack = was;
      status = next;
      notifyListeners();
    } else if (was == ConnectivityStatus.checking) {
      notifyListeners();
    }
  }

  /// Cek jaringan lalu muat ulang data shell yang terdaftar.
  Future<bool> probeAndReload() async {
    await probeNow();
    if (status == ConnectivityStatus.offline) {
      return false;
    }
    await ConnectivityReload.runAll();
    return true;
  }

  /// True jika baru kembali online (untuk snackbar sekali).
  bool consumeBackOnlineSignal() {
    if (_prevForSnack != null &&
        _prevForSnack != ConnectivityStatus.online &&
        status == ConnectivityStatus.online) {
      _prevForSnack = null;
      return true;
    }
    return false;
  }

  Future<ConnectivityStatus> _probeOnce() async {
    final base = supabaseUrl.trim();
    if (base.isEmpty) {
      // Dev tanpa dart-define — jangan blokir UI.
      return ConnectivityStatus.online;
    }

    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/rest/v1/');
    final headers = <String, String>{
      if (supabasePublishableKey.isNotEmpty) 'apikey': supabasePublishableKey,
      if (supabasePublishableKey.isNotEmpty)
        'Authorization': 'Bearer $supabasePublishableKey',
    };

    final sw = Stopwatch()..start();
    try {
      await http.head(uri, headers: headers).timeout(_probeTimeout);
      sw.stop();
      if (sw.elapsedMilliseconds >= _slowMs) {
        return ConnectivityStatus.slow;
      }
      return ConnectivityStatus.online;
    } catch (_) {
      return ConnectivityStatus.offline;
    }
  }
}
