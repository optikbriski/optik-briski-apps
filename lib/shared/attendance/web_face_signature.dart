import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Fingerprint wajah ringan untuk browser (tanpa ML Kit / AWS).
///
/// Crop area tengah (perkiraan oval), downsample ke grid abu-abu, normalisasi.
/// Lebih lemah dari model biometrik — cukup untuk anti-salah-pilih karyawan kasual.
class WebFaceSignature {
  WebFaceSignature._();

  static const int gridSize = 16;
  static const int vectorLength = gridSize * gridSize;

  /// Rata-rata |Δ| setelah normalisasi; semakin kecil semakin mirip.
  static const double matchThreshold = 0.14;

  /// Minimal kontras (std) agar frame tidak hitam/kosong.
  static const double minContrast = 0.04;

  static bool isWebVector(List<double>? v) =>
      v != null && v.length == vectorLength;

  static Future<List<double>?> fromJpeg(Uint8List jpegBytes) async {
    if (jpegBytes.length < 500) return null;
    try {
      final codec = await ui.instantiateImageCodec(jpegBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        image.dispose();
        return null;
      }
      final w = image.width;
      final h = image.height;
      image.dispose();
      if (w < 48 || h < 48) return null;

      final rgba = byteData.buffer.asUint8List();
      // Crop tengah ~62% (area oval wajah).
      final side = (math.min(w, h) * 0.62).round().clamp(32, math.min(w, h));
      final left = ((w - side) / 2).round();
      final top = ((h - side) / 2).round();

      final raw = List<double>.filled(vectorLength, 0);
      final cell = side / gridSize;
      for (var gy = 0; gy < gridSize; gy++) {
        for (var gx = 0; gx < gridSize; gx++) {
          var sum = 0.0;
          var n = 0;
          final x0 = left + (gx * cell).floor();
          final y0 = top + (gy * cell).floor();
          final x1 = left + ((gx + 1) * cell).ceil().clamp(0, w);
          final y1 = top + ((gy + 1) * cell).ceil().clamp(0, h);
          for (var y = y0; y < y1; y++) {
            for (var x = x0; x < x1; x++) {
              final i = (y * w + x) * 4;
              if (i + 2 >= rgba.length) continue;
              // Luma kasar.
              sum += 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
              n++;
            }
          }
          raw[gy * gridSize + gx] = n == 0 ? 0 : (sum / n) / 255.0;
        }
      }

      // Normalisasi mean/std agar pencahayaan beda tidak merusak match.
      var mean = 0.0;
      for (final v in raw) {
        mean += v;
      }
      mean /= raw.length;
      var variance = 0.0;
      for (final v in raw) {
        final d = v - mean;
        variance += d * d;
      }
      final std = math.sqrt(variance / raw.length);
      if (std < minContrast) return null;

      return raw.map((v) => ((v - mean) / std).clamp(-3.0, 3.0)).toList();
    } catch (_) {
      return null;
    }
  }

  static double distance(List<double> a, List<double> b) {
    if (!isWebVector(a) || !isWebVector(b)) return 999;
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += (a[i] - b[i]).abs();
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

  /// Perubahan frame (liveness gerak kepala): jarak antar signature.
  static double motionScore(List<double>? a, List<double>? b) {
    if (a == null || b == null) return 0;
    return distance(a, b);
  }
}
