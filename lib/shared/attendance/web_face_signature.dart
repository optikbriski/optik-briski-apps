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

  /// Rata-rata |Δ| (jarak) setelah normalisasi; semakin kecil semakin mirip.
  /// Ambang longgar: signature grid 16×16 lemah vs cahaya / mirror kamera depan.
  static const double matchThreshold = 0.30;

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

  /// Mirror horizontal grid (kamera depan sering terbalik vs foto enroll).
  static List<double> flipHorizontal(List<double> v) {
    if (!isWebVector(v)) return v;
    final out = List<double>.filled(vectorLength, 0);
    for (var gy = 0; gy < gridSize; gy++) {
      for (var gx = 0; gx < gridSize; gx++) {
        out[gy * gridSize + gx] = v[gy * gridSize + (gridSize - 1 - gx)];
      }
    }
    return out;
  }

  /// Jarak terbaik antara live vs enrolled, termasuk mirror horizontal.
  static double bestDistance(List<double> enrolled, List<double> live) {
    final d = distance(enrolled, live);
    final dFlip = distance(enrolled, flipHorizontal(live));
    return d < dFlip ? d : dFlip;
  }

  static bool isMatch(
    List<double> enrolled,
    List<double> live, {
    double threshold = matchThreshold,
  }) {
    return bestDistance(enrolled, live) <= threshold;
  }

  /// Perubahan frame (liveness gerak kepala): jarak antar signature.
  static double motionScore(List<double>? a, List<double>? b) {
    if (a == null || b == null) return 0;
    return distance(a, b);
  }

  /// Pusat massa horisontal dari signature ternormalisasi (0 kiri … 1 kanan).
  static double horizontalCenter(List<double> sig) {
    if (!isWebVector(sig)) return 0.5;
    var sumW = 0.0;
    var sumX = 0.0;
    for (var gy = 0; gy < gridSize; gy++) {
      for (var gx = 0; gx < gridSize; gx++) {
        final w = sig[gy * gridSize + gx] + 3.5;
        sumW += w;
        sumX += gx * w;
      }
    }
    if (sumW <= 0) return 0.5;
    return (sumX / sumW) / (gridSize - 1);
  }

  /// Pusat massa vertikal (0 atas … 1 bawah).
  static double verticalCenter(List<double> sig) {
    if (!isWebVector(sig)) return 0.5;
    var sumW = 0.0;
    var sumY = 0.0;
    for (var gy = 0; gy < gridSize; gy++) {
      for (var gx = 0; gx < gridSize; gx++) {
        final w = sig[gy * gridSize + gx] + 3.5;
        sumW += w;
        sumY += gy * w;
      }
    }
    if (sumW <= 0) return 0.5;
    return (sumY / sumW) / (gridSize - 1);
  }

  /// Pose dari JPEG mentah (luma belum dinormalisasi) — lebih stabil untuk arah gerak.
  static Future<WebFacePose?> poseFromJpeg(Uint8List jpegBytes) async {
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
          for (var y = y0; y < y1; y += 2) {
            for (var x = x0; x < x1; x += 2) {
              final i = (y * w + x) * 4;
              if (i + 2 >= rgba.length) continue;
              sum +=
                  0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
              n++;
            }
          }
          raw[gy * gridSize + gx] = n == 0 ? 0 : (sum / n) / 255.0;
        }
      }

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

      final sig =
          raw.map((v) => ((v - mean) / std).clamp(-3.0, 3.0)).toList();

      // Pusat massa pakai luma mentah (bukan z-score).
      var sumW = 0.0;
      var sumX = 0.0;
      var sumY = 0.0;
      for (var gy = 0; gy < gridSize; gy++) {
        for (var gx = 0; gx < gridSize; gx++) {
          final wgt = raw[gy * gridSize + gx] + 0.05;
          sumW += wgt;
          sumX += gx * wgt;
          sumY += gy * wgt;
        }
      }
      final hx = sumW <= 0 ? 0.5 : (sumX / sumW) / (gridSize - 1);
      final vy = sumW <= 0 ? 0.5 : (sumY / sumW) / (gridSize - 1);

      return WebFacePose(
        signature: sig,
        horizontal: hx,
        vertical: vy,
        meanLuma: mean,
      );
    } catch (_) {
      return null;
    }
  }

  /// Rata-rata luma area wajah (0–1). Dipakai cek soft flash warna layar.
  static Future<double?> meanLuma(Uint8List jpegBytes) async {
    final pose = await poseFromJpeg(jpegBytes);
    return pose?.meanLuma;
  }
}

/// Sampel pose wajah untuk cek arah gerakan (benar / salah).
class WebFacePose {
  const WebFacePose({
    required this.signature,
    required this.horizontal,
    required this.vertical,
    required this.meanLuma,
  });

  final List<double> signature;
  /// 0 = kiri frame, 1 = kanan frame.
  final double horizontal;
  /// 0 = atas frame, 1 = bawah frame.
  final double vertical;
  final double meanLuma;
}
