import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_update_service.dart';
import '../attendance/attendance_admin_scope.dart';
import '../attendance/attendance_verification_service.dart';
import '../karyawan/jadwal_pengajuan_service.dart';
import '../logistics/receive_queue_service.dart';
import '../logistics/receive_verification_rules.dart';
import '../payroll/payroll_service.dart';
import '../training/training_mode.dart';
import 'admin_nav_badge_logic.dart';

/// Badge sidebar Admin: realtime per entitas + bubble ke grup.
///
/// - Buka menu/sub-nav **tidak** menghapus badge.
/// - Buka item spesifik (akun, pengaduan, chat, …) → hanya entitas itu di-ack.
/// - Grup/sub badge = jumlah entitas live yang belum dibaca/dikerjakan.
class AdminNavBadgeService extends ChangeNotifier {
  AdminNavBadgeService._();
  static final AdminNavBadgeService instance = AdminNavBadgeService._();

  static const apkEntityId = 'latest';

  static const _prefSeenKey = 'admin_nav_seen_v2';
  static const _prefPinnedKey = 'admin_nav_pinned_v2';
  static const _prefChatBaselinedKey = 'admin_nav_chat_baslined_v2';

  SupabaseClient get _db => Supabase.instance.client;
  RealtimeChannel? _rt;
  Timer? _debounce;
  Map<String, dynamic>? _profile;
  Map<String, Set<String>> _liveEntities = const {};
  Map<String, Set<String>> _seenEntities = {};
  Map<String, Set<String>> _pinnedUnread = {};
  bool _busy = false;

  /// Angka badge per scope nav (hanya > 0).
  Map<String, int> get counts {
    final out = <String, int>{};
    for (final scope in {
      ..._liveEntities.keys,
      ..._seenEntities.keys,
      ..._pinnedUnread.keys,
    }) {
      final n = displayCount(scope);
      if (n > 0) out[scope] = n;
    }
    return out;
  }

  /// Entitas live yang belum dibaca di scope (untuk badge per baris).
  Set<String> unreadEntityIds(String scope) {
    return AdminNavBadgeLogic.unreadEntityIds(
      live: _liveEntities[scope],
      seen: _seenEntities[scope] ?? const {},
      pinned: _pinnedUnread[scope] ?? const {},
    );
  }

  bool isEntityUnread(String scope, String entityId) {
    final id = entityId.trim();
    if (id.isEmpty) return false;
    final live = _liveEntities[scope];
    if (live == null || !live.contains(id)) return false;
    final pinned = _pinnedUnread[scope];
    if (pinned?.contains(id) == true) return true;
    return !(_seenEntities[scope]?.contains(id) ?? false);
  }

  int displayCount(String scope) {
    return AdminNavBadgeLogic.displayCount(
      live: _liveEntities[scope],
      seen: _seenEntities[scope] ?? const {},
      pinned: _pinnedUnread[scope] ?? const {},
    );
  }

  int countFor(String scope) => displayCount(scope);

  /// Jumlah entitas unread dari daftar id (untuk badge tab/filter).
  int countUnreadIn(String scope, Iterable<String> entityIds) {
    var n = 0;
    for (final raw in entityIds) {
      if (isEntityUnread(scope, raw)) n++;
    }
    return n;
  }

  int groupCount(Iterable<String> scopes) {
    var sum = 0;
    for (final scope in scopes) {
      sum += displayCount(scope);
    }
    return sum;
  }

  Future<void> bindProfile(Map<String, dynamic> profile) async {
    _profile = Map<String, dynamic>.from(profile);
    await _loadPersisted();
  }

  Future<void> start() async {
    await _loadPersisted();
    _bindRealtime();
    unawaited(_refreshLive());
  }

  void stop() {
    _debounce?.cancel();
    final ch = _rt;
    _rt = null;
    if (ch != null) unawaited(_db.removeChannel(ch));
  }

  Future<void> refresh() => _refreshLive();

  /// Buka item spesifik → hanya entitas ini yang hilang dari badge.
  Future<void> markEntitySeen(String scope, String entityId) async {
    final s = scope.trim();
    final id = entityId.trim();
    if (s.isEmpty || id.isEmpty) return;
    _seenEntities[s] = {...?_seenEntities[s], id};
    _pinnedUnread[s]?.remove(id);
    if (_pinnedUnread[s]?.isEmpty ?? false) _pinnedUnread.remove(s);
    await _savePersisted();
    notifyListeners();
  }

