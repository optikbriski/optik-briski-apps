import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../training/training_data_client.dart';
import '../training/training_mode.dart';
import 'attendance_config.dart';
import 'attendance_verification_service.dart';
import 'face_template.dart';
import 'geofence_service.dart';
import 'liveness_result.dart';
import 'web_face_signature.dart';

/// Absensi: GPS + liveness (lokal / web) + face match.
/// Android: ML Kit. Web Admin: challenge kamera + signature foto (tanpa AWS).
///
/// Live: online Supabase writes (sync cabang ↔ pusat). Training: same UI/flow;
/// clock-in/out (+ enroll writes) go to local sandbox only — no sync.
class AttendanceService {
  AttendanceService({
    SupabaseClient? client,
    GeofenceService? geofence,
  })  : _client = client ?? Supabase.instance.client,
        _geofence = geofence ?? GeofenceService();

  final SupabaseClient _client;
  final GeofenceService _geofence;
  final _training = TrainingDataClient.instance;

  Future<Map<String, dynamic>?> fetchKaryawan() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final byId =
        await _client.from('karyawan').select().eq('id', user.id).maybeSingle();
    if (byId != null) return byId;

    final email = user.email;
    if (email == null || email.isEmpty) return null;
    return _client.from('karyawan').select().eq('email', email).maybeSingle();
  }

  /// Ambil satu karyawan by id (untuk kiosk Absensi Toko).
  Future<Map<String, dynamic>?> fetchKaryawanById(String karyawanId) async {
    if (karyawanId.isEmpty) return null;
    return _client.from('karyawan').select().eq('id', karyawanId).maybeSingle();
  }

  /// Daftar karyawan aktif di toko (untuk pilih identitas di perangkat toko).
  Future<List<Map<String, dynamic>>> listKaryawanForToko(String tokoId) async {
    if (tokoId.isEmpty) return const [];
    final rows = await _client
        .from('karyawan')
        .select(
          'id, nama, jabatan, toko_id, nik, status_approval, '
          'face_template, face_photo_url, face_enrolled_at, pin_absensi',
        )
        .eq('toko_id', tokoId)
        .order('nama');
    final list = List<Map<String, dynamic>>.from(rows);
    final approved = list.where((k) {
      final st = (k['status_approval'] ?? '').toString().toLowerCase();
      return st.isEmpty ||
          st == 'approved' ||
          st == 'aktif' ||
          st == 'active';
    }).toList();
    return approved.isEmpty ? list : approved;
  }

  /// Verifikasi PIN absensi (opsional) sebelum face match di kiosk.
  bool verifyPinAbsensi(Map<String, dynamic> karyawan, String pin) {
    final expected = (karyawan['pin_absensi'] ?? '').toString().trim();
    if (expected.isEmpty) return true;
    return expected == pin.trim();
  }

  Future<Map<String, dynamic>?> fetchOpenShift(String karyawanId) async {
    if (TrainingMode.instance.isActive) {
      return _training.selectOne(
        'attendance_shifts',
        where: {'karyawan_id': karyawanId, 'status': 'OPEN'},
        orderBy: 'masuk_at',
        ascending: false,
      );
    }
    return _client
        .from('attendance_shifts')
        .select()
        .eq('karyawan_id', karyawanId)
        .eq('status', 'OPEN')
        .order('masuk_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  /// [webKiosk]: Absensi Toko di browser — lewati GPS Wi‑Fi Mac/PC.
  Future<GeofenceCheckResult> checkGeofence(
    String tokoId, {
    bool webKiosk = false,
  }) {
    return _geofence.ensureAtStore(tokoId, webKiosk: webKiosk);
  }

  bool isFaceEnrolled(Map<String, dynamic>? karyawan) {
    if (karyawan == null) return false;
    if (FaceTemplateUtil.fromJson(karyawan['face_template']) != null) {
      return true;
    }
    // Web match butuh foto referensi; anggap enrolled jika URL ada.
    final photo = (karyawan['face_photo_url'] ?? '').toString().trim();
    return photo.isNotEmpty;
  }

  Future<String> enrollFace({
    required String karyawanId,
    required String tokoId,
    required LivenessCaptureResult liveness,
    required GeofenceCheckResult geo,
  }) async {
    _requireLivenessPassed(liveness);
    TrainingMode.instance.assertSameToko(tokoId);

    final photoUrl = await _uploadPhoto(
      karyawanId: karyawanId,
      tipe: 'ENROLL',
      bytes: liveness.photoBytes!,
    );

    var template = liveness.faceTemplate;
    if (template == null && liveness.photoBytes != null) {
      template = await WebFaceSignature.fromJpeg(liveness.photoBytes!);
    }

    // Training: local sandbox only — no AWS index, no prod karyawan update, no sync.
    if (TrainingMode.instance.isActive) {
      await _training.insert('karyawan_face', {
        'id': karyawanId,
        'karyawan_id': karyawanId,
        'toko_id': tokoId,
        'face_template': template,
        'face_photo_url': photoUrl,
        'face_enrolled_at': DateTime.now().toIso8601String(),
      });
      await _training.insert('attendance_logs', {
        'karyawan_id': karyawanId,
        'toko_id': tokoId,
        'tipe': 'ENROLL',
        'photo_url': photoUrl,
        'latitude': geo.latitude,
        'longitude': geo.longitude,
        'distance_meters': geo.distanceMeters,
        'match_score': 0,
        'liveness_ok': true,
        'liveness_confidence': liveness.livenessConfidence,
        'liveness_session_id': liveness.livenessSessionId,
        'liveness_provider': liveness.livenessProvider ?? 'local',
        'device_info': defaultTargetPlatform.name,
      });
      return photoUrl;
    }

    String? awsFaceId;
    if (AttendanceConfig.useAwsFaceCompare) {
      try {
        awsFaceId = await _awsIndexFace(
          karyawanId: karyawanId,
          imageBytes: liveness.photoBytes!,
        );
      } catch (e) {
        debugPrint('AWS IndexFaces skip: $e');
      }
    }

    ProdWriteGuard.check('attendance.enrollFace.karyawan');
    await _client.from('karyawan').update({
      'face_template': template ?? liveness.faceTemplate,
      'face_photo_url': photoUrl,
      'face_enrolled_at': DateTime.now().toIso8601String(),
      if (awsFaceId != null) 'aws_face_id': awsFaceId,
    }).eq('id', karyawanId);

    ProdWriteGuard.check('attendance.enrollFace.logs');
    await _client.from('attendance_logs').insert({
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'tipe': 'ENROLL',
      'photo_url': photoUrl,
      'latitude': geo.latitude,
      'longitude': geo.longitude,
      'distance_meters': geo.distanceMeters,
      'match_score': 0,
      'liveness_ok': true,
      'liveness_confidence': liveness.livenessConfidence,
      'liveness_session_id': liveness.livenessSessionId,
      'liveness_provider': liveness.livenessProvider ?? 'local',
      'device_info': defaultTargetPlatform.name,
    });

    return photoUrl;
  }

  Future<void> clockIn({
    required Map<String, dynamic> karyawan,
    required LivenessCaptureResult liveness,
    required GeofenceCheckResult geo,
    String? qrTokenId,
    bool storeKiosk = false,
  }) async {
    final karyawanId = karyawan['id'] as String;
    final tokoId = (karyawan['toko_id'] ?? '').toString();
    if (tokoId.isEmpty) throw 'Toko karyawan belum terisi.';
    TrainingMode.instance.assertSameToko(tokoId);

    final open = await fetchOpenShift(karyawanId);
    if (open != null) throw 'Shift masih OPEN. Absen pulang dulu.';

    final score = await _matchOrThrow(karyawan, liveness);
    final deviceInfo = storeKiosk
        ? '${defaultTargetPlatform.name}-toko-kiosk'
        : defaultTargetPlatform.name;

    final photoUrl = await _uploadPhoto(
      karyawanId: karyawanId,
      tipe: 'MASUK',
      bytes: liveness.photoBytes!,
    );

    final shiftPayload = {
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'status': 'OPEN',
      'masuk_at': DateTime.now().toIso8601String(),
    };

    // Training: local sandbox only (offline OK) — never sync to pusat.
    if (TrainingMode.instance.isActive) {
      final shift = await _training.insert('attendance_shifts', shiftPayload);
      await _training.insert('attendance_logs', {
        'shift_id': shift['id'],
        'karyawan_id': karyawanId,
        'toko_id': tokoId,
        'tipe': 'MASUK',
        'photo_url': photoUrl,
        'latitude': geo.latitude,
        'longitude': geo.longitude,
        'distance_meters': geo.distanceMeters,
        'match_score': score,
        'liveness_ok': true,
        'liveness_confidence': liveness.livenessConfidence,
        'liveness_session_id': liveness.livenessSessionId,
        'liveness_provider': liveness.livenessProvider ?? 'local',
        'device_info': deviceInfo,
        if (qrTokenId != null && qrTokenId.isNotEmpty) 'qr_token_id': qrTokenId,
      });
      return;
    }

    ProdWriteGuard.check('attendance.clockIn.shift');
    final shift = await _client
        .from('attendance_shifts')
        .insert(shiftPayload)
        .select()
        .single();

    ProdWriteGuard.check('attendance.clockIn.log');
    final log = await _client.from('attendance_logs').insert({
      'shift_id': shift['id'],
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'tipe': 'MASUK',
      'photo_url': photoUrl,
      'latitude': geo.latitude,
      'longitude': geo.longitude,
      'distance_meters': geo.distanceMeters,
      'match_score': score,
      'liveness_ok': true,
      'liveness_confidence': liveness.livenessConfidence,
      'liveness_session_id': liveness.livenessSessionId,
      'liveness_provider': liveness.livenessProvider ?? 'local',
      'device_info': deviceInfo,
      if (qrTokenId != null && qrTokenId.isNotEmpty) 'qr_token_id': qrTokenId,
    }).select('id').single();

    // Antrean Admin: bandingkan capture vs foto terdaftar.
    final enrolledUrl = (karyawan['face_photo_url'] ?? '').toString().trim();
    await AttendanceVerificationService(client: _client).enqueueAfterClockIn(
      shiftId: shift['id'].toString(),
      logId: log['id']?.toString(),
      karyawanId: karyawanId,
      tokoId: tokoId,
      capturePhotoUrl: photoUrl,
      enrolledPhotoUrl: enrolledUrl.isEmpty ? null : enrolledUrl,
      matchScore: score,
      livenessOk: true,
      livenessConfidence: liveness.livenessConfidence,
      livenessProvider: liveness.livenessProvider ?? 'local',
    );
  }

  Future<void> clockOut({
    required Map<String, dynamic> karyawan,
    required LivenessCaptureResult liveness,
    required GeofenceCheckResult geo,
    bool storeKiosk = false,
  }) async {
    await _clockOutCore(
      karyawan: karyawan,
      geo: geo,
      storeKiosk: storeKiosk,
      liveness: liveness,
      skipFaceMatch: false,
    );
  }

  /// Absen pulang tanpa face match — hanya bukti QR + GPS geofence (kiosk toko).
  Future<void> clockOutByGeoUnlock({
    required Map<String, dynamic> karyawan,
    required GeofenceCheckResult geo,
    bool storeKiosk = true,
    String? qrTokenId,
  }) async {
    if (!geo.inside || geo.latitude == null || geo.longitude == null) {
      throw 'Absen pulang ditolak: GPS harus di dalam area toko.';
    }
    await _clockOutCore(
      karyawan: karyawan,
      geo: geo,
      storeKiosk: storeKiosk,
      liveness: null,
      skipFaceMatch: true,
      qrTokenId: qrTokenId,
    );
  }

  Future<void> _clockOutCore({
    required Map<String, dynamic> karyawan,
    required GeofenceCheckResult geo,
    required bool storeKiosk,
    required bool skipFaceMatch,
    LivenessCaptureResult? liveness,
    String? qrTokenId,
  }) async {
    final karyawanId = karyawan['id'] as String;
    final tokoId = (karyawan['toko_id'] ?? '').toString();
    if (tokoId.isNotEmpty) {
      TrainingMode.instance.assertSameToko(tokoId);
    }

    final open = await fetchOpenShift(karyawanId);
    if (open == null) throw 'Belum ada shift masuk hari ini.';

    final double? score;
    final String? photoUrl;
    final bool livenessOk;
    final double? livenessConfidence;
    final String? livenessSessionId;
    final String? livenessProvider;

    if (skipFaceMatch) {
      score = null;
      photoUrl = null;
      livenessOk = false;
      livenessConfidence = null;
      livenessSessionId = null;
      livenessProvider = 'qr+gps';
    } else {
      if (liveness == null) throw 'Face match wajib untuk absen wajah.';
      score = await _matchOrThrow(karyawan, liveness);
      photoUrl = await _uploadPhoto(
        karyawanId: karyawanId,
        tipe: 'PULANG',
        bytes: liveness.photoBytes!,
      );
      livenessOk = true;
      livenessConfidence = liveness.livenessConfidence;
      livenessSessionId = liveness.livenessSessionId;
      livenessProvider = liveness.livenessProvider ?? 'local';
    }

    final deviceInfo = storeKiosk
        ? (skipFaceMatch
            ? '${defaultTargetPlatform.name}-toko-kiosk-qr-pulang'
            : '${defaultTargetPlatform.name}-toko-kiosk')
        : defaultTargetPlatform.name;

    final logPayload = <String, dynamic>{
      'shift_id': open['id'],
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'tipe': 'PULANG',
      'photo_url': photoUrl,
      'latitude': geo.latitude,
      'longitude': geo.longitude,
      'distance_meters': geo.distanceMeters,
      'match_score': score,
      'liveness_ok': livenessOk,
      'liveness_confidence': livenessConfidence,
      'liveness_session_id': livenessSessionId,
      'liveness_provider': livenessProvider,
      'device_info': deviceInfo,
      if (qrTokenId != null && qrTokenId.isNotEmpty) 'qr_token_id': qrTokenId,
    };

    if (TrainingMode.instance.isActive) {
      await _training.update(
        'attendance_shifts',
        {
          'status': 'CLOSED',
          'pulang_at': DateTime.now().toIso8601String(),
        },
        where: {'id': open['id']},
      );
      await _training.insert('attendance_logs', logPayload);
      return;
    }

    ProdWriteGuard.check('attendance.clockOut.shift');
    await _client.from('attendance_shifts').update({
      'status': 'CLOSED',
      'pulang_at': DateTime.now().toIso8601String(),
    }).eq('id', open['id']);

    ProdWriteGuard.check('attendance.clockOut.log');
    await _client.from('attendance_logs').insert(logPayload);
  }

  void _requireLivenessPassed(LivenessCaptureResult liveness) {
    if (!liveness.success) {
      throw 'Liveness gagal. Pastikan wajah jelas dan ikuti instruksi di layar.';
    }
    if (liveness.photoBytes == null) {
      throw 'Wajah tidak terbaca jelas. Coba lagi dengan pencahayaan lebih baik.';
    }
    // Native butuh template ML Kit; web boleh signature dari foto saja.
    if (!kIsWeb && liveness.faceTemplate == null) {
      throw 'Wajah tidak terbaca jelas. Coba lagi dengan pencahayaan lebih baik.';
    }
    if (AttendanceConfig.useAwsFaceLiveness) {
      if (liveness.livenessProvider != 'aws') {
        throw 'AWS Face Liveness belum aktif / gagal. '
            'Hubungi admin — akun AWS belum siap, atau matikan flag '
            'useAwsFaceLiveness di AttendanceConfig.';
      }
      final conf = liveness.livenessConfidence ?? 0;
      if (conf < AttendanceConfig.minLivenessConfidence) {
        throw 'Skor liveness AWS ${conf.toStringAsFixed(1)} di bawah '
            '${AttendanceConfig.minLivenessConfidence.toStringAsFixed(0)}.';
      }
    }
  }

  Future<double> _matchOrThrow(
    Map<String, dynamic> karyawan,
    LivenessCaptureResult liveness,
  ) async {
    _requireLivenessPassed(liveness);

    // Web Admin: bandingkan foto live vs face_photo_url (signature browser).
    if (kIsWeb) {
      return _matchWebPhotoOrThrow(karyawan, liveness);
    }

    final enrolled = FaceTemplateUtil.fromJson(karyawan['face_template']);
    if (enrolled == null) {
      throw 'Wajah belum terdaftar. Daftar wajah dulu.';
    }

    double score = 0;
    if (AttendanceConfig.useLocalFaceMatch) {
      final live = liveness.faceTemplate;
      if (live == null) {
        throw 'Wajah tidak terbaca jelas. Coba lagi dengan pencahayaan lebih baik.';
      }
      // Template web (256) vs ML Kit (15) tidak kompatibel.
      if (WebFaceSignature.isWebVector(enrolled) ||
          WebFaceSignature.isWebVector(live)) {
        return _matchWebPhotoOrThrow(karyawan, liveness);
      }
      score = FaceTemplateUtil.distance(enrolled, live);
      if (!FaceTemplateUtil.isMatch(enrolled, live)) {
        throw 'Wajah tidak cocok dengan data terdaftar '
            '(skor ${score.toStringAsFixed(3)}). '
            'Coba pencahayaan lebih baik atau daftar ulang wajah.';
      }
    }

    // Training stays offline-capable: skip networked AWS compare.
    if (AttendanceConfig.useAwsFaceCompare && !TrainingMode.instance.isActive) {
      await _awsCompareFace(
        karyawanId: karyawan['id'] as String,
        sourceImageUrl: (karyawan['face_photo_url'] ?? '').toString(),
        imageBytes: liveness.photoBytes!,
      );
    }

    return score;
  }

  Future<double> _matchWebPhotoOrThrow(
    Map<String, dynamic> karyawan,
    LivenessCaptureResult liveness,
  ) async {
    final photoUrl = (karyawan['face_photo_url'] ?? '').toString().trim();
    if (photoUrl.isEmpty) {
      throw 'Foto wajah terdaftar belum ada. Daftar ulang wajah '
          '(perlu foto referensi untuk absensi web).';
    }

    final liveBytes = liveness.photoBytes!;
    var liveSig = liveness.faceTemplate;
    if (!WebFaceSignature.isWebVector(liveSig)) {
      liveSig = await WebFaceSignature.fromJpeg(liveBytes);
    }
    if (liveSig == null) {
      throw 'Wajah live tidak terbaca. Pastikan wajah di dalam oval dan cahaya cukup.';
    }

    final enrolledBytes = await _downloadBytes(photoUrl);
    final enrolledSig = await WebFaceSignature.fromJpeg(enrolledBytes);
    if (enrolledSig == null) {
      throw 'Foto wajah terdaftar rusak / tidak jelas. Daftar ulang wajah.';
    }

    final score = WebFaceSignature.distance(enrolledSig, liveSig);
    if (!WebFaceSignature.isMatch(enrolledSig, liveSig)) {
      throw 'Wajah tidak cocok dengan data terdaftar '
          '(skor web ${score.toStringAsFixed(3)}). '
          'Coba pencahayaan lebih baik atau daftar ulang wajah.';
    }
    return score;
  }

  Future<Uint8List> _downloadBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw 'Gagal unduh foto wajah terdaftar (${res.statusCode}).';
      }
      if (res.bodyBytes.length < 500) {
        throw 'Foto wajah terdaftar kosong / rusak.';
      }
      return res.bodyBytes;
    } catch (e) {
      final msg = e.toString();
      if (msg.startsWith('Gagal unduh') || msg.startsWith('Foto wajah')) {
        rethrow;
      }
      throw 'Gagal unduh foto wajah terdaftar. Cek koneksi / CORS storage.';
    }
  }

  Future<String?> _awsIndexFace({
    required String karyawanId,
    required Uint8List imageBytes,
  }) async {
    TrainingMode.guardProductionWrite('attendance.awsIndexFace');
    final res = await _client.functions.invoke(
      'aws-rekognition',
      body: {
        'action': 'enroll',
        'karyawan_id': karyawanId,
        'image_base64': base64Encode(imageBytes),
      },
    );
    final data = res.data;
    if (data is Map && data['face_id'] != null) {
      return data['face_id'].toString();
    }
    return null;
  }

  Future<void> _awsCompareFace({
    required String karyawanId,
    required String sourceImageUrl,
    required Uint8List imageBytes,
  }) async {
    TrainingMode.guardProductionWrite('attendance.awsCompareFace');
    if (sourceImageUrl.isEmpty) {
      throw 'Foto wajah terdaftar belum ada untuk perbandingan AWS.';
    }
    final res = await _client.functions.invoke(
      'aws-rekognition',
      body: {
        'action': 'compare',
        'karyawan_id': karyawanId,
        'source_image_url': sourceImageUrl,
        'image_base64': base64Encode(imageBytes),
      },
    );
    final data = res.data;
    if (data is Map && data['matched'] == true) return;
    throw (data is Map ? data['error'] : null)?.toString() ??
        'Wajah tidak cocok (AWS CompareFaces).';
  }

  Future<String> _uploadPhoto({
    required String karyawanId,
    required String tipe,
    required Uint8List bytes,
  }) async {
    final path =
        '$karyawanId/${tipe.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    if (TrainingMode.instance.isActive) {
      return _training.storeFile('attendance_photos/$path', bytes);
    }
    ProdWriteGuard.check('attendance.uploadPhoto');
    await _client.storage.from('attendance_photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return _client.storage.from('attendance_photos').getPublicUrl(path);
  }
}
