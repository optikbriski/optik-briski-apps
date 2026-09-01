import 'vision_table_grid.dart';

/// Draf klaim dari teks OCR — manusia wajib cek sebelum kirim.
class VisionReceiptDraft {
  const VisionReceiptDraft({
    required this.text,
    this.amountRp,
    this.merchant,
    this.suggestedKategori = 'Lainnya',
    this.tokens = const [],
  });

  final String text;
  final int? amountRp;
  final String? merchant;
  final String suggestedKategori;
  final List<VisionOcrToken> tokens;

  static const kategoriBensin = 'Bensin';
  static const kategoriParkir = 'Parkir';
  static const kategoriSpare = 'Spare / alat';
  static const kategoriLainnya = 'Lainnya';

  static const int minAmount = 500;
  static const int maxAmount = 20000000;

  String get catatanDraft {
    final lines = <String>[];
    final m = merchant?.trim();
    if (m != null && m.isNotEmpty) lines.add(m);
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (m != null && line.toLowerCase() == m.toLowerCase()) continue;
      if (_looksLikeAmountLine(line)) continue;
      if (_isNoiseLine(line)) continue;
      lines.add(line);
      if (lines.join('\n').length >= 240) break;
    }
    final out = lines.join('\n').trim();
    if (out.isNotEmpty) {
      return out.length <= 240 ? out : out.substring(0, 240).trim();
    }
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '';
    return compact.length <= 240 ? compact : compact.substring(0, 240).trim();
  }

  static VisionReceiptDraft parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) {
      return const VisionReceiptDraft(text: '');
    }
    return VisionReceiptDraft(
      text: text,
      amountRp: _pickAmount(text),
      merchant: _pickMerchant(text),
      suggestedKategori: _pickKategori(text),
    );
  }

  VisionReceiptDraft withTokens(List<VisionOcrToken> next) {
    return VisionReceiptDraft(
      text: text,
      amountRp: amountRp,
      merchant: merchant,
      suggestedKategori: suggestedKategori,
      tokens: next,
    );
  }

  static int? parseIdrAmount(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'(rp\.?|idr)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;

    final id = RegExp(r'^(\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?$');
    final us = RegExp(r'^(\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$');
    final idMatch = id.firstMatch(s);
    if (idMatch != null) {
      return int.tryParse(idMatch.group(1)!.replaceAll('.', ''));
    }
    final usMatch = us.firstMatch(s);
    if (usMatch != null) {
      return int.tryParse(usMatch.group(1)!.replaceAll(',', ''));
    }
    final plain = RegExp(r'^(\d{3,9})(?:[.,]\d{1,2})?$');
    final p = plain.firstMatch(s);
    if (p != null) return int.tryParse(p.group(1)!);
    return null;
  }

  static int? _pickAmount(String text) {
    final scored = <({int amount, int score})>[];
    final lineRe = RegExp(
      r'(?:rp\.?|idr)?\s*([0-9]{1,3}(?:[.\s][0-9]{3})+(?:,[0-9]{1,2})?|[0-9]{3,9}(?:[.,][0-9]{1,2})?)',
      caseSensitive: false,
    );

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      var lineScore = 0;
      if (RegExp(r'total|grand|jumlah|bayar|netto|harga').hasMatch(lower)) {
        lineScore += 8;
      }
      if (RegExp(r'\brp\b|idr').hasMatch(lower)) lineScore += 3;
      if (RegExp(r'subtotal|pajak|ppn|diskon|kembalian|change').hasMatch(lower)) {
        lineScore -= 4;
      }

      for (final m in lineRe.allMatches(line)) {
        final amount = parseIdrAmount(m.group(1)!);
        if (amount == null) continue;
        if (amount < minAmount || amount > maxAmount) continue;
        scored.add((amount: amount, score: lineScore));
      }
    }

    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.amount.compareTo(a.amount);
    });
    return scored.first.amount;
  }

  static String? _pickMerchant(String text) {
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_isNoiseLine(line)) continue;
      if (_looksLikeAmountLine(line)) continue;
      if (line.length < 3) continue;
      return line.length <= 80 ? line : line.substring(0, 80).trim();
    }
    return null;
  }

  static String _pickKategori(String text) {
    final t = text.toLowerCase();
    if (RegExp(
      r'parkir|parking|valet',
    ).hasMatch(t)) {
      return kategoriParkir;
    }
    if (RegExp(
      r'bensin|pertamina|pertamax|pertalite|shell|spbu|solar|dexlite|bbm',
    ).hasMatch(t)) {
      return kategoriBensin;
    }
    if (RegExp(
      r'spare|sparepart|oli mesin|alat|sekrup|kunci pas',
    ).hasMatch(t)) {
      return kategoriSpare;
    }
    return kategoriLainnya;
  }

  static bool _looksLikeAmountLine(String line) {
    return parseIdrAmount(line) != null ||
        RegExp(r'(rp\.?|idr)\s*\d', caseSensitive: false).hasMatch(line);
  }

  static bool _isNoiseLine(String line) {
    final lower = line.toLowerCase();
    if (RegExp(r'^(struk|nota|receipt|invoice|kasir)$').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'npwp|nik\b|telp|telepon|www\.|https?://').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^\d{1,2}[/\-.\s]\d{1,2}[/\-.\s]\d{2,4}$').hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^[\d\s./:-]+$').hasMatch(line)) return true;
    return false;
  }
}