  /// Long-press baris → tandai belum dibaca (entitas spesifik).
  Future<void> markEntityUnread(String scope, String entityId) async {
    final s = scope.trim();
    final id = entityId.trim();
    if (s.isEmpty || id.isEmpty) return;
    _seenEntities[s]?.remove(id);
    _pinnedUnread[s] = {...?_pinnedUnread[s], id};
    await _savePersisted();
    notifyListeners();
  }

  /// Long-press menu sidebar → kembalikan badge semua entitas pending di scope.
  Future<void> markScopeUnread(String scope) async {
    final s = scope.trim();
    if (s.isEmpty) return;
    final live = _liveEntities[s] ?? const {};
    if (live.isEmpty) {
      _pinnedUnread[s] = {AdminNavBadgeLogic.reminderToken};
    } else {
      final seen = _seenEntities[s] ?? {};
      _seenEntities[s] = seen.difference(live);
      _pinnedUnread[s] = {
        ...?_pinnedUnread[s],
        ...live,
      }..remove(AdminNavBadgeLogic.reminderToken);
    }
    await _savePersisted();
    notifyListeners();
  }

  @Deprecated('Use markEntitySeen')
  Future<void> markRead(String itemId) async {}

  @Deprecated('Use markScopeUnread')
  Future<void> markUnread(String itemId) async =>
      markScopeUnread(itemId);

  /// Reset state untuk unit test.
  @visibleForTesting
  void debugReset({
    Map<String, Set<String>>? live,
    Map<String, Set<String>>? seen,
    Map<String, Set<String>>? pinned,
  }) {
    _liveEntities = live ?? const {};
    _seenEntities = seen ?? {};
    _pinnedUnread = pinned ?? {};
  }

  @visibleForTesting
  Future<void> debugSetLive(String scope, Set<String> ids) async {
    _liveEntities = {..._liveEntities, scope: ids};
    _pruneStaleAcks();
    notifyListeners();
  }

