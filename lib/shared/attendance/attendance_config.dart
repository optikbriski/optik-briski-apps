/// Feature flags absensi wajah.
class AttendanceConfig {
  AttendanceConfig._();

  /// true = wajib lewat AWS Rekognition Face Liveness (Edge Function).
  /// false = liveness lokal (senyum ML Kit). Default OFF sampai AWS siap.
  static const bool useAwsFaceLiveness = false;

  /// Ambang default di client; server memakai AWS_LIVENESS_MIN_CONFIDENCE.
  static const double minLivenessConfidence = 90;

  /// Setelah liveness AWS lolos, cocokkan wajah lewat template lokal (ML Kit).
  static const bool useLocalFaceMatch = true;

  /// Opsional: panggil Edge Function aws-rekognition compare setelah liveness.
  static const bool useAwsFaceCompare = false;

  static const String edgeFunctionName = 'aws-face-liveness';

  /// Masa hidup token QR absensi di layar Admin (detik).
  /// Pendek agar QR tidak sempat dikirim ke luar toko.
  static const int qrTtlSeconds = 5;

  /// Interval rotasi QR di layar Admin (sama dengan TTL).
  static const int qrRotateSeconds = 5;
}
