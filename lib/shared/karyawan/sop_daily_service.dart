import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../attendance/attendance_dinas.dart';
import 'shift_auto_assign.dart';
import 'sop_score.dart';
import 'sop_story_resolve.dart';

/// Fakta SOP cabang hari ini + sync skor ±25.
class SopBranchState {
  const SopBranchState({
    required this.tokoId,
    required this.tanggal,
    required this.storyCount,
    required this.displayDone,
    required this.displayRequired,
    required this.sapuDone,
    required this.stokDone,
    required this.completedDisplaySlots,
    this.igConfigured = false,
    this.igLive = false,
    this.igUsername,
    this.storyError,
  });

  final String tokoId;
  final String tanggal;
  final int storyCount;
  final int displayDone;
  final int displayRequired;
  final bool sapuDone;
  final bool stokDone;
  final Set<int> completedDisplaySlots;

  /// Toko punya akun IG di detail toko. [igLive] = hitungan dari Graph/cache.
  final bool igConfigured;
  final bool igLive;
  final String? igUsername;
  final String? storyError;
}

class SopDailyService {
  SopDailyService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  String todayKey([DateTime? now]) => AttendanceDinas.todayKey(now);

  List<String> _tokoKeys(String tokoId) {
    final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
    if (aliases.isEmpty) {
      final t = tokoId.trim();
      return t.isEmpty ? const [] : [t];
    }
    return aliases;
  }

  Future<SopBranchState> fetchBranchState({
    required String tokoId,
    String? tanggal,
    int displayRequired = SopScore.displaySlotsDefault,
    bool forceStoryRefresh = false,
  }) async {
    final toko = tokoId.trim();
    final day = (tanggal ?? todayKey()).trim();
    final keys = _tokoKeys(toko);
    if (keys.isEmpty) {
      return SopBranchState(
        tokoId: toko,
        tanggal: day,
        storyCount: 0,
        displayDone: 0,
        displayRequired: displayRequired,
        sapuDone: false,
        stokDone: false,
        completedDisplaySlots: const {},
      );
    }

    final ig = await _tokoIg(keys);
    final honorCount = await _storyFromPosts(keys: keys, tanggal: day);
    var storyCount = honorCount;
    String? storyUser = ig.username;
    String? storyErr;
    var igLive = false;
    if (ig.configured) {
      final igHit = await _storyFromIg(
        tokoId: toko,
        tanggal: day,
        keys: keys,
        force: forceStoryRefresh,
        usernameHint: ig.username,
      );
      final picked = SopStoryResolve.pick(
        hasAccount: true,
        igCount: igHit.ok ? igHit.count : null,
        cacheCount: igHit.ok ? null : igHit.cacheCount,
        honorCount: honorCount,
      );
      storyCount = picked.count;
      igLive = picked.live;
      storyErr = igHit.ok ? null : igHit.error;
      storyUser = igHit.username ?? ig.username;
    }

    final slots = await _db
        .from('sop_display_slots')
        .select('slot_index, completed_at')
        .inFilter('toko_id', keys)
        .eq('tanggal', day);
    final doneSlots = <int>{};
    for (final raw in slots as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['completed_at'] == null) continue;
      final idx = (m['slot_index'] as num?)?.toInt();
      if (idx != null) doneSlots.add(idx);
    }

    final sapu = await _db
        .from('sop_sapu_claims')
        .select('toko_id')
        .inFilter('toko_id', keys)
        .eq('tanggal', day)
        .limit(1);
    final stok = await _db
        .from('sop_stok_checks')
        .select('toko_id, matched_admin')
        .inFilter('toko_id', keys)
        .eq('tanggal', day)
        .limit(1);

    final stokDone = (stok as List).isNotEmpty &&
        (Map<String, dynamic>.from(stok.first as Map)['matched_admin'] !=
            false);

