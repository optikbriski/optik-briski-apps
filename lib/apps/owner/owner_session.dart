import 'package:flutter/foundation.dart';

/// In-memory Owner session after login + owner_my_profile RPC.
class OwnerSession extends ChangeNotifier {
  OwnerSession._();
  static final OwnerSession instance = OwnerSession._();

  Map<String, dynamic>? _profile;

  Map<String, dynamic>? get profile => _profile;
  bool get isLoggedIn => _profile != null;

  String get nama => (_profile?['nama'] ?? '').toString();
  String get email => (_profile?['email'] ?? '').toString();
  String get ownerType => (_profile?['owner_type'] ?? '').toString();
  bool get isUtama => ownerType == 'utama';

  List<String> get tokoIds {
    final raw = _profile?['toko_ids'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  void setProfile(Map<String, dynamic> profile) {
    _profile = Map<String, dynamic>.from(profile);
    notifyListeners();
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }
}
