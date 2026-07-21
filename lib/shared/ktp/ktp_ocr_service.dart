import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class KtpOcrResult {
  const KtpOcrResult({
    required this.nik,
    required this.nama,
    required this.alamatJalan,
    required this.rtRw,
    required this.kelDesa,
    required this.kecamatan,
    required this.alamat,
    required this.tempatLahir,
    required this.tanggalLahir,
    required this.tempatTglLahir,
    required this.jenisKelamin,
    required this.genderCode,
    required this.golonganDarah,
    required this.agama,
    required this.statusPerkawinan,
    required this.rawText,
  });

  final String nik;
  final String nama;
  final String alamatJalan;
  final String rtRw;
  final String kelDesa;
  final String kecamatan;

  /// Alamat KTP lengkap: jalan + RT/RW + kel/desa + kecamatan.
  final String alamat;
  final String tempatLahir;
  final String tanggalLahir;

  /// Contoh: JAKARTA, 26-12-2002
  final String tempatTglLahir;
  final String jenisKelamin;

  /// L / P (untuk form register).
  final String genderCode;
  final String golonganDarah;
  final String agama;
  final String statusPerkawinan;
  final String rawText;

  bool get hasNik => nik.length == 16;

  int? get umurDariLahir => hitungUmurDariTeks(
        tanggalLahir.isNotEmpty ? tanggalLahir : tempatTglLahir,
      );

  /// Umur per hari ini dari teks TTL / tanggal lahir KTP.
  /// Contoh: 20-07-2002 pada 20 Jul 2026 → 24; desember 2002 → 23 (sampai tgl lahir tahun ini).
  static int? hitungUmurDariTeks(String sumber, {DateTime? padaTanggal}) {
    final birth = parseTanggalLahir(sumber);
    if (birth == null) return null;
    return hitungUmur(birth, padaTanggal: padaTanggal);
  }

  static DateTime? parseTanggalLahir(String sumber) {
    final s = sumber.trim();
    if (s.isEmpty) return null;

    final full = RegExp(r'(\d{2})[-/.](\d{2})[-/.](\d{4})').firstMatch(s);
    if (full != null) {
      final d = int.tryParse(full.group(1)!);
      final mo = int.tryParse(full.group(2)!);
      final y = int.tryParse(full.group(3)!);
      if (d != null && mo != null && y != null) {
        try {
          return DateTime(y, mo, d);
        } catch (_) {}
      }
    }

    // "Desember 2002" / "12-2002" / "2002"
    const bulan = {
      'JANUARI': 1,
      'FEBRUARI': 2,
      'MARET': 3,
      'APRIL': 4,
      'MEI': 5,
      'JUNI': 6,
      'JULI': 7,
      'AGUSTUS': 8,
      'SEPTEMBER': 9,
      'OKTOBER': 10,
      'NOVEMBER': 11,
      'DESEMBER': 12,
    };
    final u = s.toUpperCase();
    for (final e in bulan.entries) {
      if (u.contains(e.key)) {
        final y = RegExp(r'(19|20)\d{2}').firstMatch(u);
        if (y != null) {
          try {
            return DateTime(int.parse(y.group(0)!), e.value, 1);
          } catch (_) {}
        }
      }
    }
    final my = RegExp(r'(\d{1,2})[-/.]((?:19|20)\d{2})').firstMatch(s);
    if (my != null) {
      try {
        return DateTime(int.parse(my.group(2)!), int.parse(my.group(1)!), 1);
      } catch (_) {}
    }
    final yOnly = RegExp(r'^(19|20)\d{2}$').firstMatch(s);
    if (yOnly != null) {
      try {
        return DateTime(int.parse(yOnly.group(0)!), 1, 1);
      } catch (_) {}
    }
    return null;
  }

  static int? hitungUmur(DateTime birth, {DateTime? padaTanggal}) {
    final now = padaTanggal ?? DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age >= 0 && age < 120 ? age : null;
  }

  int get filledFieldCount {
    var n = 0;
    if (hasNik) n++;
    if (nama.isNotEmpty) n++;
    if (alamat.isNotEmpty) n++;
    if (tempatTglLahir.isNotEmpty) n++;
    if (genderCode.isNotEmpty) n++;
    if (golonganDarah.isNotEmpty) n++;
    if (agama.isNotEmpty) n++;
    if (statusPerkawinan.isNotEmpty) n++;
    return n;
  }

  /// Alamat cukup lengkap untuk auto-jepret (jalan + RT/RW atau kel+kec).
  bool get alamatLengkapJelas =>
      alamatJalan.length >= 5 &&
      (rtRw.isNotEmpty || (kelDesa.isNotEmpty && kecamatan.isNotEmpty));

  /// Semua field yang diisi otomatis sudah terbaca jelas → boleh auto capture.
  bool get siapAutoCapture =>
      hasNik &&
      nama.length >= 3 &&
      alamatLengkapJelas &&
      tempatTglLahir.isNotEmpty &&
      genderCode.isNotEmpty &&
      golonganDarah.isNotEmpty &&
      agama.isNotEmpty &&
      statusPerkawinan.isNotEmpty;

  List<String> get fieldBelumJelas {
    final miss = <String>[];
    if (!hasNik) miss.add('NIK');
    if (nama.length < 3) miss.add('Nama');
    if (!alamatLengkapJelas) miss.add('Alamat+RT/RW/Kel/Kec');
    if (tempatTglLahir.isEmpty) miss.add('TTL');
    if (genderCode.isEmpty) miss.add('Gender');
    if (golonganDarah.isEmpty) miss.add('Gol. darah');
    if (agama.isEmpty) miss.add('Agama');
    if (statusPerkawinan.isEmpty) miss.add('Status kawin');
    return miss;
  }
}

