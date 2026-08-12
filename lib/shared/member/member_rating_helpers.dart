/// Pure helpers for Member Rating list / eligibility (unit-tested).
class MemberRatingHelpers {
  MemberRatingHelpers._();

  static bool bisaRating(Map<String, dynamic> row) {
    if (row['bisa_rating'] == true) return true;
    if (row['diambil_at'] != null) return true;
    return (row['tracking_status']?.toString().toUpperCase() ?? '') == 'DIAMBIL';
  }

  static bool hasRatingKasir(Map<String, dynamic> row) {
    if (row['has_rating_kasir'] == true) return true;
    return row['rating_kasir'] is Map;
  }

  static bool hasRatingPembuat(Map<String, dynamic> row) {
    if (row['has_rating_pembuat'] == true) return true;
    return row['rating_pembuat'] is Map;
  }

  static bool kasirAssigned(Map<String, dynamic> row) {
    if (row['kasir_assigned'] == true) return true;
    if ((row['kasir_karyawan_id'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    return (row['nama_kasir'] ?? '').toString().trim().isNotEmpty;
  }

  static bool pembuatAssigned(Map<String, dynamic> row) {
    if (row['pembuat_assigned'] == true) return true;
    if ((row['pembuat_kacamata_id'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    return (row['nama_pembuat_kacamata'] ?? '').toString().trim().isNotEmpty;
  }

  /// Pending if taken and at least one assigned role still missing a rating.
  static bool isPendingToRate(Map<String, dynamic> row) {
    if (!bisaRating(row)) return false;
    final needKasir = kasirAssigned(row) && !hasRatingKasir(row);
    final needPembuat = pembuatAssigned(row) && !hasRatingPembuat(row);
    // Belum ada assign sama sekali → tetap tampil di pending supaya member tahu.
    if (!kasirAssigned(row) && !pembuatAssigned(row)) return true;
    return needKasir || needPembuat;
  }

  static bool isHistory(Map<String, dynamic> row) {
    if (!bisaRating(row)) return false;
    return hasRatingKasir(row) || hasRatingPembuat(row);
  }

  static bool isComplete(Map<String, dynamic> row) {
    if (!bisaRating(row)) return false;
    final kasirOk = !kasirAssigned(row) || hasRatingKasir(row);
    final pembuatOk = !pembuatAssigned(row) || hasRatingPembuat(row);
    return kasirOk && pembuatOk && (hasRatingKasir(row) || hasRatingPembuat(row));
  }

  static List<Map<String, dynamic>> pendingOnly(List<Map<String, dynamic>> rows) {
    return rows.where(isPendingToRate).toList();
  }

  static List<Map<String, dynamic>> historyOnly(List<Map<String, dynamic>> rows) {
    return rows.where(isHistory).toList();
  }
}
