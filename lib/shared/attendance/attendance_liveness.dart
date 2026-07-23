import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../liveness_camera_page.dart';
import 'attendance_config.dart';
import 'aws_face_liveness_page.dart';
import 'face_from_image.dart';
import 'liveness_result.dart';
import 'web_face_liveness_page.dart';

/// Capture liveness + face template (shared by Absensi pribadi & Absensi Toko).
Future<LivenessCaptureResult?> captureAttendanceLiveness(
  BuildContext context, {
  void Function(String message)? onInfo,
}) async {
  // Admin / kiosk di browser: challenge lokal + signature foto (tanpa AWS / ML Kit).
  if (kIsWeb) {
    final raw = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const WebFaceLivenessPage()),
    );
    final web = _asLiveness(raw);
    if (web == null) return null;
    return LivenessCaptureResult(
      success: web.success,
      photoBytes: web.photoBytes,
      faceTemplate: web.faceTemplate,
      livenessProvider: 'web',
      livenessConfidence: web.livenessConfidence ?? (web.success ? 70 : 0),
    );
  }

  if (AttendanceConfig.useAwsFaceLiveness) {
    final raw = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const AwsFaceLivenessPage()),
    );
    var result = _asLiveness(raw);
    if (result == null || !result.success) return result;

    if (result.faceTemplate == null && result.photoBytes != null) {
      final tpl = await faceTemplateFromJpeg(result.photoBytes!);
      if (tpl != null) {
        result = LivenessCaptureResult(
          success: true,
          photoBytes: result.photoBytes,
          faceTemplate: tpl,
          livenessProvider: result.livenessProvider,
          livenessSessionId: result.livenessSessionId,
          livenessConfidence: result.livenessConfidence,
        );
      }
    }
    if (result.faceTemplate == null) {
      if (!context.mounted) return null;
      onInfo?.call('aws_liveness_need_local_face');
      final localRaw = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(builder: (_) => const LivenessCameraPage()),
      );
      final local = _asLiveness(localRaw);
      if (local == null ||
          !local.success ||
          local.faceTemplate == null ||
          local.photoBytes == null) {
        return null;
      }
      return LivenessCaptureResult(
        success: true,
        photoBytes: local.photoBytes,
        faceTemplate: local.faceTemplate,
        livenessProvider: 'aws',
        livenessSessionId: result.livenessSessionId,
        livenessConfidence: result.livenessConfidence,
      );
    }
    return result;
  }

  final raw = await Navigator.push<Object?>(
    context,
    MaterialPageRoute(builder: (_) => const LivenessCameraPage()),
  );
  final local = _asLiveness(raw);
  if (local == null) return null;
  return LivenessCaptureResult(
    success: local.success,
    photoBytes: local.photoBytes,
    faceTemplate: local.faceTemplate,
    livenessProvider: 'local',
    livenessConfidence: local.success ? 100 : 0,
  );
}

LivenessCaptureResult? _asLiveness(Object? raw) {
  if (raw is LivenessCaptureResult) return raw;
  if (raw is bool) {
    return LivenessCaptureResult(
      success: raw,
      livenessProvider: 'local',
      livenessConfidence: raw ? 100 : 0,
    );
  }
  return null;
}
