import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import 'shift_auto_assign.dart';
import 'sop_score.dart';

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
  });

  final String tokoId;
  final String tanggal;
  final int storyCount;
  final int displayDone;
  final int displayRequired;
  final bool sapuDone;
  final bool stokDone;
  final Set<int> completedDisplaySlots;
}

class SopDailyService {
  SopDailyService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;
  static final _dateKey = DateFormat('yyyy-MM-dd');

  String todayKey([DateTime? now]) => _dateKey.format(now ?? DateTime.now());

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

    final stories = await _db
        .from('sop_story_posts')
        .select('id')
        .inFilter('toko_id', keys)
        .eq('tanggal', day);
    final storyCount = (stories as List).length;

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
    );
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
