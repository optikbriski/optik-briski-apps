import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'face_template.dart';

/// Bangun template lokal dari JPEG (mis. reference image AWS Face Liveness).
Future<List<double>?> faceTemplateFromJpeg(Uint8List jpegBytes) async {
  if (jpegBytes.length < 500) return null;

  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/aws_liveness_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  FaceDetector? detector;
  try {
    await file.writeAsBytes(jpegBytes, flush: true);
    detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    final faces = await detector.processImage(InputImage.fromFilePath(file.path));
    if (faces.isEmpty) return null;
    return FaceTemplateUtil.fromFace(faces.first);
  } catch (_) {
    return null;
  } finally {
    await detector?.close();
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
