import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Template geometri wajah ringan dari landmark ML Kit (bukan model enterprise).
class FaceTemplateUtil {
  FaceTemplateUtil._();

  /// Semakin kecil jarak, semakin mirip. Lolos jika < [matchThreshold].
  static const double matchThreshold = 0.12;

  static List<double>? fromFace(Face face) {
    final box = face.boundingBox;
    final w = box.width;
    final h = box.height;
    if (w < 40 || h < 40) return null;

    double nx(num x) => ((x - box.left) / w).clamp(0.0, 1.0);
    double ny(num y) => ((y - box.top) / h).clamp(0.0, 1.0);

    List<double>? xy(FaceLandmarkType type) {
      final lm = face.landmarks[type];
      if (lm == null) return null;
      return [nx(lm.position.x), ny(lm.position.y)];
    }

    final leftEye = xy(FaceLandmarkType.leftEye);
    final rightEye = xy(FaceLandmarkType.rightEye);
    final nose = xy(FaceLandmarkType.noseBase);
    final leftMouth = xy(FaceLandmarkType.leftMouth);
    final rightMouth = xy(FaceLandmarkType.rightMouth);
    final bottomMouth = xy(FaceLandmarkType.bottomMouth);

    if (leftEye == null || rightEye == null || nose == null) return null;

    return <double>[
      leftEye[0],
      leftEye[1],
      rightEye[0],
      rightEye[1],
      nose[0],
      nose[1],
      leftMouth?[0] ?? 0.35,
      leftMouth?[1] ?? 0.75,
      rightMouth?[0] ?? 0.65,
      rightMouth?[1] ?? 0.75,
      bottomMouth?[0] ?? 0.5,
      bottomMouth?[1] ?? 0.85,
      (w / h).clamp(0.5, 1.5),
      ((face.headEulerAngleY ?? 0) / 90).clamp(-1.0, 1.0),
      ((face.headEulerAngleZ ?? 0) / 90).clamp(-1.0, 1.0),
    ];
  }

  static double distance(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 999;
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sum / a.length;
  }

  static bool isMatch(
    List<double> enrolled,
    List<double> live, {
    double threshold = matchThreshold,
  }) {
    return distance(enrolled, live) <= threshold;
  }

  static List<double>? fromJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      return raw.map((e) => (e as num).toDouble()).toList();
    }
    return null;
  }
}
