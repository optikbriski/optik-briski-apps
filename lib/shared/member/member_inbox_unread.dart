import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'member_repository.dart';
import 'member_session.dart';

/// Jumlah pesan Inbox yang belum dibaca (titik biru + badge ikon).
///
/// Terpisah dari key StatusWatch (`member_alert_seen_ids_v1`) yang hanya
/// untuk dedupe push notifikasi.
class MemberInboxUnread extends ChangeNotifier {
  MemberInboxUnread._();
  static final MemberInboxUnread instance = MemberInboxUnread._();

  static const _readKey = 'member_inbox_read_ids_v1';

  int _count = 0;
  int get count => _count;

  Set<String> _read = {};

  bool isUnread(String id) => id.isNotEmpty && !_read.contains(id);

  Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    _read = (prefs.getStringList(_readKey) ?? const []).toSet();

    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      if (_count != 0) {
        _count = 0;
        notifyListeners();
      } else {
        notifyListeners();
      }
      return;
    }

    final alerts = await MemberRepository().listOrderAlerts(phone: phone);
    var n = 0;
    for (final a in alerts) {
      final id = '${a['id'] ?? ''}';
      if (isUnread(id)) n++;
    }
    _count = n;
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    if (id.isEmpty || _read.contains(id)) return;
    _read = {..._read, id};
    final prefs = await SharedPreferences.getInstance();
    final trimmed =
        _read.toList().reversed.take(300).toList().reversed.toList();
    await prefs.setStringList(_readKey, trimmed);
    if (_count > 0) _count -= 1;
    notifyListeners();
  }

  /// Hitung ulang badge dari daftar id yang sedang ditampilkan.
  void syncFromAlertIds(Iterable<String> ids) {
    var n = 0;
    for (final id in ids) {
      if (isUnread(id)) n++;
    }
    if (n != _count) {
      _count = n;
      notifyListeners();
    }
  }

  /// Logout / ganti akun — kosongkan baca lokal.
  Future<void> clear() async {
    _read = {};
    _count = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_readKey);
    notifyListeners();
  }
}
