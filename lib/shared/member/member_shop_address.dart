import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShopAddressKind { recent, home, work, favorite, custom }

/// Alamat Belanja Online: aktif + recent + saved (rumah/kantor/favorit).
class MemberShopAddress extends ChangeNotifier {
  MemberShopAddress._();
  static final MemberShopAddress instance = MemberShopAddress._();

  static const _activeKey = 'member_shop_address_active_v1';
  static const _recentKey = 'member_shop_address_recent_v1';
  static const _savedKey = 'member_shop_address_saved_v1';

  bool _loaded = false;

  MemberShopAddressEntry? active;
  List<MemberShopAddressEntry> recent = const [];
  List<MemberShopAddressEntry> saved = const [];

  bool get isConfirmed => active != null && active!.hasCoords;

  String get shortLabel {
    final a = active;
    if (a == null) return 'Pilih alamat';
    return a.label.trim().isNotEmpty ? a.label.trim() : a.shortTitle;
  }

  String get fullAddress => (active?.displayName ?? '').trim();

  double? get lat => active?.lat;
  double? get lng => active?.lng;

  MemberShopAddressEntry? get home =>
      saved.cast<MemberShopAddressEntry?>().firstWhere(
            (e) => e?.kind == ShopAddressKind.home,
            orElse: () => null,
          );

  MemberShopAddressEntry? get work =>
      saved.cast<MemberShopAddressEntry?>().firstWhere(
            (e) => e?.kind == ShopAddressKind.work,
            orElse: () => null,
          );

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    final activeRaw = prefs.getString(_activeKey);
    if (activeRaw != null && activeRaw.isNotEmpty) {
      try {
        active = MemberShopAddressEntry.fromMap(
          Map<String, dynamic>.from(jsonDecode(activeRaw) as Map),
        );
      } catch (_) {}
    }

    recent = _readList(prefs.getString(_recentKey));
    saved = _readList(prefs.getString(_savedKey));

    _loaded = true;
    notifyListeners();
  }

  List<MemberShopAddressEntry> _readList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => MemberShopAddressEntry.fromMap(
                Map<String, dynamic>.from(e),
              ))
          .where((e) => e.displayName.isNotEmpty && e.hasCoords)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (active != null) {
      await prefs.setString(_activeKey, jsonEncode(active!.toMap()));
    } else {
      await prefs.remove(_activeKey);
    }
    await prefs.setString(
      _recentKey,
      jsonEncode(recent.take(12).map((e) => e.toMap()).toList()),
    );
    await prefs.setString(
      _savedKey,
      jsonEncode(saved.take(30).map((e) => e.toMap()).toList()),
    );
  }

  /// Konfirmasi lokasi → jadi alamat aktif + masuk recent.
  Future<void> confirm(MemberShopAddressEntry entry) async {
    await ensureLoaded();
    active = entry.copyWith(
      kind: entry.kind == ShopAddressKind.recent
          ? ShopAddressKind.custom
          : entry.kind,
      savedAt: DateTime.now(),
    );

    recent = [
      active!,
      ...recent.where((e) => !_samePlace(e, active!)),
    ].take(12).toList();

    await _persist();
    notifyListeners();
  }

  Future<void> savePlace(MemberShopAddressEntry entry) async {
    await ensureLoaded();
    // Rumah / kantor: hanya satu slot.
    if (entry.kind == ShopAddressKind.home ||
        entry.kind == ShopAddressKind.work) {
      saved = [
        entry,
        ...saved.where((e) => e.kind != entry.kind),
      ];
    } else {
      saved = [
        entry.copyWith(kind: ShopAddressKind.favorite),
        ...saved.where((e) => !_samePlace(e, entry)),
      ].take(30).toList();
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeSaved(String id) async {
    await ensureLoaded();
    saved = saved.where((e) => e.id != id).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> clearActive() async {
    await ensureLoaded();
    active = null;
    await _persist();
    notifyListeners();
  }

  static bool _samePlace(MemberShopAddressEntry a, MemberShopAddressEntry b) {
    if (a.id.isNotEmpty && a.id == b.id) return true;
    return (a.lat - b.lat).abs() < 0.00008 && (a.lng - b.lng).abs() < 0.00008;
  }

  static String shortFromDisplay(String displayName) {
    final d = displayName.trim();
    if (d.isEmpty) return 'Alamat';
    return d.split(',').first.trim();
  }
}

class MemberShopAddressEntry {
  const MemberShopAddressEntry({
    required this.id,
    required this.label,
    required this.displayName,
    required this.lat,
    required this.lng,
    required this.kind,
    required this.savedAt,
    this.note = '',
    this.detail = '',
  });

  final String id;
  final String label;
  final String displayName;
  final double lat;
  final double lng;
  final ShopAddressKind kind;
  final DateTime savedAt;
  final String note;
  final String detail;

  bool get hasCoords =>
      lat.abs() > 0.00001 || lng.abs() > 0.00001;

  String get shortTitle {
    final l = label.trim();
    if (l.isNotEmpty) return l;
    return MemberShopAddress.shortFromDisplay(displayName);
  }

  MemberShopAddressEntry copyWith({
    String? id,
    String? label,
    String? displayName,
    double? lat,
    double? lng,
    ShopAddressKind? kind,
    DateTime? savedAt,
    String? note,
    String? detail,
  }) {
    return MemberShopAddressEntry(
      id: id ?? this.id,
      label: label ?? this.label,
      displayName: displayName ?? this.displayName,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      kind: kind ?? this.kind,
      savedAt: savedAt ?? this.savedAt,
      note: note ?? this.note,
      detail: detail ?? this.detail,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'displayName': displayName,
        'lat': lat,
        'lng': lng,
        'kind': kind.name,
        'savedAt': savedAt.toIso8601String(),
        'note': note,
        'detail': detail,
      };

  factory MemberShopAddressEntry.fromMap(Map<String, dynamic> m) {
    final kindName = (m['kind'] ?? 'custom').toString();
    final kind = ShopAddressKind.values.firstWhere(
      (e) => e.name == kindName,
      orElse: () => ShopAddressKind.custom,
    );
    final display = (m['displayName'] ?? '').toString();
    return MemberShopAddressEntry(
      id: (m['id'] ?? '').toString().isNotEmpty
          ? (m['id'] ?? '').toString()
          : 'a_${(m['lat'] ?? 0)}_${(m['lng'] ?? 0)}',
      label: (m['label'] ?? MemberShopAddress.shortFromDisplay(display))
          .toString(),
      displayName: display,
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      kind: kind,
      savedAt: DateTime.tryParse((m['savedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      note: (m['note'] ?? '').toString(),
      detail: (m['detail'] ?? '').toString(),
    );
  }

  factory MemberShopAddressEntry.fromCoords({
    required String displayName,
    required double lat,
    required double lng,
    String? label,
    ShopAddressKind kind = ShopAddressKind.custom,
    String note = '',
    String detail = '',
  }) {
    final short = label ?? MemberShopAddress.shortFromDisplay(displayName);
    return MemberShopAddressEntry(
      id: 'a_${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}_'
          '${DateTime.now().millisecondsSinceEpoch}',
      label: short,
      displayName: displayName.trim(),
      lat: lat,
      lng: lng,
      kind: kind,
      savedAt: DateTime.now(),
      note: note,
      detail: detail,
    );
  }
}
