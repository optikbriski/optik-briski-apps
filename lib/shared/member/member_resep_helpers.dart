/// Helpers Resep Member — filter riwayat + validasi nilai optik (SPH/CYL/AXIS/ADD).
///
/// Sumber data: `sales_items.detail_resep` dari nota (bukan CRUD mandiri Member).
class MemberResepHelpers {
  MemberResepHelpers._();

  static final _powerRe = RegExp(
    r'^[+-]?(?:\d{1,2}(?:\.(?:00|25|50|75))?|\d(?:\.(?:00|25|50|75))?)$',
  );

  /// Item layak tampil di daftar Resep (bukan kosong / "Normal").
  static bool isMeaningfulResep(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    if (lower == 'normal' || lower == '-' || lower == 'n/a') return false;
    return true;
  }

  /// Format POS standar: `R: SPH … | L: SPH … | PD Pasien: …`
  static bool isStructuredResep(String? raw) {
    if (!isMeaningfulResep(raw)) return false;
    final t = raw!.trim();
    if (!t.contains('|')) return false;
    final u = t.toUpperCase();
    return u.contains('SPH') && (u.contains('R:') || u.contains('L:'));
  }

  static bool isValidSph(String? raw) => _validPower(raw, min: -20, max: 20);

  static bool isValidCyl(String? raw) => _validPower(raw, min: -6, max: 6);

  /// ADD progresif / bifokal: 0 … +4.00 (step 0.25).
  static bool isValidAdd(String? raw) => _validPower(raw, min: 0, max: 4);

  /// AXIS 0–180. Wajib jika CYL tidak nol; jika CYL 0/kosong, kosong atau 0 OK.
  static bool isValidAxis(String? raw, {String? cyl}) {
    final cylN = _parsePower(cyl);
    final axisRaw = (raw ?? '').trim().replaceAll('°', '');
    if (cylN == null || cylN == 0) {
      if (axisRaw.isEmpty || axisRaw == '-' || axisRaw == '0' || axisRaw == '0.00') {
        return true;
      }
    }
    if (axisRaw.isEmpty) return false;
    final n = int.tryParse(axisRaw);
    if (n == null) return false;
    return n >= 0 && n <= 180;
  }

  static bool _validPower(String? raw, {required double min, required double max}) {
    final t = (raw ?? '').trim();
    if (t.isEmpty || t == '-') return false;
    if (!_powerRe.hasMatch(t)) return false;
    final n = _parsePower(t);
    if (n == null) return false;
    if (n < min || n > max) return false;
    // Step 0.25
    final steps = (n * 100).round();
    return steps % 25 == 0;
  }

  static double? _parsePower(String? raw) {
    final t = (raw ?? '').trim().replaceAll('°', '');
    if (t.isEmpty || t == '-') return null;
    return double.tryParse(t);
  }
}
