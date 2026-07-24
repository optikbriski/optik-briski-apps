/// Feature flags absensi wajah.
class AttendanceConfig {
  AttendanceConfig._();

  /// AWS Face Liveness — dimatikan (Admin web pakai liveness browser lokal).
  static const bool useAwsFaceLiveness = false;

  /// Ambang legacy AWS (tidak dipakai saat [useAwsFaceLiveness] = false).
  static const double minLivenessConfidence = 90;

  /// Face match lokal (ML Kit) — hanya path non-kiosk / non-web (jarang dipakai).
  /// Absensi Toko Admin (web + storeKiosk) tidak memakai face match;
  /// cukup liveness + foto untuk tinjauan Monitor.
  static const bool useLocalFaceMatch = true;

  /// Legacy: tolak clock-in web jika signature di atas ambang.
  /// Diabaikan — path web/kiosk selalu skip face match (lihat AttendanceService).
  static const bool strictWebFaceMatch = false;

  /// AWS CompareFaces — dimatikan; tidak butuh secrets AWS untuk Absensi Toko.
  static const bool useAwsFaceCompare = false;

  static const String edgeFunctionName = 'aws-face-liveness';

  /// Face match clock-in/out hanya di perangkat toko (Admin tablet / kiosk / web Admin),
  /// bukan di HP pribadi karyawan. Enroll wajah tetap boleh di HP karyawan.
  static const bool faceMatchOnStoreDeviceOnly = true;

  /// Absensi Toko Admin wajib punya geo unlock aktif dari HP karyawan
  /// (scan QR Absensi + GPS di geofence) sebelum face match masuk /
  /// auto pulang tanpa wajah.
  static const bool requireKaryawanGeoUnlock = true;

  /// Masa hidup bukti lokasi (detik) setelah karyawan scan QR + GPS OK.
  /// Admin harus menyelesaikan face match sebelum ini habis (~2–5 menit).
  static const int geoUnlockTtlSeconds = 180;

  /// Di mode kiosk toko, QR Admin tidak dipakai sebagai syarat face match di
  /// perangkat Admin (bukti lokasi datang dari unlock HP karyawan).
  static const bool kioskSkipAdminQr = true;

  /// Masa hidup token QR absensi di layar Admin (detik).
  /// Pendek agar QR tidak sempat dikirim ke luar toko.
  /// Dipakai karyawan untuk membuka geo unlock (bukan clock-in wajah di HP).
  static const int qrTtlSeconds = 5;

  /// Interval rotasi QR di layar Admin (sama dengan TTL).
  static const int qrRotateSeconds = 5;
}
