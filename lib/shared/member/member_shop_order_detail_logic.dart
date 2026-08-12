// Pure helpers for MemberShopOrderDetailPage (unit-tested).

/// Pilih tarif default: pertahankan [keepId] bila masih ada,
/// else OBR termurah, else opsi termurah apa pun.
Map<String, dynamic>? pickDefaultShippingRate(
  List<Map<String, dynamic>> groups, {
  String? keepId,
}) {
  if (keepId != null && keepId.isNotEmpty) {
    for (final g in groups) {
      final opts = g['options'];
      if (opts is! List) continue;
      for (final o in opts) {
        if (o is Map && o['id']?.toString() == keepId) {
          return Map<String, dynamic>.from(o);
        }
      }
    }
  }

  Map<String, dynamic>? bestObr;
  Map<String, dynamic>? bestAny;
  for (final g in groups) {
    final opts = g['options'];
    if (opts is! List) continue;
    for (final o in opts) {
      if (o is! Map) continue;
      final m = Map<String, dynamic>.from(o);
      final p = int.tryParse('${m['price']}') ?? 0;
      if (bestAny == null ||
          p < (int.tryParse('${bestAny['price']}') ?? 1 << 30)) {
        bestAny = m;
      }
      if (m['is_obr'] == true) {
        if (bestObr == null ||
            p < (int.tryParse('${bestObr['price']}') ?? 1 << 30)) {
          bestObr = m;
        }
      }
    }
  }
  return bestObr ?? bestAny;
}

/// Apakah tombol "Lanjut bayar" harus di-disable.
///
/// - Tanpa item terpilih → block.
/// - Delivery tanpa alamat → jangan block (buka picker).
/// - Delivery sedang muat tarif → block.
/// - Delivery gagal tarif (error, groups kosong) → jangan block (tap = retry).
/// - Delivery tanpa rate valid → block.
bool memberShopOrderDetailPayBlocked({
  required bool hasSelection,
  required bool isDelivery,
  required bool addressConfirmed,
  required bool loadingRates,
  required bool hasSelectedRate,
  required bool hasRateGroups,
  required bool hasRateError,
}) {
  if (!hasSelection) return true;
  if (!isDelivery) return false;
  if (!addressConfirmed) return false;
  if (loadingRates) return true;
  if (hasRateError && !hasRateGroups) return false;
  return !hasSelectedRate || !hasRateGroups;
}

/// Cabang boleh dipakai untuk ambil di toko.
bool storeAllowsPickup(Map<String, dynamic>? store) {
  if (store == null) return false;
  return store['pickup_enabled'] != false;
}
