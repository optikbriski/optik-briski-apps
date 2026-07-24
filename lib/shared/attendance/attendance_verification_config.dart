/// Konstanta poin verifikasi absensi wajah (Admin).
///
/// **Poin belum ada sebelum Admin verifikasi** (pending/mencurigakan = 0).
/// Saat verifikasi, satu jalur saja (jangan digabung):
/// - **Ontime + Valid** → `ABSEN` +20
/// - **Telat + Valid** → `ABSEN_TELAT` saja (tanpa +20)
/// - **Curang** → −200 saja (hapus ontime/telat event ini)
///
/// Terpisah dari klaim SOP harian (`sumber: SOP`).
abstract final class AttendanceVerificationConfig {
  /// Poin ontime saat Admin menandai absen wajah Valid / Aman (bukan telat).
  static const int validDayPoints = 20;

  /// Penalti poin jika terbukti curang (foto/liveness tidak sah).
  static const int cheatingPenaltyPoints = -200;

  /// Tingkat SP untuk kecurangan absensi wajah.
  static const int cheatingSpTingkat = 1;

  static const String sumberPoinAbsen = 'ABSEN';
  static const String sumberSpCurang = 'ABSEN_CURANG';
}
