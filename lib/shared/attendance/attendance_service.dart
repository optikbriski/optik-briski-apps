import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'attendance_config.dart';
import 'face_template.dart';
import 'geofence_service.dart';
import 'liveness_result.dart';

/// Absensi: GPS + AWS Face Liveness (opsional) + face template lokal.
/// Kredensial AWS hanya di Edge Function — tidak pernah di APK.
class AttendanceService {
  AttendanceService({
    SupabaseClient? client,
    GeofenceService? geofence,
  })  : _client = client ?? Supabase.instance.client,
        _geofence = geofence ?? GeofenceService();

  final SupabaseClient _client;
  final GeofenceService _geofence;

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

  Future<Map<String, dynamic>?> fetchOpenShift(String karyawanId) async {
    return _client
        .from('attendance_shifts')
        .select()
        .eq('karyawan_id', karyawanId)
        .eq('status', 'OPEN')
        .order('masuk_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<GeofenceCheckResult> checkGeofence(String tokoId) {
    return _geofence.ensureAtStore(tokoId);
  }

  bool isFaceEnrolled(Map<String, dynamic>? karyawan) {
    if (karyawan == null) return false;
    return FaceTemplateUtil.fromJson(karyawan['face_template']) != null;
  }

  Future<String> enrollFace({
    required String karyawanId,
    required String tokoId,
    required LivenessCaptureResult liveness,
    required GeofenceCheckResult geo,
  }) async {
    _requireLivenessPassed(liveness);

    final photoUrl = await _uploadPhoto(
      karyawanId: karyawanId,
      tipe: 'ENROLL',
      bytes: liveness.photoBytes!,
    );

    String? awsFaceId;
    try {
      awsFaceId = await _awsIndexFace(
        karyawanId: karyawanId,
        imageBytes: liveness.photoBytes!,
      );
    } catch (e) {
      debugPrint('AWS IndexFaces skip: $e');
    }

    await _client.from('karyawan').update({
      'face_template': liveness.faceTemplate,
      'face_photo_url': photoUrl,
      'face_enrolled_at': DateTime.now().toIso8601String(),
      if (awsFaceId != null) 'aws_face_id': awsFaceId,
    }).eq('id', karyawanId);

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
  }) async {
    final karyawanId = karyawan['id'] as String;
    final tokoId = (karyawan['toko_id'] ?? '').toString();
    if (tokoId.isEmpty) throw 'Toko karyawan belum terisi.';

    final open = await fetchOpenShift(karyawanId);
    if (open != null) throw 'Shift masih OPEN. Absen pulang dulu.';

    final score = await _matchOrThrow(karyawan, liveness);

    final photoUrl = await _uploadPhoto(
      karyawanId: karyawanId,
      tipe: 'MASUK',
      bytes: liveness.photoBytes!,
    );

    final shift = await _client
        .from('attendance_shifts')
        .insert({
          'karyawan_id': karyawanId,
          'toko_id': tokoId,
          'status': 'OPEN',
          'masuk_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    await _client.from('attendance_logs').insert({
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
      'device_info': defaultTargetPlatform.name,
      if (qrTokenId != null && qrTokenId.isNotEmpty) 'qr_token_id': qrTokenId,
    });
  }

  Future<void> clockOut({
    required Map<String, dynamic> karyawan,
    required LivenessCaptureResult liveness,
    required GeofenceCheckResult geo,
  }) async {
    final karyawanId = karyawan['id'] as String;
    final tokoId = (karyawan['toko_id'] ?? '').toString();

    final open = await fetchOpenShift(karyawanId);
    if (open == null) throw 'Belum ada shift masuk hari ini.';

    final score = await _matchOrThrow(karyawan, liveness);

    final photoUrl = await _uploadPhoto(
      karyawanId: karyawanId,
      tipe: 'PULANG',
      bytes: liveness.photoBytes!,
    );

    await _client.from('attendance_shifts').update({
      'status': 'CLOSED',
      'pulang_at': DateTime.now().toIso8601String(),
    }).eq('id', open['id']);

    await _client.from('attendance_logs').insert({
      'shift_id': open['id'],
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'tipe': 'PULANG',
      'photo_url': photoUrl,
      'latitude': geo.latitude,
      'longitude': geo.longitude,
      'distance_meters': geo.distanceMeters,
      'match_score': score,
      'liveness_ok': true,
      'liveness_confidence': liveness.livenessConfidence,
      'liveness_session_id': liveness.livenessSessionId,
      'liveness_provider': liveness.livenessProvider ?? 'local',
      'device_info': defaultTargetPlatform.name,
    });
  }

  void _requireLivenessPassed(LivenessCaptureResult liveness) {
    if (!liveness.success) {
      throw 'Liveness gagal. Pastikan wajah jelas dan ikuti instruksi di layar.';
    }
    if (liveness.photoBytes == null || liveness.faceTemplate == null) {
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

    final enrolled = FaceTemplateUtil.fromJson(karyawan['face_template']);
    if (enrolled == null) {
      throw 'Wajah belum terdaftar. Daftar wajah dulu.';
    }

    double score = 0;
    if (AttendanceConfig.useLocalFaceMatch) {
      score = FaceTemplateUtil.distance(enrolled, liveness.faceTemplate!);
      if (!FaceTemplateUtil.isMatch(enrolled, liveness.faceTemplate!)) {
        throw 'Wajah tidak cocok dengan data terdaftar '
            '(skor ${score.toStringAsFixed(3)}). '
            'Coba pencahayaan lebih baik atau daftar ulang wajah.';
      }
    }

    if (AttendanceConfig.useAwsFaceCompare) {
      await _awsCompareFace(
        karyawanId: karyawan['id'] as String,
        sourceImageUrl: (karyawan['face_photo_url'] ?? '').toString(),
        imageBytes: liveness.photoBytes!,
      );
    }

    return score;
  }

  Future<String?> _awsIndexFace({
    required String karyawanId,
    required Uint8List imageBytes,
  }) async {
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