/// OCR lokal KTP Indonesia — field lengkap + alamat RT/RW/kel/kec.
class KtpOcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<KtpOcrResult> scanFile(File file) async {
    final input = InputImage.fromFile(file);
    return scanInputImage(input);
  }

  Future<KtpOcrResult> scanInputImage(InputImage input) async {
    final recognized = await _recognizer.processImage(input);
    return parseRecognized(recognized);
  }

  KtpOcrResult parseRecognized(RecognizedText recognized) {
    final raw = recognized.text;
    final lines = _lines(recognized);

    final nik = _extractNik(raw);
    final nama = _extractNama(raw, lines, nik);
    final jalan = _extractLabeled(lines, const [
      'alamat',
    ], stopHints: const [
      'rt/',
      'rw/',
      'kel/',
      'desa',
      'kecamatan',
      'agama',
      'status',
      'pekerjaan',
    ]);
    final rtRw = _normalizeRtRw(_extractLabeled(lines, const [
      'rt/rw',
      'rt / rw',
      'rtrw',
    ]));
    final kelDesa = _extractLabeled(lines, const [
      'kel/desa',
      'kelurahan',
      'kel / desa',
      'desa',
    ], stopHints: const [
      'kecamatan',
      'agama',
    ]);
    final kecamatan = _extractLabeled(lines, const [
      'kecamatan',
      'kec.',
    ], stopHints: const [
      'agama',
      'status',
      'pekerjaan',
    ]);

    final ttlRaw = _extractLabeled(lines, const [
      'tempat/tgl lahir',
      'tempat/tgl',
      'tempat tgl lahir',
      'tempat tanggal lahir',
    ], stopHints: const [
      'jenis kelamin',
      'gol',
      'alamat',
    ]);
    final parsedTtl = _parseTempatTglLahir(ttlRaw, raw);
    final jkRaw = _extractLabeled(lines, const [
      'jenis kelamin',
      'jeniskelamin',
    ], stopHints: const [
      'gol',
      'alamat',
    ]);
    final gender = _parseGender(jkRaw, raw);
    final golDarah = _normalizeGolDarah(_extractLabeled(lines, const [
      'gol. darah',
      'gol darah',
      'golongan darah',
      'gol.darah',
    ], stopHints: const [
      'alamat',
      'rt/',
    ]));
    final agama = _cleanTitle(_extractLabeled(lines, const [
      'agama',
    ], stopHints: const [
      'status',
      'pekerjaan',
    ]));
    final statusKawin = _cleanTitle(_extractLabeled(lines, const [
      'status perkawinan',
      'status perkawlnan',
      'status kawin',
    ], stopHints: const [
      'pekerjaan',
      'kewarganegaraan',
    ]));

    final alamat = _composeAlamat(
      jalan: jalan.isNotEmpty ? jalan : _extractAlamatFallback(raw, lines),
      rtRw: rtRw,
      kelDesa: kelDesa,
      kecamatan: kecamatan,
    );

    return KtpOcrResult(
      nik: nik,
      nama: nama,
      alamatJalan: jalan.isNotEmpty ? jalan : alamat,
      rtRw: rtRw,
      kelDesa: kelDesa,
      kecamatan: kecamatan,
      alamat: alamat,
      tempatLahir: parsedTtl.$1,
      tanggalLahir: parsedTtl.$2,
      tempatTglLahir: parsedTtl.$3,
      jenisKelamin: gender.$1,
      genderCode: gender.$2,
      golonganDarah: golDarah,
      agama: agama,
      statusPerkawinan: statusKawin,
      rawText: raw,
    );
  }

  String _composeAlamat({
    required String jalan,
    required String rtRw,
    required String kelDesa,
    required String kecamatan,
  }) {
    final parts = <String>[];
    if (jalan.isNotEmpty) parts.add(jalan);
    if (rtRw.isNotEmpty) parts.add('RT/RW $rtRw');
    if (kelDesa.isNotEmpty) parts.add('Kel/Desa $kelDesa');
    if (kecamatan.isNotEmpty) parts.add('Kec. $kecamatan');
    return parts.join(', ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _extractNik(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ');
    final match = RegExp(r'\b(\d{16})\b').firstMatch(compact);
    if (match != null) return match.group(1)!;

    final digits = RegExp(r'(?:\d[\s\-]*){16}')
        .allMatches(compact)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[\s\-]'), ''))
        .where((s) => s.length == 16)
        .toList();
    return digits.isNotEmpty ? digits.first : '';
  }

  String _extractNama(String raw, List<String> lines, String nik) {
    final labeled = _extractLabeled(lines, const ['nama'], stopHints: const [
      'tempat',
      'jenis',
      'gol',
      'alamat',
    ]);
    if (labeled.isNotEmpty) return _cleanName(labeled);

    if (nik.isNotEmpty) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].replaceAll(RegExp(r'\s'), '').contains(nik) &&
            i + 1 < lines.length) {
          final next = _cleanName(lines[i + 1]);
          if (next.length >= 3 && !RegExp(r'^\d+$').hasMatch(next)) {
            return next;
          }
        }
      }
    }
    return '';
  }

  /// Ambil nilai setelah label di baris yang sama, atau baris berikutnya.
  String _extractLabeled(
    List<String> lines,
    List<String> labels, {
    List<String> stopHints = const [],
  }) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = _norm(line);
      for (final label in labels) {
        final li = lower.indexOf(_norm(label));
        if (li < 0) continue;

        // Hindari false match "nama" di dalam kata lain yang panjang.
        if (label == 'nama' &&
            (lower.contains('jenis kelamin') ||
                lower.contains('tempat') ||
                lower.contains('agama'))) {
          continue;
        }
        if (label == 'desa' &&
            (lower.contains('kel') || lower.contains('kecamatan'))) {
          // biarkan kel/desa ditangani label lain; "desa" saja OK jika tidak kel
        }

        var after = line.substring(
          (li + label.length).clamp(0, line.length),
        );
        after = after.replaceFirst(RegExp(r'^[\s:.\-]+'), '').trim();

        // Sering ada ":" terpisah / OCR buang label
        if (after.isEmpty && i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          final nLower = _norm(next);
          final isNextLabel = stopHints.any((h) => nLower.contains(_norm(h))) ||
              _looksLikeLabel(nLower);
          if (!isNextLabel && next.isNotEmpty) {
            after = next;
          }
        }

        // Potong jika label berikutnya menempel di baris yang sama.
        for (final h in stopHints) {
          final idx = _norm(after).indexOf(_norm(h));
          if (idx > 0) {
            after = after.substring(0, idx).trim();
          }
        }

        after = after
            .replaceAll(RegExp(r'^[:.\-\s]+'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (after.isNotEmpty) return after;
      }
    }
    return '';
  }

  String _extractAlamatFallback(String raw, List<String> lines) {
    final buf = <String>[];
    var capturing = false;
    for (final line in lines) {
      final lower = _norm(line);
      if (lower.contains('alamat')) {
        capturing = true;
        final after =
            line.split(RegExp(r'alamat\s*:?', caseSensitive: false));
        if (after.length > 1 && after[1].trim().isNotEmpty) {
          buf.add(after[1].trim());
        }
        continue;
      }
      if (!capturing) continue;
      if (lower.contains('agama') ||
          lower.contains('status perkawinan') ||
          lower.contains('pekerjaan') ||
          lower.contains('kewarganegaraan') ||
          lower.contains('berlaku')) {
        break;
      }
      if (lower.contains('rt/') ||
          lower.contains('kel/') ||
          lower.contains('desa') ||
          lower.contains('kecamatan') ||
          line.trim().length > 2) {
        buf.add(line.trim());
      }
    }
    if (buf.isNotEmpty) {
      return buf.join(', ').replaceAll(RegExp(r'\s+'), ' ');
    }
    final m = RegExp(
      r'alamat\s*:?\s*(.+?)(?:agama|status|pekerjaan|kewarganegaraan|berlaku)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    return m?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  }

  (String, String, String) _parseTempatTglLahir(String labeled, String raw) {
    var src = labeled;
    if (src.isEmpty) {
      final m = RegExp(
        r'tempat\s*/?\s*tgl\.?\s*lahir\s*:?\s*(.+?)(?:jenis|gol|alamat|rt/)',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(raw);
      src = m?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    }
    src = src.replaceAll(RegExp(r'\s+'), ' ').trim();
    final dateM =
        RegExp(r'(\d{2})\s*[-/.]\s*(\d{2})\s*[-/.]\s*(\d{4})').firstMatch(src);
    var tanggal = '';
    var tempat = src;
    if (dateM != null) {
      tanggal = '${dateM.group(1)}-${dateM.group(2)}-${dateM.group(3)}';
      tempat = src
          .substring(0, dateM.start)
          .replaceAll(RegExp(r'[,:\-\s]+$'), '')
          .trim();
    }
    tempat = tempat.toUpperCase();
    final combined = [
      if (tempat.isNotEmpty) tempat,
      if (tanggal.isNotEmpty) tanggal,
    ].join(', ');
    return (tempat, tanggal, combined);
  }

  (String, String) _parseGender(String labeled, String raw) {
    final src = labeled.toUpperCase().trim();
    if (src.contains('PEREMPUAN')) return ('PEREMPUAN', 'P');
    if (src.contains('LAKI')) return ('LAKI-LAKI', 'L');
    if (src == 'P') return ('PEREMPUAN', 'P');
    if (src == 'L') return ('LAKI-LAKI', 'L');

    final full = raw.toUpperCase();
    if (RegExp(r'\bPEREMPUAN\b').hasMatch(full)) return ('PEREMPUAN', 'P');
    if (RegExp(r'\bLAKI[\-\s]?LAKI\b').hasMatch(full) ||
        RegExp(r'\bLAKI\b').hasMatch(full)) {
      return ('LAKI-LAKI', 'L');
    }
    return ('', '');
  }

  String _normalizeRtRw(String s) {
    final m = RegExp(r'(\d{1,3})\s*/\s*(\d{1,3})').firstMatch(s);
    if (m != null) {
      return '${m.group(1)!.padLeft(3, '0')}/${m.group(2)!.padLeft(3, '0')}';
    }
    final digits = RegExp(r'\d+').allMatches(s).map((e) => e.group(0)!).toList();
    if (digits.length >= 2) {
      return '${digits[0].padLeft(3, '0')}/${digits[1].padLeft(3, '0')}';
    }
    return s.replaceAll(RegExp(r'[^0-9/]'), '').trim();
  }

  String _normalizeGolDarah(String s) {
    final m = RegExp(r'\b(AB|A|B|O)\b\s*([+\-])?').firstMatch(s.toUpperCase());
    if (m != null) {
      final type = m.group(1)!;
      final rh = m.group(2) ?? '';
      return '$type$rh';
    }
    final compact = s.toUpperCase().replaceAll(RegExp(r'[^ABO+\-]'), '');
    if (compact.startsWith('AB')) return 'AB';
    if (compact.startsWith('A')) return 'A';
    if (compact.startsWith('B')) return 'B';
    if (compact.startsWith('O')) return 'O';
    return s.toUpperCase().trim();
  }

  bool _looksLikeLabel(String lower) {
    const labels = [
      'nik',
      'nama',
      'tempat',
      'jenis kelamin',
      'gol',
      'alamat',
      'rt/',
      'kel/',
      'kecamatan',
      'agama',
      'status',
      'pekerjaan',
      'kewarganegaraan',
      'berlaku',
    ];
    return labels.any(lower.contains);
  }

  List<String> _lines(RecognizedText recognized) {
    final out = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  String _cleanName(String s) {
    return s
        .replaceAll(RegExp(r"[^A-Za-z\s\.]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }

  String _cleanTitle(String s) {
    return s
        .replaceAll(RegExp(r'^[:.\-\s]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }

  Future<void> dispose() => _recognizer.close();
}
