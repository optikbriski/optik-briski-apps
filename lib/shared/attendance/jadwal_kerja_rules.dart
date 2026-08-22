/// Aturan roster + pengajuan ijin — dipakai UI dan tes, bukan pengganti RLS.
abstract final class JadwalKerjaRules {
  static const minKuota = 0;
  static const maxKuota = 40;
  static const maxCatatanChars = 500;

  static const allowedTipe = {'IJIN', 'CUTI', 'TUKAR'};
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';

  static String tipeOf(String? raw) => (raw ?? '').trim().toUpperCase();

  static String statusOf(String? raw) => (raw ?? '').trim().toUpperCase();

  static bool isAllowedTipe(String? raw) => allowedTipe.contains(tipeOf(raw));

  static bool isPending(String? raw) => statusOf(raw) == pending;

  static bool isTerminal(String? raw) {
    final s = statusOf(raw);
    return s == approved || s == rejected || s == cancelled;
  }

  /// Karyawan hanya boleh batal saat masih antrean.
  static bool canCancel(String? status) => isPending(status);

  /// Admin hanya memutus antrean. Bukan buka ulang yang sudah diputus.
  static bool canDecide(String? status) => isPending(status);

  static bool isValidTime(String? raw) {
    final t = (raw ?? '').trim();
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(t)) return false;
    final h = int.tryParse(t.substring(0, 2));
    final m = int.tryParse(t.substring(3, 5));
    if (h == null || m == null) return false;
    return h >= 0 && h <= 23 && m >= 0 && m <= 59;
  }

  static int clampKuota(int n) {
    if (n < minKuota) return minKuota;
    if (n > maxKuota) return maxKuota;
    return n;
  }
}
