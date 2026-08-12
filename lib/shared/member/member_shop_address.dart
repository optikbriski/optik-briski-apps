import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShopAddressKind { recent, home, work, favorite, custom }

/// Alamat Belanja Online: aktif + recent + saved (rumah/kantor/favorit).
///
/// Persistensi di-scope per pemilik sesi. Panggil [syncOwner] saat login/logout
/// agar ganti akun di perangkat yang sama tidak bocor alamat member lain.
class MemberShopAddress extends ChangeNotifier {
  MemberShopAddress._();
  static final MemberShopAddress instance = MemberShopAddress._();

  static const _legacyActiveKey = 'member_shop_address_active_v1';
  static const _legacyRecentKey = 'member_shop_address_recent_v1';
  static const _legacySavedKey = 'member_shop_address_saved_v1';

  bool _loaded = false;
  String _boundOwner = 'guest';

  MemberShopAddressEntry? active;
  List<MemberShopAddressEntry> recent = const [];
  List<MemberShopAddressEntry> saved = const [];

  bool get isConfirmed =>
      active != null && MemberShopAddressEntry.isValidForShipping(active!);

  String get shortLabel {
    final a = active;
    if (a == null) return 'Pilih alamat';
    return a.label.trim().isNotEmpty ? a.label.trim() : a.shortTitle;
  }

  String get fullAddress => (active?.displayName ?? '').trim();

  /// Alamat tampilan ringkas + detail unit/patokan (bila ada).
  String get displayWithDetail {
    final a = active;
    if (a == null) return '';
    final base = a.displayName.trim();
    final detail = a.detail.trim();
    if (base.isEmpty) return detail;
    if (detail.isEmpty) return base;
    return '$base · $detail';
  }

  double? get lat => active?.lat;
  double? get lng => active?.lng;

  String get boundOwner => _boundOwner;

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

  String _activeKey(String owner) => 'member_shop_address_active_v2_$owner';
  String _recentKey(String owner) => 'member_shop_address_recent_v2_$owner';
  String _savedKey(String owner) => 'member_shop_address_saved_v2_$owner';

  /// Ganti bucket pemilik (login/logout). [owner] kosong → `guest`.
  Future<void> syncOwner(String owner) async {
    final next = owner.trim().isEmpty ? 'guest' : owner.trim();
    await ensureLoaded(owner: next, force: true);
  }

