import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../training/training_data_client.dart';
import '../training/training_mode.dart';
import 'attendance_admin_scope.dart';
import 'attendance_late_penalty.dart';
import 'attendance_verification_config.dart';

/// Status verifikasi wajah absensi (mirror DB check constraint).
abstract final class AttendanceVerificationStatus {
  static const pendingReview = 'pending_review';
  static const aman = 'aman';
  static const mencurigakan = 'mencurigakan';
  static const curang = 'curang';
}

/// Admin: antrian bandingkan capture masuk vs foto terdaftar + poin/SP.
class AttendanceVerificationService {
  AttendanceVerificationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final _dayKey = DateFormat('yyyy-MM-dd');

  /// Hari kalender Asia/Jakarta (hindari TZ device Admin).
  String _jakartaDayKey([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final jkt = utc.add(const Duration(hours: 7));
    return _dayKey.format(DateTime(jkt.year, jkt.month, jkt.day));
  }

  /// Dipanggil setelah clock-in MASUK sukses → antrean `pending_review`.
  Future<void> enqueueAfterClockIn({
    required String shiftId,
    required String? logId,
    required String karyawanId,
    required String tokoId,
    required String? capturePhotoUrl,
    required String? enrolledPhotoUrl,
    double? matchScore,
    bool? livenessOk,
    double? livenessConfidence,
    String? livenessProvider,
  }) async {
    if (TrainingMode.instance.isActive) return;
    if (shiftId.isEmpty || karyawanId.isEmpty || tokoId.isEmpty) return;

    try {
      await _client.from('attendance_verifications').insert({
        'shift_id': shiftId,
        'log_id': logId,
        'karyawan_id': karyawanId,
        'toko_id': tokoId,
        'status': AttendanceVerificationStatus.pendingReview,
        'capture_photo_url': capturePhotoUrl,
        'enrolled_photo_url': enrolledPhotoUrl,
        'match_score': matchScore,
        'liveness_ok': livenessOk,
        'liveness_confidence': livenessConfidence,
        'liveness_provider': livenessProvider,
      });
    } catch (e) {
      // Unique shift_id / RLS — jangan gagalkan absen.
      // ignore: avoid_print
      print('attendance_verifications enqueue: $e');
    }
  }

  Future<List<Map<String, dynamic>>> listByStatus({
    required List<String> statuses,
    String? tokoId,
    List<String>? tokoIds,
    String? tenantId,
    DateTime? dayStart,
    DateTime? dayEnd,
    int limit = 100,
  }) async {
    var q = _client.from('attendance_verifications').select(
      'id, shift_id, log_id, karyawan_id, toko_id, tenant_id, status, '
      'capture_photo_url, enrolled_photo_url, match_score, '
      'liveness_ok, liveness_confidence, liveness_provider, '
      'notes, reviewed_by, reviewed_at, poin_awarded, created_at, '
      'karyawan:karyawan_id(id, nama, jabatan, face_photo_url)',
    );

    if (statuses.length == 1) {
      q = q.eq('status', statuses.first);
    } else if (statuses.isNotEmpty) {
      q = q.inFilter('status', statuses);
    }
    final tenant = (tenantId ?? AttendanceAdminScope.tenantIdOf(null) ?? '')
        .trim();
    if (tenant.isEmpty) return const [];
    q = q.eq('tenant_id', tenant);

    if (tokoId != null && tokoId.isNotEmpty) {
      final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
      if (aliases.length == 1) {
        q = q.eq('toko_id', aliases.first);
      } else {
        q = q.inFilter('toko_id', aliases);
      }
    } else if (tokoIds != null) {
      final cleaned = AttendanceAdminScope.expandStoreIds(tokoIds);
      if (cleaned.isEmpty) return const [];
      q = q.inFilter('toko_id', cleaned);
    }
    if (dayStart != null) {
      q = q.gte('created_at', dayStart.toUtc().toIso8601String());
    }
    if (dayEnd != null) {
      q = q.lte('created_at', dayEnd.toUtc().toIso8601String());
    }

    final rows = await q.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Valid / Aman: wajah OK. Poin baru di sini (bukan saat clock-in).
  /// - Ontime → +20 (`ABSEN`) saja
  /// - Telat → hanya `ABSEN_TELAT` (tanpa +20)
  Future<void> markAman({
    required String verificationId,
    required String karyawanId,
    required String tokoId,
    String? tenantId,
    String? notes,
  }) async {
    ProdWriteGuard.check('verifikasi.markAman');
    final store = AttendanceAdminScope.requireTokoId(tokoId);
    final tenant = _requireTenant(tenantId);
    final row = await _requireReviewCase(
      verificationId: verificationId,
      karyawanId: karyawanId,
      tokoId: store,
      tenantId: tenant,
      allowedStatuses: const [
        AttendanceVerificationStatus.pendingReview,
        AttendanceVerificationStatus.mencurigakan,
      ],
    );
    final caseKaryawan = row['karyawan_id'].toString();
    final uid = _client.auth.currentUser?.id;
    final now = DateTime.now();
    final tanggal = _jakartaDayKey(now);

    final lateInfo = await _lateInfoForVerification(verificationId);
    final wasLate = lateInfo.isLate && lateInfo.penaltyPoints < 0;
    // Satu jalur saja — jangan gabung ontime + telat.
    // Siklus telat: pagi −1/mnt (08:30–09:00) lalu −20/15mnt; siang −20/15mnt dari 13:00.
    final ontimePoints =
        wasLate ? 0 : AttendanceVerificationConfig.validDayPoints;
    final awarded = wasLate ? lateInfo.penaltyPoints : ontimePoints;

    final updated = await _client
        .from('attendance_verifications')
        .update({
          'status': AttendanceVerificationStatus.aman,
          'notes': notes,
          'reviewed_by': uid,
          'reviewed_at': now.toIso8601String(),
          'poin_awarded': awarded,
        })
        .eq('id', verificationId)
        .eq('tenant_id', tenant)
        .inFilter('status', [
          AttendanceVerificationStatus.pendingReview,
          AttendanceVerificationStatus.mencurigakan,
        ])
        .select('id');

    if (List<dynamic>.from(updated).isEmpty) {
      throw 'Status sudah berubah. Muat ulang daftar.';
    }

    if (wasLate) {
      final logId = lateInfo.logId;
      if (logId == null || logId.isEmpty) {
        throw 'Log absen tidak ditemukan — poin telat tidak bisa ditulis.';
      }
      await _insertPoinLog(
        karyawanId: caseKaryawan,
        tanggal: tanggal,
        poin: lateInfo.penaltyPoints,
        refId: AttendanceLatePenalty.refIdForLog(logId),
        sumber: AttendanceLatePenalty.sumberPoinTelat,
      );
    } else {
      await _insertPoinLog(
        karyawanId: caseKaryawan,
        tanggal: tanggal,
        poin: ontimePoints,
        refId: 'absen-valid-$verificationId',
        sumber: AttendanceVerificationConfig.sumberPoinAbsen,
      );
    }

    await _notifyKaryawan(
      karyawanId: caseKaryawan,
      judul: 'Absensi wajah aman',
      isi: wasLate
          ? 'Verifikasi disetujui. Poin telat ${lateInfo.penaltyPoints} '
              '(tanpa poin ontime).'
          : 'Verifikasi disetujui. Poin ontime +$ontimePoints.',
      tipe: 'ADMIN',
    );
  }

  /// Flag ke antrean tinjauan lanjut (belum hukuman).
  Future<void> markMencurigakan({
    required String verificationId,
    required String tokoId,
    String? tenantId,
    String? notes,
  }) async {
    ProdWriteGuard.check('verifikasi.markMencurigakan');
    final store = AttendanceAdminScope.requireTokoId(tokoId);
    final tenant = _requireTenant(tenantId);
    await _requireReviewCase(
      verificationId: verificationId,
      tokoId: store,
      tenantId: tenant,
      allowedStatuses: const [AttendanceVerificationStatus.pendingReview],
    );
    final uid = _client.auth.currentUser?.id;
    final updated = await _client
        .from('attendance_verifications')
        .update({
          'status': AttendanceVerificationStatus.mencurigakan,
          'notes': notes,
          'reviewed_by': uid,
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', verificationId)
        .eq('tenant_id', tenant)
        .eq('status', AttendanceVerificationStatus.pendingReview)
        .select('id');

    if (List<dynamic>.from(updated).isEmpty) {
      throw 'Status sudah berubah. Muat ulang daftar.';
    }
  }

  /// Terbukti curang: hanya −200 + SP1 (hapus poin telat/ontime absen ini).
  Future<void> markCurang({
    required String verificationId,
    required String karyawanId,
    required String tokoId,
    String? tenantId,
    String? notes,
  }) async {
    ProdWriteGuard.check('verifikasi.markCurang');
    final store = AttendanceAdminScope.requireTokoId(tokoId);
    final tenant = _requireTenant(tenantId);
    final row = await _requireReviewCase(
      verificationId: verificationId,
      karyawanId: karyawanId,
      tokoId: store,
      tenantId: tenant,
      allowedStatuses: const [AttendanceVerificationStatus.mencurigakan],
    );
    final caseKaryawan = row['karyawan_id'].toString();
    final caseToko = (row['toko_id'] ?? store).toString();
    final uid = _client.auth.currentUser?.id;
    final penalty = AttendanceVerificationConfig.cheatingPenaltyPoints;
    final now = DateTime.now();
    final tanggal = _jakartaDayKey(now);
    final refId = 'absen-curang-$verificationId';
    final alasan = (notes == null || notes.trim().isEmpty)
        ? 'Terbukti curang pada verifikasi wajah absensi '
            '(bukan keterlambatan).'
        : notes.trim();

    final logId = (row['log_id'] ?? '').toString().trim();

    final updated = await _client
        .from('attendance_verifications')
        .update({
          'status': AttendanceVerificationStatus.curang,
          'notes': alasan,
          'reviewed_by': uid,
          'reviewed_at': now.toIso8601String(),
          'poin_awarded': penalty,
        })
        .eq('id', verificationId)
        .eq('tenant_id', tenant)
        .eq('status', AttendanceVerificationStatus.mencurigakan)
        .select('id');

    if (List<dynamic>.from(updated).isEmpty) {
      throw 'Status sudah berubah. Muat ulang daftar.';
    }

    // Curang saja — jangan digabung dengan telat / ontime.
    await _removePoinForAbsenEvent(
      karyawanId: caseKaryawan,
      verificationId: verificationId,
      logId: logId.isEmpty ? null : logId,
    );

    await _insertPoinLog(
      karyawanId: caseKaryawan,
      tanggal: tanggal,
      poin: penalty,
      refId: refId,
    );

    try {
      await _client.from('surat_peringatan').insert({
        'karyawan_id': caseKaryawan,
        'toko_id': caseToko,
        'tingkat': AttendanceVerificationConfig.cheatingSpTingkat,
        'alasan': alasan,
        'sumber': AttendanceVerificationConfig.sumberSpCurang,
        'ref_id': verificationId,
        'issued_by': uid,
        'issued_at': now.toIso8601String(),
      });
    } catch (e) {
      if (!_isUniqueViolation(e)) {
        // ignore: avoid_print
        print('surat_peringatan insert: $e');
      }
    }

    await _notifyKaryawan(
      karyawanId: caseKaryawan,
      judul: 'SP ${AttendanceVerificationConfig.cheatingSpTingkat} — Absensi',
      isi: 'Terbukti curang pada verifikasi wajah. '
          'Hanya poin curang $penalty + SP '
          '${AttendanceVerificationConfig.cheatingSpTingkat} '
          '(poin telat/ontime absen ini dibatalkan).',
      tipe: 'ADMIN',
    );
  }

  Future<String?> _logIdForVerification(String verificationId) async {
    try {
      final row = await _client
          .from('attendance_verifications')
          .select('log_id')
          .eq('id', verificationId)
          .maybeSingle();
      final id = (row?['log_id'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<({bool isLate, int penaltyPoints, String? logId})>
      _lateInfoForVerification(String verificationId) async {
    final logId = await _logIdForVerification(verificationId);
    if (logId == null) {
      return (isLate: false, penaltyPoints: 0, logId: null);
    }
    try {
      final log = await _client
          .from('attendance_logs')
          .select(
            'late_seconds, late_penalty_points, created_at, karyawan_id',
          )
          .eq('id', logId)
          .maybeSingle();
      if (log == null) {
        return (isLate: false, penaltyPoints: 0, logId: logId);
      }
      var pts = (log['late_penalty_points'] as num?)?.toInt() ?? 0;
      final secs = (log['late_seconds'] as num?)?.toInt() ?? 0;

      // Cadangan: hitung ulang siklus pagi/siang jika metadata kosong.
      if (pts >= 0 && secs > 0) {
        pts = await _recomputeLatePenaltyPoints(log) ?? pts;
      }
      if (pts >= 0 && secs <= 0) {
        final recomputed = await _recomputeLatePenaltyPoints(log);
        if (recomputed != null && recomputed < 0) pts = recomputed;
      }

      final late = pts < 0 || secs > 0;
      return (
        isLate: late,
        penaltyPoints: pts < 0 ? pts : 0,
        logId: logId,
      );
    } catch (_) {
      return (isLate: false, penaltyPoints: 0, logId: logId);
    }
  }

  /// Hitung ulang penalti dari jadwal + created_at log (siklus pagi/siang).
  Future<int?> _recomputeLatePenaltyPoints(Map<String, dynamic> log) async {
    try {
      final kid = (log['karyawan_id'] ?? '').toString();
      final created = DateTime.tryParse((log['created_at'] ?? '').toString());
      if (kid.isEmpty || created == null) return null;

      final utc = created.toUtc();
      final jkt = utc.add(const Duration(hours: 7));
      final day =
          '${jkt.year.toString().padLeft(4, '0')}-'
          '${jkt.month.toString().padLeft(2, '0')}-'
          '${jkt.day.toString().padLeft(2, '0')}';

      final jadwal = await _client
          .from('jadwal_kerja')
          .select('jam_masuk, is_libur')
          .eq('karyawan_id', kid)
          .eq('tanggal', day)
          .maybeSingle();
      if (jadwal == null || jadwal['is_libur'] == true) return null;
      final jam = (jadwal['jam_masuk'] ?? '').toString().trim();
      if (jam.isEmpty) return null;

      final parsed = AttendanceLatePenalty.parseSchedule(
        tanggalKey: day,
        jamMasuk: jam,
      );
      if (parsed == null) return null;

      return AttendanceLatePenalty.compute(
        clockInUtc: utc,
        scheduledMasukUtc: parsed.utc,
        scheduledMasukHourJakarta: parsed.hourJakarta,
      ).penaltyPoints;
    } catch (_) {
      return null;
    }
  }

  /// Hapus poin ontime/telat untuk event absen ini (sebelum curang).
  Future<void> _removePoinForAbsenEvent({
    required String karyawanId,
    required String verificationId,
    String? logId,
  }) async {
    final refs = <String>[
      'absen-valid-$verificationId',
      if (logId != null && logId.isNotEmpty) 'absen-telat-$logId',
    ];
    for (final ref in refs) {
      try {
        await _client
            .from('poin_logs')
            .delete()
            .eq('karyawan_id', karyawanId)
            .eq('ref_id', ref);
      } catch (_) {}
    }
  }

  /// Insert `poin_logs`. Duplikat ref diabaikan; error lain dilempar.
  Future<void> _insertPoinLog({
    required String karyawanId,
    required String tanggal,
    required int poin,
    required String refId,
    String sumber = AttendanceVerificationConfig.sumberPoinAbsen,
  }) async {
    try {
      await _client.from('poin_logs').insert({
        'karyawan_id': karyawanId,
        'tanggal': tanggal,
        'poin': poin,
        'sumber': sumber,
        'ref_id': refId,
      });
    } catch (e) {
      if (_isUniqueViolation(e)) return;
      throw 'Poin absensi gagal disimpan ke poin_logs: $e';
    }
  }

  static bool _isUniqueViolation(Object e) {
    if (e is PostgrestException) {
      final code = (e.code ?? '').toString();
      final msg = e.message.toLowerCase();
      return code == '23505' ||
          msg.contains('duplicate') ||
          msg.contains('unique');
    }
    final s = e.toString().toLowerCase();
    return s.contains('23505') ||
        s.contains('duplicate') ||
        s.contains('unique');
  }

  Future<Map<String, dynamic>> _requireReviewCase({
    required String verificationId,
    required String tokoId,
    required String tenantId,
    required List<String> allowedStatuses,
    String? karyawanId,
  }) async {
    final row = await _client
        .from('attendance_verifications')
        .select('id, karyawan_id, toko_id, tenant_id, status, log_id')
        .eq('id', verificationId)
        .eq('tenant_id', tenantId)
        .maybeSingle();
    if (row == null) {
      throw 'Kasus tinjauan tidak ditemukan di usaha ini.';
    }
    if (!AttendanceAdminScope.sameTokoId(row['toko_id']?.toString(), tokoId)) {
      throw 'Kasus tinjauan bukan toko ini.';
    }
    if ((row['tenant_id'] ?? '').toString().trim() != tenantId) {
      throw 'Kasus tinjauan bukan milik usaha ini.';
    }
    if (karyawanId != null &&
        karyawanId.trim().isNotEmpty &&
        (row['karyawan_id'] ?? '').toString() != karyawanId) {
      throw 'Karyawan tidak cocok dengan kasus tinjauan.';
    }
    if (!allowedStatuses.contains((row['status'] ?? '').toString())) {
      throw 'Status sudah berubah. Muat ulang daftar.';
    }
    return row;
  }

  String _requireTenant(String? tenantId) {
    final t = (tenantId ?? AttendanceAdminScope.tenantIdOf(null) ?? '').trim();
    if (t.isEmpty) {
      throw StateError(
        'Tenant usaha wajib. Jangan memakai data merek lain.',
      );
    }
    return t;
  }

  /// Notifikasi ke auth user karyawan (`notifikasi.user_id` → auth.users).
  Future<void> _notifyKaryawan({
    required String karyawanId,
    required String judul,
    required String isi,
    required String tipe,
  }) async {
    final authUserId = await _resolveAuthUserId(karyawanId);
    if (authUserId == null || authUserId.isEmpty) return;
    try {
      await _client.from('notifikasi').insert({
        'user_id': authUserId,
        'judul': judul,
        'isi': isi,
        'tipe': tipe,
      });
    } catch (_) {}
  }

  /// Register Karyawan biasanya set id = auth.uid.
  Future<String?> _resolveAuthUserId(String karyawanId) async {
    if (karyawanId.trim().isEmpty) return null;
    return karyawanId;
  }

  String enrolledUrlOf(Map<String, dynamic> row) {
    final enrolled = (row['enrolled_photo_url'] ?? '').toString().trim();
    if (enrolled.isNotEmpty) return enrolled;
    final k = row['karyawan'];
    if (k is Map) {
      return (k['face_photo_url'] ?? '').toString().trim();
    }
    return '';
  }

  String namaOf(Map<String, dynamic> row) {
    final k = row['karyawan'];
    if (k is Map) return (k['nama'] ?? '-').toString();
    return (row['karyawan_id'] ?? '-').toString();
  }

  String jabatanOf(Map<String, dynamic> row) {
    final k = row['karyawan'];
    if (k is Map) return (k['jabatan'] ?? '').toString();
    return '';
  }
}