  void _bindRealtime() {
    _rt?.unsubscribe();
    final ch = _db.channel('admin-nav-badges');
    void bump(PostgresChangePayload _) => _scheduleRefresh();
    for (final table in const [
      'karyawan',
      'pengaduan',
      'karyawan_reimburse',
      'payroll_overtime_entries',
      'toko_chat_messages',
      'jadwal_pengajuan',
      'stock_move_history',
      'online_orders',
      'attendance_verifications',
    ]) {
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: bump,
      );
    }
    _rt = ch..subscribe();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_refreshLive());
    });
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    _seenEntities = _decodeSetMap(prefs.getString(_prefSeenKey));
    _pinnedUnread = _decodeSetMap(prefs.getString(_prefPinnedKey));
  }

  Map<String, Set<String>> _decodeSetMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(
          k,
          (v as List).map((e) => e.toString()).toSet(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefSeenKey,
      jsonEncode(_seenEntities.map((k, v) => MapEntry(k, v.toList()))),
    );
    await prefs.setString(
      _prefPinnedKey,
      jsonEncode(_pinnedUnread.map((k, v) => MapEntry(k, v.toList()))),
    );
  }

  Future<void> _refreshLive() async {
    if (_busy || _profile == null || TrainingMode.instance.isActive) {
      if (TrainingMode.instance.isActive && _liveEntities.isNotEmpty) {
        _liveEntities = const {};
        notifyListeners();
      }
      return;
    }
    _busy = true;
    try {
      final p = _profile!;
      final toko = AttendanceAdminScope.tokoOf(p);
      final isPusat = AttendanceAdminScope.isPusatTokoId(toko) ||
          AttendanceAdminScope.isPusatOperator(p);
      final storeKeys =
          AttendanceAdminScope.storeIdAliases(toko).where((e) => e.isNotEmpty);
      final tenantId = AttendanceAdminScope.tenantIdOf(p);

      final next = <String, Set<String>>{};

      await Future.wait<void>([
        _loadKaryawanPending(next, toko, isPusat, storeKeys),
        _loadPengaduanOpen(next, toko, isPusat, storeKeys),
        _loadReimburseOpen(next, toko, isPusat, storeKeys),
        _loadLemburDraft(next, toko, isPusat),
        _loadChatUnread(next, toko, isPusat),
        _loadJadwalPending(next, toko, isPusat),
        _loadLogistikIncoming(next, p, toko),
        _loadOnlineAction(next, toko, isPusat, storeKeys),
        _loadAttendanceQueues(next, p, toko, isPusat, tenantId),
        _loadApkUpdate(next),
      ]);

      _liveEntities = next;
      _pruneStaleAcks();
      notifyListeners();
    } catch (e) {
      debugPrint('AdminNavBadgeService._refreshLive: $e');
    } finally {
      _busy = false;
    }
  }

  void _pruneStaleAcks() {
    var changed = false;
    for (final scope in _seenEntities.keys.toList()) {
      final live = _liveEntities[scope];
      final seen = _seenEntities[scope]!;
      final pruned = AdminNavBadgeLogic.pruneSeen(live: live, seen: seen);
      if (pruned.length != seen.length) {
        _seenEntities[scope] = pruned;
        changed = true;
      }
    }
    for (final scope in _pinnedUnread.keys.toList()) {
      final live = _liveEntities[scope] ?? const {};
      final pinned = _pinnedUnread[scope]!;
      final pruned = AdminNavBadgeLogic.prunePinned(live: live, pinned: pinned);
      if (pruned.length != pinned.length) {
        if (pruned.isEmpty) {
          _pinnedUnread.remove(scope);
        } else {
          _pinnedUnread[scope] = pruned;
        }
        changed = true;
      }
    }
    if (changed) unawaited(_savePersisted());
  }

  Future<Set<String>> _idsFromRows(dynamic rows) async {
    return {
      for (final r in rows as List)
        if (r['id'] != null) r['id'].toString(),
    }.where((s) => s.isNotEmpty).toSet();
  }

  Future<void> _loadKaryawanPending(
    Map<String, Set<String>> out,
    String toko,
    bool isPusat,
    Iterable<String> storeKeys,
  ) async {
    if (!AttendanceAdminScope.canOpenKaryawanManagement(_profile!)) return;
    const pending = ['Pending', 'Menunggu OTP', 'Menunggu Persetujuan'];
    var q =
        _db.from('karyawan').select('id').inFilter('status_approval', pending);
    if (!isPusat && toko.isNotEmpty) {
      final keys = storeKeys.isEmpty ? [toko] : storeKeys.toList();
      q = q.inFilter('toko_id', keys);
    }
    final ids = await _idsFromRows(await q);
    if (ids.isNotEmpty) out['karyawan'] = ids;
  }

  Future<void> _loadPengaduanOpen(
    Map<String, Set<String>> out,
    String toko,
    bool isPusat,
    Iterable<String> storeKeys,
  ) async {
    var q = _db.from('pengaduan').select('id').eq('status', 'OPEN');
    if (!isPusat && toko.isNotEmpty) {
      final keys = storeKeys.isEmpty ? [toko] : storeKeys.toList();
      q = q.inFilter('toko_id', keys);
    }
    final ids = await _idsFromRows(await q);
    if (ids.isNotEmpty) out['pengaduan'] = ids;
  }

  Future<void> _loadReimburseOpen(
    Map<String, Set<String>> out,
    String toko,
    bool isPusat,
    Iterable<String> storeKeys,
  ) async {
    var q = _db.from('karyawan_reimburse').select('id').eq('status', 'OPEN');
    if (!isPusat && toko.isNotEmpty) {
      final keys = storeKeys.isEmpty ? [toko] : storeKeys.toList();
      q = q.inFilter('toko_id', keys);
    }
    final ids = await _idsFromRows(await q);
    if (ids.isNotEmpty) out['reimburse'] = ids;
  }

  Future<void> _loadLemburDraft(
    Map<String, Set<String>> out,
    String toko,
    bool isPusat,
  ) async {
    final rows = await PayrollService().listOvertimeDrafts(
      tokoId: toko,
      allToko: isPusat && AttendanceAdminScope.canViewAllStores(_profile!),
    );
    final ids = {
      for (final r in rows)
        if (r['id'] != null) r['id'].toString(),
    }.where((s) => s.isNotEmpty).toSet();
    if (ids.isNotEmpty) out['lembur'] = ids;
  }

  Future<void> _loadChatUnread(
    Map<String, Set<String>> out,
    String toko,
    bool isPusat,
  ) async {
    var q = _db
        .from('toko_chat_messages')
        .select('id')
        .not('sender_karyawan_id', 'is', null);
    if (!isPusat && toko.isNotEmpty) {
      q = q.eq('toko_id', toko);
    }
    final ids = await _idsFromRows(await q);
    if (ids.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final baselined = prefs.getBool(_prefChatBaselinedKey) ?? false;
    if (!baselined) {
      _seenEntities['chat_toko'] = {...?_seenEntities['chat_toko'], ...ids};
      await prefs.setBool(_prefChatBaselinedKey, true);
      await _savePersisted();
      return;
    }
    out['chat_toko'] = ids;
  }

  Future<void> _loadJadwalPending(
    Map<String, Set<String>> out,
    String toko,
    bool isPusat,
  ) async {
    if (!AttendanceAdminScope.canManageJadwal(_profile!)) return;
    final rows = await JadwalPengajuanService().listPending(
      tokoId: isPusat ? null : toko,
      allToko: isPusat,
    );
    final ids = {
      for (final r in rows)
        if (r['id'] != null) r['id'].toString(),
    }.where((s) => s.isNotEmpty).toSet();
    if (ids.isNotEmpty) out['jadwal'] = ids;
  }

  Future<void> _loadLogistikIncoming(
    Map<String, Set<String>> out,
    Map<String, dynamic> profile,
    String toko,
  ) async {
    if (!ReceiveVerificationRules.canOpenIncomingQueue(profile)) return;
    if (toko.isEmpty) return;
    final rows = await ReceiveQueueService().listIncoming(tokoId: toko);
    final ids = {
      for (final r in rows)
        if (r['id'] != null) r['id'].toString(),
    }.where((s) => s.isNotEmpty).toSet();
    if (ids.isNotEmpty) out['logistik'] = ids;
  }

  Future<void> _loadOnlineAction(
    Map<String, Set<String>> out,
    String toko,
    bool isPusat,
    Iterable<String> storeKeys,
  ) async {
    var q = _db
        .from('online_orders')
        .select('id')
        .inFilter('status', ['pending_payment', 'paid', 'packing']);
    if (!isPusat && toko.isNotEmpty) {
      final keys = storeKeys.isEmpty ? [toko] : storeKeys.toList();
      q = q.inFilter('toko_id', keys);
    }
    try {
      final ids = await _idsFromRows(await q);
      if (ids.isNotEmpty) out['online'] = ids;
    } catch (_) {}
  }

  Future<void> _loadAttendanceQueues(
    Map<String, Set<String>> out,
    Map<String, dynamic> profile,
    String toko,
    bool isPusat,
    String? tenantId,
  ) async {
    if ((tenantId ?? '').isEmpty) return;
    if (!AttendanceAdminScope.canOpenStoreMonitor(profile)) return;

    final svc = AttendanceVerificationService();
    final pending = await svc.listByStatus(
      statuses: [AttendanceVerificationStatus.pendingReview],
      tokoId: isPusat ? null : toko,
      tenantId: tenantId,
      limit: 200,
    );
    final pendingIds = {
      for (final r in pending)
        if (r['id'] != null) r['id'].toString(),
    }.where((s) => s.isNotEmpty).toSet();
    if (pendingIds.isNotEmpty) out['monitor_absensi'] = pendingIds;

    final sus = await svc.listByStatus(
      statuses: [AttendanceVerificationStatus.mencurigakan],
      tokoId: isPusat ? null : toko,
      tenantId: tenantId,
      limit: 200,
    );
    final susIds = {
      for (final r in sus)
        if (r['id'] != null) r['id'].toString(),
    }.where((s) => s.isNotEmpty).toSet();
    if (susIds.isNotEmpty) out['tinjauan'] = susIds;
  }

  Future<void> _loadApkUpdate(Map<String, Set<String>> out) async {
    try {
      final info = await AppUpdateService()
          .checkForUpdate(appFlavor: AppUpdateFlavor.admin);
      if (info.hasUpdate && info.urlReachable) {
        out['update_apk'] = {apkEntityId};
      }
    } catch (_) {}
  }
}