  Future<void> ensureLoaded({String? owner, bool force = false}) async {
    final next = (owner ?? _boundOwner).trim().isEmpty
        ? 'guest'
        : (owner ?? _boundOwner).trim();
    if (_loaded && !force && _boundOwner == next) return;

    final prefs = await SharedPreferences.getInstance();
    final prevOwner = _boundOwner;

    // Legacy device-global hanya masuk ke akun login (bukan guest).
    if (next != 'guest') {
      await _migrateLegacyIfNeeded(prefs, next);
    }

    // Alamat dipilih saat guest → bawa ke akun login bila bucket masih kosong.
    if (next != 'guest' && prevOwner == 'guest' && _loaded) {
      await _copyBucketIfTargetEmpty(prefs, from: 'guest', to: next);
      await _wipeBucket(prefs, 'guest');
    }

    // Logout / balik guest: mulai bersih agar tidak nyisa alamat akun lain.
    if (next == 'guest' && prevOwner != 'guest' && _loaded) {
      await _wipeBucket(prefs, 'guest');
    }

    await _readBucket(prefs, next);
    _boundOwner = next;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _readBucket(SharedPreferences prefs, String owner) async {
    MemberShopAddressEntry? nextActive;
    final activeRaw = prefs.getString(_activeKey(owner));
    if (activeRaw != null && activeRaw.isNotEmpty) {
      try {
        final parsed = MemberShopAddressEntry.fromMap(
          Map<String, dynamic>.from(jsonDecode(activeRaw) as Map),
        );
        if (MemberShopAddressEntry.isValidForShipping(parsed)) {
          nextActive = parsed;
        }
      } catch (_) {}
    }
    active = nextActive;
    recent = _readList(prefs.getString(_recentKey(owner)));
    saved = _readList(prefs.getString(_savedKey(owner)));
  }

  Future<void> _migrateLegacyIfNeeded(
    SharedPreferences prefs,
    String owner,
  ) async {
    final already = prefs.containsKey(_activeKey(owner)) ||
        prefs.containsKey(_recentKey(owner)) ||
        prefs.containsKey(_savedKey(owner));
    if (already) return;

    final legA = prefs.getString(_legacyActiveKey);
    final legR = prefs.getString(_legacyRecentKey);
    final legS = prefs.getString(_legacySavedKey);
    if ((legA == null || legA.isEmpty) &&
        (legR == null || legR.isEmpty) &&
        (legS == null || legS.isEmpty)) {
      return;
    }

    if (legA != null && legA.isNotEmpty) {
      await prefs.setString(_activeKey(owner), legA);
    }
    if (legR != null && legR.isNotEmpty) {
      await prefs.setString(_recentKey(owner), legR);
    }
    if (legS != null && legS.isNotEmpty) {
      await prefs.setString(_savedKey(owner), legS);
    }
    await prefs.remove(_legacyActiveKey);
    await prefs.remove(_legacyRecentKey);
    await prefs.remove(_legacySavedKey);
  }

  Future<void> _wipeBucket(SharedPreferences prefs, String owner) async {
    await prefs.remove(_activeKey(owner));
    await prefs.remove(_recentKey(owner));
    await prefs.remove(_savedKey(owner));
  }

  Future<void> _copyBucketIfTargetEmpty(
    SharedPreferences prefs, {
    required String from,
    required String to,
  }) async {
    final targetHas = prefs.containsKey(_activeKey(to)) ||
        prefs.containsKey(_recentKey(to)) ||
        prefs.containsKey(_savedKey(to));
    if (targetHas) return;

    final a = prefs.getString(_activeKey(from));
    final r = prefs.getString(_recentKey(from));
    final s = prefs.getString(_savedKey(from));
    if ((a == null || a.isEmpty) &&
        (r == null || r.isEmpty) &&
        (s == null || s.isEmpty)) {
      return;
    }
    if (a != null && a.isNotEmpty) {
      await prefs.setString(_activeKey(to), a);
    }
    if (r != null && r.isNotEmpty) {
      await prefs.setString(_recentKey(to), r);
    }
    if (s != null && s.isNotEmpty) {
      await prefs.setString(_savedKey(to), s);
    }
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
          .where(MemberShopAddressEntry.isValidForShipping)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async {
    final owner = _boundOwner.isEmpty ? 'guest' : _boundOwner;
    final prefs = await SharedPreferences.getInstance();
    if (active != null) {
      await prefs.setString(_activeKey(owner), jsonEncode(active!.toMap()));
    } else {
      await prefs.remove(_activeKey(owner));
    }
    await prefs.setString(
      _recentKey(owner),
      jsonEncode(recent.take(12).map((e) => e.toMap()).toList()),
    );
    await prefs.setString(
      _savedKey(owner),
      jsonEncode(saved.take(30).map((e) => e.toMap()).toList()),
    );
  }

  /// Konfirmasi lokasi → jadi alamat aktif + masuk recent.
  Future<void> confirm(MemberShopAddressEntry entry) async {
    await ensureLoaded();
    if (!MemberShopAddressEntry.isValidForShipping(entry)) return;
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
    if (!MemberShopAddressEntry.isValidForShipping(entry)) return;
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

    final a = active;
    if (a != null && (_samePlace(a, entry) || a.id == entry.id)) {
      active = entry.copyWith(
        kind: entry.kind == ShopAddressKind.recent
            ? ShopAddressKind.custom
            : entry.kind,
      );
      recent = [
        active!,
        ...recent.where((e) => !_samePlace(e, active!)),
      ].take(12).toList();
    }

    await _persist();
    notifyListeners();
  }

  Future<void> removeSaved(String id) async {
    await ensureLoaded();
    final target = id.trim();
    if (target.isEmpty) return;
    saved = saved.where((e) => e.id != target).toList();
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

  /// Test-only: kosongkan state + izinkan [ensureLoaded] baca prefs lagi.
  @visibleForTesting
  Future<void> debugResetForTest() async {
    active = null;
    recent = const [];
    saved = const [];
    _loaded = false;
    _boundOwner = 'guest';
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('member_shop_address_'))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    notifyListeners();
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

  bool get hasCoords => lat.abs() > 0.00001 || lng.abs() > 0.00001;

  /// Valid untuk pengiriman: ada label alamat + koordinat non-nol.
  static bool isValidForShipping(MemberShopAddressEntry e) {
    return e.displayName.trim().isNotEmpty && e.hasCoords;
  }

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
