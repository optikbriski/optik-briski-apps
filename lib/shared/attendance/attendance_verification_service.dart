import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../training/training_data_client.dart';
import '../training/training_mode.dart';
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
    DateTime? dayStart,
    DateTime? dayEnd,
    int limit = 100,
  }) async {
    var q = _client.from('attendance_verifications').select(
      'id, shift_id, log_id, karyawan_id, toko_id, status, '
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
    if (tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('toko_id', tokoId);
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

  /// Valid (dari antrian) atau Aman (dari tinjauan) → status aman + poin ABSEN.
  Future<void> markAman({
    required String verificationId,
    required String karyawanId,
    String? notes,
  }) async {
    ProdWriteGuard.check('verifikasi.markAman');
    final uid = _client.auth.currentUser?.id;
    final points = AttendanceVerificationConfig.validDayPoints;
    final now = DateTime.now();
    final tanggal = _dayKey.format(now);
    final refId = 'absen-valid-$verificationId';

    final updated = await _client
        .from('attendance_verifications')
        .update({
          'status': AttendanceVerificationStatus.aman,
          'notes': notes,
          'reviewed_by': uid,
          'reviewed_at': now.toIso8601String(),
          'poin_awarded': points,
        })
        .eq('id', verificationId)
        .inFilter('status', [
          AttendanceVerificationStatus.pendingReview,
          AttendanceVerificationStatus.mencurigakan,
        ])
        .select('id');

    if (List<dynamic>.from(updated).isEmpty) {
      throw 'Status sudah berubah. Muat ulang daftar.';
    }

    // Wajib masuk poin_logs — sumber baca APK Karyawan. Duplikat = OK (idempotent).
    await _insertPoinLog(
      karyawanId: karyawanId,
      tanggal: tanggal,
      poin: points,
      refId: refId,
    );

    await _notifyKaryawan(
      karyawanId: karyawanId,
      judul: 'Absensi wajah aman',
      isi: 'Verifikasi absensi wajah disetujui. Poin +$points.',
      tipe: 'ADMIN',
    );
  }

  /// Flag ke antrean tinjauan lanjut (belum hukuman).
  Future<void> markMencurigakan({
    required String verificationId,
    String? notes,
  }) async {
    ProdWriteGuard.check('verifikasi.markMencurigakan');
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
        .eq('status', AttendanceVerificationStatus.pendingReview)
        .select('id');

    if (List<dynamic>.from(updated).isEmpty) {
      throw 'Status sudah berubah. Muat ulang daftar.';
    }
  }

  /// Terbukti curang: -200 poin + SP1. Bukan untuk keterlambatan.
  Future<void> markCurang({
    required String verificationId,
    required String karyawanId,
    required String tokoId,
    String? notes,
  }) async {
    ProdWriteGuard.check('verifikasi.markCurang');
    final uid = _client.auth.currentUser?.id;
    final penalty = AttendanceVerificationConfig.cheatingPenaltyPoints;
    final now = DateTime.now();
    final tanggal = _dayKey.format(now);
    final refId = 'absen-curang-$verificationId';
    final alasan = (notes == null || notes.trim().isEmpty)
        ? 'Terbukti curang pada verifikasi wajah absensi '
            '(bukan keterlambatan).'
        : notes.trim();

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
        .eq('status', AttendanceVerificationStatus.mencurigakan)
        .select('id');

    if (List<dynamic>.from(updated).isEmpty) {
      throw 'Status sudah berubah. Muat ulang daftar.';
    }

    await _insertPoinLog(
      karyawanId: karyawanId,
      tanggal: tanggal,
      poin: penalty,
      refId: refId,
    );

    try {
      await _client.from('surat_peringatan').insert({
        'karyawan_id': karyawanId,
        'toko_id': tokoId,
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
      karyawanId: karyawanId,
      judul: 'SP ${AttendanceVerificationConfig.cheatingSpTingkat} — Absensi',
      isi: 'Terbukti curang pada verifikasi wajah. '
          'Poin $penalty dan SP ${AttendanceVerificationConfig.cheatingSpTingkat}. '
          '(Bukan karena keterlambatan.)',
      tipe: 'ADMIN',
    );
  }

  /// Insert `poin_logs` (sumber ABSEN). Duplikat ref diabaikan; error lain dilempar.
  Future<void> _insertPoinLog({
    required String karyawanId,
    required String tanggal,
    required int poin,
    required String refId,
  }) async {
    try {
      await _client.from('poin_logs').insert({
        'karyawan_id': karyawanId,
        'tanggal': tanggal,
        'poin': poin,
        'sumber': AttendanceVerificationConfig.sumberPoinAbsen,
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
