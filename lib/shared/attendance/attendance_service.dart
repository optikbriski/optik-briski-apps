import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'face_template.dart';
import 'geofence_service.dart';
import 'liveness_result.dart';

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

  Future<String> enrollFace({
    required String karyawanId,
    required String tokoId,
    required LivenessCaptureResult liveness,
    required GeofenceCheckResult geo,
  }) async {
    if (!liveness.success ||
        liveness.faceTemplate == null ||
        liveness.photoBytes == null) {
      throw 'Liveness/wajah gagal. Coba lagi dengan pencahayaan lebih baik.';
    }

    final photoUrl = await _uploadPhoto(
      karyawanId: karyawanId,
      tipe: 'ENROLL',
      bytes: liveness.photoBytes!,
    );

    await _client.from('karyawan').update({
      'face_template': liveness.faceTemplate,
      'face_photo_url': photoUrl,
      'face_enrolled_at': DateTime.now().toIso8601String(),
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
      'device_info': defaultTargetPlatform.name,
    });

    return photoUrl;
  }

  Future<void> clockIn({
    required Map<String, dynamic> karyawan,
    required LivenessCaptureResult liveness,
    required GeofenceCheckResult geo,
  }) async {
    final karyawanId = karyawan['id'] as String;
    final tokoId = (karyawan['toko_id'] ?? '').toString();
    if (tokoId.isEmpty) throw 'Toko karyawan belum terisi.';

    final open = await fetchOpenShift(karyawanId);
    if (open != null) throw 'Shift masih OPEN. Absen pulang dulu.';

    final score = _matchOrThrow(karyawan, liveness);

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
      'device_info': defaultTargetPlatform.name,
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

    final score = _matchOrThrow(karyawan, liveness);

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
      'device_info': defaultTargetPlatform.name,
    });
  }

  double _matchOrThrow(
    Map<String, dynamic> karyawan,
    LivenessCaptureResult liveness,
  ) {
    if (!liveness.success || liveness.faceTemplate == null) {
      throw 'Liveness gagal. Pastikan wajah jelas dan senyum saat diminta.';
    }
    if (liveness.photoBytes == null) {
      throw 'Foto absen gagal diambil. Coba lagi.';
    }

    final enrolled = FaceTemplateUtil.fromJson(karyawan['face_template']);
    if (enrolled == null) {
      throw 'Wajah belum terdaftar. Daftar wajah dulu.';
    }

    final score = FaceTemplateUtil.distance(enrolled, liveness.faceTemplate!);
    if (!FaceTemplateUtil.isMatch(enrolled, liveness.faceTemplate!)) {
      throw 'Wajah tidak cocok dengan data terdaftar '
          '(skor ${score.toStringAsFixed(3)}). '
          'Coba pencahayaan lebih baik atau daftar ulang wajah.';
    }
    return score;
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
