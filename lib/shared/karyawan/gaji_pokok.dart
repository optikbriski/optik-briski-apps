/// Gaji pokok karyawan (rupiah utuh, tanpa sen).
int parseGajiPokokInput(String? raw, {int fallback = 0}) {
  final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return fallback < 0 ? 0 : fallback;
  final n = int.tryParse(digits);
  if (n == null || n < 0) return fallback < 0 ? 0 : fallback;
  return n;
}

/// Isi field approve: kosong jika 0 supaya admin toko bisa biarkan 0.
String formatGajiPokokInput(Object? raw) {
  final n = parseGajiPokokInput(raw?.toString());
  return n == 0 ? '' : n.toString();
}
