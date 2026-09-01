/// Kata hasil Cloud Vision + posisi (0–1, kiri-atas → kanan-bawah).
class VisionOcrToken {
  const VisionOcrToken({
    required this.text,
    required this.cx,
    required this.cy,
    this.x0 = 0,
    this.x1 = 0,
    this.y0 = 0,
    this.y1 = 0,
  });

  final String text;
  final double cx;
  final double cy;
  final double x0;
  final double x1;
  final double y0;
  final double y1;

  static List<VisionOcrToken> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <VisionOcrToken>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final text = (m['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      out.add(
        VisionOcrToken(
          text: text,
          cx: _n(m['cx']),
          cy: _n(m['cy']),
          x0: _n(m['x0']),
          x1: _n(m['x1']),
          y0: _n(m['y0']),
          y1: _n(m['y1']),
        ),
      );
    }
    return out;
  }

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}

/// Susun token Vision ke grid kolom yang ditentukan user.
class VisionTableGrid {
  static const minColumns = 2;
  static const maxColumns = 8;

  static List<List<String>> fromTokens({
    required List<VisionOcrToken> tokens,
    required int columns,
    bool skipFirstRow = false,
  }) {
    final cols = columns.clamp(minColumns, maxColumns);
    final usable = tokens
        .where((t) => t.text.trim().isNotEmpty)
        .toList();
    if (usable.isEmpty) {
      return [List<String>.filled(cols, '')];
    }

    usable.sort((a, b) {
      final y = a.cy.compareTo(b.cy);
      if (y != 0) return y;
      return a.cx.compareTo(b.cx);
    });

    final heights = usable
        .map((t) => (t.y1 - t.y0).abs())
        .where((h) => h > 0.002)
        .toList()
      ..sort();
    final medianH =
        heights.isEmpty ? 0.022 : heights[heights.length ~/ 2];
    final rowGap = (medianH * 0.7).clamp(0.012, 0.05);

    final bands = <List<VisionOcrToken>>[];
    for (final t in usable) {
      if (bands.isEmpty) {
        bands.add([t]);
        continue;
      }
      final last = bands.last;
      var sumY = 0.0;
      for (final e in last) {
        sumY += e.cy;
      }
      final lastY = sumY / last.length;
      if ((t.cy - lastY).abs() <= rowGap) {
        last.add(t);
      } else {
        bands.add([t]);
      }
    }

    var minX = 1.0;
    var maxX = 0.0;
    for (final t in usable) {
      final left = t.x0 != 0 ? t.x0 : t.cx;
      final right = t.x1 != 0 ? t.x1 : t.cx;
      if (left < minX) minX = left;
      if (right > maxX) maxX = right;
    }
    var span = maxX - minX;
    if (span < 0.12) {
      minX = 0;
      span = 1;
    }

    List<String> pack(List<VisionOcrToken> row) {
      final buckets = List.generate(cols, (_) => <VisionOcrToken>[]);
      for (final t in row) {
        var rel = (t.cx - minX) / span;
        if (rel.isNaN || rel.isInfinite) rel = 0;
        var i = (rel * cols).floor();
        if (i < 0) i = 0;
        if (i >= cols) i = cols - 1;
        buckets[i].add(t);
      }
      return [
        for (final cell in buckets)
          (List<VisionOcrToken>.from(cell)
                ..sort((a, b) => a.cx.compareTo(b.cx)))
              .map((e) => e.text.trim())
              .where((s) => s.isNotEmpty)
              .join(' '),
      ];
    }

    var grid = [for (final row in bands) pack(row)];
    if (skipFirstRow && grid.isNotEmpty) {
      grid = grid.sublist(1);
    }
    grid = [
      for (final row in grid)
        if (row.any((c) => c.trim().isNotEmpty)) row,
    ];
    if (grid.isEmpty) {
      return [List<String>.filled(cols, '')];
    }
    return grid;
  }

  /// Cadangan kalau token posisi tidak ada: pecah baris + spasi.
  static List<List<String>> fromPlainText(String text, int columns) {
    final cols = columns.clamp(minColumns, maxColumns);
    final lines = [
      for (final raw in text.split(RegExp(r'\r?\n')))
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    if (lines.isEmpty) return [List<String>.filled(cols, '')];
    return [
      for (final line in lines) _splitLine(line, cols),
    ];
  }

  static List<String> _splitLine(String line, int cols) {
    var parts = line.split(RegExp(r'\t+|\s{2,}'));
    if (parts.length == 1 && cols > 1) {
      parts = line.split(RegExp(r'\s+'));
    }
    if (parts.length > cols) {
      parts = [
        ...parts.sublist(0, cols - 1),
        parts.sublist(cols - 1).join(' '),
      ];
    }
    return [for (var i = 0; i < cols; i++) i < parts.length ? parts[i] : ''];
  }

  static String toTsv(List<String> headers, List<List<String>> rows) {
    String esc(String s) =>
        s.replaceAll('\t', ' ').replaceAll(RegExp(r'\r?\n'), ' ').trim();
    final n = headers.length;
    final lines = <String>[headers.map(esc).join('\t')];
    for (final row in rows) {
      lines.add(
        [
          for (var i = 0; i < n; i++) esc(i < row.length ? row[i] : ''),
        ].join('\t'),
      );
    }
    return lines.join('\n');
  }
}
