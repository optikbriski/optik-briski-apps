import 'package:supabase_flutter/supabase_flutter.dart';

import '../training/training_mode.dart';
import '../training/training_sandbox_store.dart';
import 'attendance_config.dart';
import 'geofence_service.dart';

class AttendanceGeoUnlock {
  const AttendanceGeoUnlock({
    required this.id,
    required this.karyawanId,
    required this.tokoId,
    required this.expiresAt,
    this.createdAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.source = 'qr+gps',
    this.qrTokenId,
  });

  final String id;
  final String karyawanId;
  final String tokoId;
  final DateTime expiresAt;
  final DateTime? createdAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String source;
  final String? qrTokenId;

  bool get isValid => expiresAt.isAfter(DateTime.now());

  /// Hasil geofence dari bukti unlock (untuk log absensi Admin).
  GeofenceCheckResult toGeofenceResult() {
    return GeofenceCheckResult(
      inside: true,
      gpsSkipped: false,
      message: 'Lokasi OK (scan QR + GPS karyawan).',
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
    );
  }

  factory AttendanceGeoUnlock.fromJson(Map<String, dynamic> json) {
    return AttendanceGeoUnlock(
      id: (json['id'] ?? '').toString(),
      karyawanId: (json['karyawan_id'] ?? '').toString(),
      tokoId: (json['toko_id'] ?? '').toString(),
      expiresAt: DateTime.parse(json['expires_at'].toString()).toLocal(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : null,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
      source: (json['source'] ?? 'qr+gps').toString(),
      qrTokenId: json['qr_token_id']?.toString(),
    );
  }
}

/// Bukti lokasi singkat dari HP karyawan (QR Absensi + GPS geofence).
class AttendanceGeoUnlockService {
  AttendanceGeoUnlockService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<AttendanceGeoUnlock> createUnlock({
    required String karyawanId,
    required String tokoId,
    required GeofenceCheckResult geo,
    String? qrTokenId,
    int? ttlSeconds,
    String source = 'qr+gps',
  }) async {
    final ttl = ttlSeconds ?? AttendanceConfig.geoUnlockTtlSeconds;

    if (TrainingMode.instance.isActive) {
      TrainingMode.instance.assertSameToko(tokoId);
      final expires = DateTime.now().add(Duration(seconds: ttl));
      final row = await TrainingSandboxStore.instance.insert(
        'attendance_geo_unlocks',
        {
          'karyawan_id': karyawanId,
          'toko_id': tokoId,
          'expires_at': expires.toIso8601String(),
          'latitude': geo.latitude,
          'longitude': geo.longitude,
          'accuracy_meters': geo.accuracyMeters,
          'source': source,
          'consumed_at': null,
          if (qrTokenId != null && qrTokenId.isNotEmpty)
            'qr_token_id': qrTokenId,
        },
      );
      return AttendanceGeoUnlock.fromJson(row);
    }

    try {
      final res = await _client.rpc(
        'create_attendance_geo_unlock',
        params: {
          'p_toko_id': tokoId,
          'p_latitude': geo.latitude,
          'p_longitude': geo.longitude,
          'p_accuracy_meters': geo.accuracyMeters,
          'p_ttl_seconds': ttl,
          'p_qr_token_id': qrTokenId,
          'p_source': source,
        },
      );
      final map = _asMap(res);
      if (map == null || (map['id'] ?? '').toString().isEmpty) {
        throw 'Gagal menyimpan verifikasi lokasi.';
      }
      return AttendanceGeoUnlock.fromJson(map);
    } on PostgrestException catch (e) {
      throw _rpcMessage(e);
    }
  }

  /// Unlock aktif (belum kedaluwarsa / belum dipakai) untuk satu karyawan.
  Future<AttendanceGeoUnlock?> fetchValidUnlock({
    required String karyawanId,
    required String tokoId,
  }) async {
    if (karyawanId.isEmpty || tokoId.isEmpty) return null;

    if (TrainingMode.instance.isActive) {
      return _latestTrainingUnlock(tokoId: tokoId, karyawanId: karyawanId);
    }

    try {
      final res = await _client.rpc(
        'get_valid_attendance_geo_unlock',
        params: {
          'p_karyawan_id': karyawanId,
          'p_toko_id': tokoId,
        },
      );
      return _unlockFromRpc(res);
    } on PostgrestException catch (e) {
      throw _rpcMessage(e);
    }
  }

  /// Unlock terbaru di toko (Admin menunggu scan karyawan).
  Future<AttendanceGeoUnlock?> fetchLatestForToko(String tokoId) async {
    if (tokoId.isEmpty) return null;

    if (TrainingMode.instance.isActive) {
      return _latestTrainingUnlock(tokoId: tokoId);
    }

    try {
      final res = await _client.rpc(
        'get_latest_attendance_geo_unlock_for_toko',
        params: {'p_toko_id': tokoId},
      );
      return _unlockFromRpc(res);
    } on PostgrestException catch (e) {
      throw _rpcMessage(e);
    }
  }

  /// Tandai unlock sudah diproses agar tidak memicu face match ulang.
  Future<void> consumeUnlock(String unlockId) async {
    if (unlockId.isEmpty) return;

    if (TrainingMode.instance.isActive) {
      await TrainingSandboxStore.instance.update(
        'attendance_geo_unlocks',
        {
          'consumed_at': DateTime.now().toIso8601String(),
          'expires_at': DateTime.now().toIso8601String(),
        },
        where: {'id': unlockId},
      );
      return;
    }

    try {
      await _client.rpc(
        'consume_attendance_geo_unlock',
        params: {'p_unlock_id': unlockId},
      );
    } on PostgrestException catch (e) {
      throw _rpcMessage(e);
    }
  }

  AttendanceGeoUnlock? _unlockFromRpc(dynamic res) {
    final map = _asMap(res);
    if (map == null) return null;
    if (map['valid'] != true) return null;
    if ((map['id'] ?? '').toString().isEmpty) return null;
    final unlock = AttendanceGeoUnlock.fromJson(map);
    return unlock.isValid ? unlock : null;
  }

  Future<AttendanceGeoUnlock?> _latestTrainingUnlock({
    required String tokoId,
    String? karyawanId,
  }) async {
    final where = <String, dynamic>{'toko_id': tokoId};
    if (karyawanId != null) where['karyawan_id'] = karyawanId;
    final rows = await TrainingSandboxStore.instance.select(
      'attendance_geo_unlocks',
      where: where,
      orderBy: 'created_at',
      ascending: false,
    );
    final now = DateTime.now();
    for (final row in rows) {
      if (row['consumed_at'] != null) continue;
      final u = AttendanceGeoUnlock.fromJson(row);
      if (u.expiresAt.isAfter(now)) return u;
    }
    return null;
  }

  Map<String, dynamic>? _asMap(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  String _rpcMessage(PostgrestException e) {
    final m = e.message.trim();
    if (m.isNotEmpty) return m;
    return e.details?.toString() ?? 'Gagal memproses verifikasi lokasi.';
  }
}