    return SopBranchState(
      tokoId: toko,
      tanggal: day,
      storyCount: storyCount,
      displayDone: doneSlots.length.clamp(0, displayRequired),
      displayRequired: displayRequired,
      sapuDone: (sapu as List).isNotEmpty,
      stokDone: stokDone,
      completedDisplaySlots: doneSlots,
      igConfigured: ig.configured,
      igLive: igLive,
      igUsername: storyUser ?? ig.username,
      storyError: storyErr,
    );
  }

  Future<({bool configured, String? username})> _tokoIg(
    List<String> keys,
  ) async {
    try {
      final rows = await _db
          .from('toko_id')
          .select('ig_user_id, ig_username')
          .inFilter('id', keys);
      var configured = false;
      String? username;
      for (final raw in rows as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['ig_user_id'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        final un = (m['ig_username'] ?? '')
            .toString()
            .trim()
            .replaceFirst(RegExp(r'^@+'), '');
        if (id.isNotEmpty || un.isNotEmpty) configured = true;
        if (username == null && un.isNotEmpty) username = un;
      }
      return (configured: configured, username: username);
    } catch (_) {
      return (configured: false, username: null);
    }
  }

  Future<int> _storyFromPosts({
    required List<String> keys,
    required String tanggal,
  }) async {
    final stories = await _db
        .from('sop_story_posts')
        .select('id')
        .inFilter('toko_id', keys)
        .eq('tanggal', tanggal);
    return (stories as List).length;
  }

  Future<({bool ok, int count, int? cacheCount, String? username, String? error})>
      _storyFromIg({
    required String tokoId,
    required String tanggal,
    required List<String> keys,
    required bool force,
    String? usernameHint,
  }) async {
    if (!force) {
      final cached = await _readIgCache(keys: keys, tanggal: tanggal);
      if (cached != null) {
        return (
          ok: true,
          count: cached.count,
          cacheCount: cached.count,
          username: cached.username ?? usernameHint,
          error: null,
        );
      }
    }
    try {
      final res = await _db.functions.invoke(
        'ig-story-count',
        body: {
          'toko_id': tokoId,
          'tanggal': tanggal,
          'force': force,
        },
      );
      final data = _asMap(res.data);
      if (data['ok'] == true && data['configured'] == true) {
        final n = (data['count'] as num?)?.toInt() ?? 0;
        final un = (data['ig_username'] ?? '').toString().trim();
        return (
          ok: true,
          count: n < 0 ? 0 : n,
          cacheCount: n < 0 ? 0 : n,
          username: un.isEmpty ? usernameHint : un,
          error: null,
        );
      }
      if (data['ok'] == true && data['configured'] != true) {
        return (
          ok: false,
          count: 0,
          cacheCount: null,
          username: usernameHint,
          error: null,
        );
      }
      final err = (data['error'] ?? 'Gagal cek story Instagram.').toString();
      final stale = await _readIgCache(
        keys: keys,
        tanggal: tanggal,
        maxAge: null,
      );
      return (
        ok: false,
        count: 0,
        cacheCount: stale?.count,
        username: stale?.username ?? usernameHint,
        error: err,
      );
    } on FunctionException catch (e) {
      final stale = await _readIgCache(
        keys: keys,
        tanggal: tanggal,
        maxAge: null,
      );
      return (
        ok: false,
        count: 0,
        cacheCount: stale?.count,
        username: stale?.username ?? usernameHint,
        error: _fnError(e),
      );
    } catch (e) {
      final stale = await _readIgCache(
        keys: keys,
        tanggal: tanggal,
        maxAge: null,
      );
      return (
        ok: false,
        count: 0,
        cacheCount: stale?.count,
        username: stale?.username ?? usernameHint,
        error: '$e',
      );
    }
  }

  Future<({int count, String? username})?> _readIgCache({
    required List<String> keys,
    required String tanggal,
    Duration? maxAge = const Duration(minutes: 8),
  }) async {
    try {
      final rows = await _db
          .from('sop_ig_story_cache')
          .select('story_count, ig_username, fetched_at')
          .inFilter('toko_id', keys)
          .eq('tanggal', tanggal)
          .order('fetched_at', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return null;
      final m = Map<String, dynamic>.from(list.first as Map);
      if (maxAge != null) {
        final fetched = DateTime.tryParse((m['fetched_at'] ?? '').toString());
        if (fetched == null) return null;
        if (DateTime.now().toUtc().difference(fetched.toUtc()) > maxAge) {
          return null;
        }
      }
      return (
        count: (m['story_count'] as num?)?.toInt() ?? 0,
        username: () {
          final u = (m['ig_username'] ?? '').toString().trim();
          return u.isEmpty ? null : u;
        }(),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  String _fnError(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    if (details is String && details.isNotEmpty) return details;
    return e.reasonPhrase?.trim().isNotEmpty == true
        ? e.reasonPhrase!
        : 'Gagal cek story Instagram.';
  }

  Future<SopScoreResult> scoreFor({
    required String tokoId,
    required String jabatan,
    required bool isAktif,
    required bool isLibur,
    String? jamMasuk,
    String? shiftLabel,
    SopBranchState? state,
  }) async {
    final branch = state ??
        await fetchBranchState(tokoId: tokoId);
    return SopScore.compute(
      SopScoreInput(
        layer: officeLayerOf(jabatan),
        isPagi: SopScore.isPagiShift(
          jamMasuk: jamMasuk,
          shiftLabel: shiftLabel,
        ),
        isAktif: isAktif,
        isLibur: isLibur,
        storyCount: branch.storyCount,
        displayDone: branch.displayDone,
        displayRequired: branch.displayRequired,
        stokDone: branch.stokDone,
        sapuDone: branch.sapuDone,
      ),
    );
  }

  Future<void> addStoryPost({
    required String tokoId,
    required String karyawanId,
    String? catatan,
    String? buktiUrl,
  }) async {
    final toko = tokoId.trim();
    final kid = karyawanId.trim();
    if (toko.isEmpty || kid.isEmpty) throw 'Toko / karyawan kosong.';
    final ig = await _tokoIg(_tokoKeys(toko));
    if (ig.configured) {
      final cached = await _readIgCache(
        keys: _tokoKeys(toko),
        tanggal: todayKey(),
        maxAge: null,
      );
      if (cached != null) {
        throw 'Story SOP dihitung dari Instagram bisnis. Post di IG, lalu ketuk Cek story IG.';
      }
    }
    await _db.from('sop_story_posts').insert({
      'toko_id': toko,
      'karyawan_id': kid,
      'tanggal': todayKey(),
      if ((catatan ?? '').trim().isNotEmpty) 'catatan': catatan!.trim(),
      if ((buktiUrl ?? '').trim().isNotEmpty) 'bukti_url': buktiUrl!.trim(),
    });
  }

  Future<void> completeDisplaySlot({
    required String tokoId,
    required String karyawanId,
    required int slotIndex,
    String? buktiUrl,
  }) async {
    final toko = tokoId.trim();
    if (toko.isEmpty) throw 'Toko kosong.';
    if (slotIndex < 1 || slotIndex > SopScore.displaySlotsDefault) {
      throw 'Slot display tidak valid.';
    }
    await _db.from('sop_display_slots').upsert({
      'toko_id': toko,
      'tanggal': todayKey(),
      'slot_index': slotIndex,
      'completed_by': karyawanId.trim(),
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      if ((buktiUrl ?? '').trim().isNotEmpty) 'bukti_url': buktiUrl!.trim(),
    }, onConflict: 'toko_id,tanggal,slot_index');
  }

  Future<void> claimSapu({
    required String tokoId,
    required String karyawanId,
    String? buktiUrl,
  }) async {
    final toko = tokoId.trim();
    if (toko.isEmpty) throw 'Toko kosong.';
    await _db.from('sop_sapu_claims').upsert({
      'toko_id': toko,
      'tanggal': todayKey(),
      'claimed_by': karyawanId.trim(),
      'claimed_at': DateTime.now().toUtc().toIso8601String(),
      if ((buktiUrl ?? '').trim().isNotEmpty) 'bukti_url': buktiUrl!.trim(),
    }, onConflict: 'toko_id,tanggal');
  }

  Future<void> claimStokCheck({
    required String tokoId,
    required String karyawanId,
    bool matchedAdmin = true,
    String? catatan,
  }) async {
    final toko = tokoId.trim();
    if (toko.isEmpty) throw 'Toko kosong.';
    await _db.from('sop_stok_checks').upsert({
      'toko_id': toko,
      'tanggal': todayKey(),
      'checked_by': karyawanId.trim(),
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'matched_admin': matchedAdmin,
      if ((catatan ?? '').trim().isNotEmpty) 'catatan': catatan!.trim(),
    }, onConflict: 'toko_id,tanggal');
  }

  /// Tulis / update poin SOP ±25 ke poin_logs (sumber SOP, ref sop-daily-*).
  Future<int> syncMyPoin({
    required String karyawanId,
    required SopScoreResult score,
    String? tanggal,
  }) async {
    final day = (tanggal ?? todayKey()).trim();
    final parsed = DateTime.tryParse(day);
    final res = await _db.rpc('upsert_sop_daily_poin', params: {
      'p_karyawan_id': karyawanId.trim(),
      'p_tanggal': day,
      'p_poin': score.poin,
    });
    if (res is Map && res['ok'] == false) {
      throw (res['error'] ?? 'Gagal sync poin SOP').toString();
    }
    if (res is Map && res['poin'] is num) {
      return (res['poin'] as num).toInt();
    }
    // Fallback client upsert if RPC missing
    final refId = 'sop-daily-$day';
    try {
      await _db.from('poin_logs').upsert({
        'karyawan_id': karyawanId.trim(),
        'tanggal': day,
        'poin': score.poin,
        'sumber': 'SOP',
        'ref_id': refId,
      }, onConflict: 'karyawan_id,sumber,ref_id');
    } catch (_) {
      await _db.from('poin_logs').insert({
        'karyawan_id': karyawanId.trim(),
        'tanggal': parsed != null ? day : todayKey(),
        'poin': score.poin,
        'sumber': 'SOP',
        'ref_id': refId,
      });
    }
    return score.poin;
  }
}
