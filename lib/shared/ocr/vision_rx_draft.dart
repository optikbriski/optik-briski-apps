/// Draf resep kacamata dari teks OCR (tulisan dokter). Manusia wajib cek.
class VisionRxDraft {
  const VisionRxDraft({
    required this.rawText,
    this.structured,
  });

  final String rawText;
  final String? structured;

  String get displayText =>
      (structured != null && structured!.trim().isNotEmpty)
          ? structured!.trim()
          : rawText.trim();

  static VisionRxDraft parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return const VisionRxDraft(rawText: '');
    final hasEye = RegExp(
      r'\b(od|os|kanan|kiri|right|left)\b|(?:^|\n)\s*[RL]\s*[:]',
      caseSensitive: false,
    ).hasMatch(text);
    if (!hasEye) return VisionRxDraft(rawText: text);
    final r = _eye(text, right: true);
    final l = _eye(text, right: false);
    final pd = _pd(text);
    if (r == null && l == null) {
      return VisionRxDraft(rawText: text);
    }
    final parts = <String>[
      if (r != null) 'R: $r',
      if (l != null) 'L: $l',
      if (pd != null) 'PD Pasien: $pd',
    ];
    return VisionRxDraft(rawText: text, structured: parts.join(' | '));
  }

  static String? _eye(String text, {required bool right}) {
    final labels = right
        ? ['\\bod\\b', '\\br\\b', 'kanan', 'right']
        : ['\\bos\\b', '\\bl\\b', 'kiri', 'left'];
    final block = _blockForEye(text, labels);
    if (block.isEmpty) return null;
    final sph = _power(block, ['sph', 's\\.ph', 'sphere']);
    final cyl = _power(block, ['cyl', 'c\\.yl', 'cylinder', 'sil']);
    final axis = _axis(block);
    final add = _power(block, ['add', 'addition']) ??
        _power(text, ['add', 'addition']);
    if (sph == null && cyl == null && add == null) return null;
    return 'SPH ${sph ?? '0.00'}/CYL ${cyl ?? '0.00'}/AXIS ${axis ?? '0'}/ADD ${add ?? '0.00'}';
  }

  static String _blockForEye(String text, List<String> labels) {
    final re = RegExp('(?:${labels.join('|')})', caseSensitive: false);
    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (re.hasMatch(line)) return line;
    }
    return '';
  }

  static String? _power(String block, List<String> keys) {
    final re = RegExp(
      '(?:${keys.join('|')})\\s*[=:]?\\s*([+-]?\\d{1,2}(?:[.,]\\d{1,2})?)',
      caseSensitive: false,
    );
    final m = re.firstMatch(block);
    if (m == null) return null;
    return _fmtPower(m.group(1)!);
  }

  static String? _axis(String block) {
    final re = RegExp(
      r'(?:axis|x)\s*[=:]?\s*(\d{1,3})\s*°?',
      caseSensitive: false,
    );
    final m = re.firstMatch(block);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null || n < 0 || n > 180) return null;
    return '$n';
  }

  static String? _pd(String text) {
    final re = RegExp(
      r'(?:pd|pupil)\s*[=:]?\s*(\d{2}(?:[./]\d{2})?)',
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    if (m == null) return null;
    final v = m.group(1)!.replaceAll('.', '/');
    return v.contains('/') ? '$v mm' : '$v mm';
  }

  static String _fmtPower(String raw) {
    var s = raw.replaceAll(',', '.');
    final n = double.tryParse(s);
    if (n == null) return raw;
    var t = n.toStringAsFixed(2);
    if (!t.startsWith('-') && !t.startsWith('+') && n != 0) {
      t = '+$t';
    }
    return t;
  }
}
