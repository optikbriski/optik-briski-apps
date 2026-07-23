/// Konstanta poin verifikasi absensi wajah (Admin).
///
/// Terpisah dari klaim SOP harian (`sumber: SOP`).
/// Poin Valid/Aman memakai `sumber: ABSEN` di `poin_logs`.
/// Hukuman curang: -200 poin + SP1 — **bukan** untuk keterlambatan.
abstract final class AttendanceVerificationConfig {
  /// Poin harian saat Admin menandai absen wajah Valid / Aman.
  /// (Belum ada aturan ABSEN di produk lama; nilai ini didokumentasikan di sini.)
  static const int validDayPoints = 20;

  /// Penalti poin jika terbukti curang (foto/liveness tidak sah).
  static const int cheatingPenaltyPoints = -200;

  /// Tingkat SP untuk kecurangan absensi wajah.
  static const int cheatingSpTingkat = 1;

  static const String sumberPoinAbsen = 'ABSEN';
  static const String sumberSpCurang = 'ABSEN_CURANG';
}
