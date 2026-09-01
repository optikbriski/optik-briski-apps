import 'dart:io';
import 'dart:typed_data';

/// Cetak ESC/POS raw ke printer USB lewat antrian CUPS (macOS/Linux).
/// POS-80 hanya paham ESC/POS — jangan kirim PDF/PostScript.
class PosCupsPrint {
  PosCupsPrint._();

  static const _lpinfo = '/usr/sbin/lpinfo';
  static const _lpadmin = '/usr/sbin/lpadmin';
  static const _cupsenable = '/usr/sbin/cupsenable';
  static const _cupsaccept = '/usr/sbin/cupsaccept';
  static const _lpstat = '/usr/bin/lpstat';
  static const _lp = '/usr/bin/lp';
  static const _cancel = '/usr/bin/cancel';

  /// PPD passthrough (macOS menolak `-m raw`).
  static const String escPosPpd = r'''
*PPD-Adobe: "4.3"
*FormatVersion: "4.3"
*FileVersion: "1.0"
*LanguageVersion: English
*LanguageEncoding: ISOLatin1
*PCFileName: "ESCPOS.PPD"
*Manufacturer: "Rekasa"
*Product: "(ESC/POS Thermal)"
*ModelName: "ESC/POS Raw Passthrough"
*ShortNickName: "ESC/POS Raw"
*NickName: "ESC/POS Raw Passthrough"
*PSVersion: "(3010.000) 0"
*LanguageLevel: "3"
*ColorDevice: False
*DefaultColorSpace: Gray
*FileSystem: False
*Throughput: "1"
*LandscapeOrientation: Plus90
*TTRasterizer: Type42
*cupsVersion: 2.0
*cupsManualCopies: True
*cupsModelNumber: 0
*cupsFilter: "application/vnd.cups-raw 0 -"
*cupsFilter: "application/octet-stream 0 -"
*OpenUI *PageSize/Media Size: PickOne
*OrderDependency: 10 AnySetup *PageSize
*DefaultPageSize: Roll80
*PageSize Roll80/80mm Roll: "<</PageSize[226 841]/PageSize setpagedevice"
*PageRegion Roll80/80mm Roll: "<</PageSize[226 841]/PageSize setpagedevice"
*CloseUI: *PageSize
*DefaultImageableArea: Roll80
*ImageableArea Roll80: "0 0 226 841"
*DefaultPaperDimension: Roll80
*PaperDimension Roll80: "226 841"
''';

  static Future<List<String>> listQueues() async {
    final r = await Process.run(_lpstat, ['-a'], runInShell: false);
    if (r.exitCode != 0) return const [];
    final out = (r.stdout as String? ?? '').trim();
    if (out.isEmpty) return const [];
    return out
        .split('\n')
        .map((l) => l.trim().split(RegExp(r'\s+')).first)
        .where((n) => n.isNotEmpty)
        .toList();
  }

  static Future<String?> findUsbUri({String nameHint = 'POS-80'}) async {
    final r = await Process.run(_lpinfo, ['-v'], runInShell: false);
    if (r.exitCode != 0) return null;
    final hint = nameHint.toLowerCase();
    final lines = (r.stdout as String? ?? '').split('\n');
    for (final line in lines) {
      final t = line.trim();
      if (!t.startsWith('direct usb://')) continue;
      final uri = t.replaceFirst(RegExp(r'^direct\s+'), '').trim();
      if (uri.toLowerCase().contains(hint) ||
          uri.toLowerCase().contains('pos-80') ||
          uri.toLowerCase().contains('pos80')) {
        return uri;
      }
    }
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('direct usb://')) {
        return t.replaceFirst(RegExp(r'^direct\s+'), '').trim();
      }
    }
    return null;
  }

  static Future<String?> _queueDriverKind(String queue) async {
    final r =
        await Process.run(_lpstat, ['-l', '-p', queue], runInShell: false);
    final out = '${r.stdout}\n${r.stderr}'.toLowerCase();
    if (out.contains('postscript') || out.contains('generic')) {
      return 'postscript';
    }
    if (out.contains('esc/pos') ||
        out.contains('passthrough') ||
        out.contains('raw')) {
      return 'escpos';
    }
    return 'unknown';
  }

  /// Pastikan antrian CUPS ESC/POS ada (bukan Generic PostScript).
  static Future<String?> ensureQueue({
    String queue = 'POS-80',
    String nameHint = 'POS-80',
    bool recreateIfPostScript = true,
  }) async {
    final existing = await listQueues();
    final match = existing.cast<String?>().firstWhere(
          (n) =>
              n != null &&
              (n.toLowerCase() == queue.toLowerCase() ||
                  n.toLowerCase().contains('pos-80') ||
                  n.toLowerCase().contains('pos80')),
          orElse: () => null,
        );

    if (match != null) {
      final kind = await _queueDriverKind(match);
      if (kind != 'postscript' || !recreateIfPostScript) return match;
      await Process.run(_cancel, ['-a', match], runInShell: false);
      await Process.run(_lpadmin, ['-x', match], runInShell: false);
    }

    final uri = await findUsbUri(nameHint: nameHint);
    if (uri == null) return null;

    final ppdFile = File(
      '${Directory.systemTemp.path}/rekasa_escpos_$queue.ppd',
    );
    await ppdFile.writeAsString(escPosPpd, flush: true);

    final add = await Process.run(
      _lpadmin,
      [
        '-p',
        queue,
        '-E',
        '-v',
        uri,
        '-P',
        ppdFile.path,
        '-o',
        'printer-is-shared=false',
        '-D',
        'POS-80 ESC/POS',
        '-L',
        'USB',
      ],
      runInShell: false,
    );
    if (add.exitCode != 0) return null;

    await Process.run(_cupsenable, [queue], runInShell: false);
    await Process.run(_cupsaccept, [queue], runInShell: false);
    final after = await listQueues();
    if (after.any((n) => n.toLowerCase() == queue.toLowerCase())) {
      return queue;
    }
    return after.cast<String?>().firstWhere(
          (n) =>
              n != null &&
              (n.toLowerCase().contains('pos-80') ||
                  n.toLowerCase().contains('pos80')),
          orElse: () => null,
        );
  }

  static Future<void> cancelAll(String queue) async {
    await Process.run(_cancel, ['-a', queue], runInShell: false);
  }

  static Future<void> printRaw({
    required String queue,
    required List<int> bytes,
    String jobTitle = 'nota',
  }) async {
    final tmp = await File(
      '${Directory.systemTemp.path}/rekasa_pos_${DateTime.now().millisecondsSinceEpoch}.bin',
    ).create();
    try {
      await tmp.writeAsBytes(Uint8List.fromList(bytes), flush: true);
      final r = await Process.run(
        _lp,
        [
          '-d',
          queue,
          '-o',
          'raw',
          '-o',
          'document-format=application/vnd.cups-raw',
          '-t',
          jobTitle,
          tmp.path,
        ],
        runInShell: false,
      );
      if (r.exitCode != 0) {
        final err =
            ((r.stderr as String?) ?? (r.stdout as String?) ?? '').trim();
        throw err.isEmpty ? 'lp gagal (exit ${r.exitCode}).' : err;
      }
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
