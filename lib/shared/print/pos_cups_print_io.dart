import 'dart:io';
import 'dart:typed_data';

/// Cetak ESC/POS raw ke printer USB lewat antrian CUPS (macOS/Linux).
/// POS-80 biasanya muncul sebagai `usb://Printer/POS-80?...`.
class PosCupsPrint {
  PosCupsPrint._();

  static Future<List<String>> listQueues() async {
    final r = await Process.run('lpstat', ['-a'], runInShell: false);
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
    final r = await Process.run('lpinfo', ['-v'], runInShell: false);
    if (r.exitCode != 0) return null;
    final hint = nameHint.toLowerCase();
    final lines = (r.stdout as String? ?? '').split('\n');
    for (final line in lines) {
      final t = line.trim();
      if (!t.startsWith('direct usb://')) continue;
      final uri = t.replaceFirst(RegExp(r'^direct\s+'), '').trim();
      if (uri.toLowerCase().contains(hint.toLowerCase()) ||
          uri.toLowerCase().contains('pos-80') ||
          uri.toLowerCase().contains('pos80')) {
        return uri;
      }
    }
    // Fallback: USB printer pertama.
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('direct usb://')) {
        return t.replaceFirst(RegExp(r'^direct\s+'), '').trim();
      }
    }
    return null;
  }

  /// Pastikan antrian CUPS ada. Return nama queue siap pakai, atau null.
  static Future<String?> ensureQueue({
    String queue = 'POS-80',
    String nameHint = 'POS-80',
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
    if (match != null) return match;

    final uri = await findUsbUri(nameHint: nameHint);
    if (uri == null) return null;

    final add = await Process.run(
      'lpadmin',
      ['-p', queue, '-E', '-v', uri, '-m', 'raw'],
      runInShell: false,
    );
    if (add.exitCode != 0) {
      // Beberapa macOS menolak -m raw; coba tanpa model.
      final add2 = await Process.run(
        'lpadmin',
        ['-p', queue, '-E', '-v', uri],
        runInShell: false,
      );
      if (add2.exitCode != 0) return null;
    }
    await Process.run('cupsenable', [queue], runInShell: false);
    await Process.run('cupsaccept', [queue], runInShell: false);
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
        'lp',
        ['-d', queue, '-o', 'raw', '-t', jobTitle, tmp.path],
        runInShell: false,
      );
      if (r.exitCode != 0) {
        final err = ((r.stderr as String?) ?? (r.stdout as String?) ?? '')
            .trim();
        throw err.isEmpty ? 'lp gagal (exit ${r.exitCode}).' : err;
      }
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
