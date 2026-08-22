/// Uang yang sudah masuk dari nota POS — bukan omzet bruto.
///
/// Sama dengan buku besar: `total_harga - sisa_tagihan`.
/// Sisa DP / piutang tidak dihitung. Nota `BATAL` = 0.
int uangMasukDariSale(Map<String, dynamic> sale) {
  final status = (sale['status_pembayaran'] ?? '').toString().toUpperCase();
  if (status == 'BATAL') return 0;
  final total = _asInt(sale['total_harga']);
  final sisa = _asInt(sale['sisa_tagihan']);
  final masuk = total - sisa;
  return masuk < 0 ? 0 : masuk;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString().split('.').first ?? '') ?? 0;
}

/// Rentang lokal: hari ini, atau bulan kalender berjalan.
({DateTime start, DateTime endExclusive}) omzetRangeLokal({
  required bool bulanIni,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  if (bulanIni) {
    final start = DateTime(n.year, n.month, 1);
    return (start: start, endExclusive: DateTime(n.year, n.month + 1, 1));
  }
  final start = DateTime(n.year, n.month, n.day);
  return (start: start, endExclusive: start.add(const Duration(days: 1)));
}

bool saleDalamRentangLokal(
  Map<String, dynamic> sale, {
  required DateTime start,
  required DateTime endExclusive,
}) {
  final raw = sale['created_at']?.toString();
  if (raw == null || raw.isEmpty) return false;
  final created = DateTime.tryParse(raw)?.toLocal();
  if (created == null) return false;
  return !created.isBefore(start) && created.isBefore(endExclusive);
}
