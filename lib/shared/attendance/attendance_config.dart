/// Feature flags absensi wajah.
class AttendanceConfig {
  AttendanceConfig._();

  /// AWS Face Liveness — dimatikan (Admin web pakai liveness browser lokal).
  static const bool useAwsFaceLiveness = false;

  /// Ambang legacy AWS (tidak dipakai saat [useAwsFaceLiveness] = false).
  static const double minLivenessConfidence = 90;

  /// Face match lokal: ML Kit di Android; di web pakai [WebFaceSignature] + foto enroll.
  static const bool useLocalFaceMatch = true;

  /// AWS CompareFaces — dimatikan; tidak butuh secrets AWS untuk Absensi Toko.
  static const bool useAwsFaceCompare = false;

  static const String edgeFunctionName = 'aws-face-liveness';

  /// Face match clock-in/out hanya di perangkat toko (Admin tablet / kiosk / web Admin),
  /// bukan di HP pribadi karyawan. Enroll wajah tetap boleh di HP karyawan.
  static const bool faceMatchOnStoreDeviceOnly = true;

  /// Di mode kiosk toko, QR Admin tidak diperlukan (perangkat sudah di toko).
  static const bool kioskSkipAdminQr = true;

  /// Masa hidup token QR absensi di layar Admin (detik).
  /// Pendek agar QR tidak sempat dikirim ke luar toko.
  /// (Legacy / cadangan jika faceMatchOnStoreDeviceOnly = false.)
  static const int qrTtlSeconds = 5;

  /// Interval rotasi QR di layar Admin (sama dengan TTL).
  static const int qrRotateSeconds = 5;
}
