/// Baris device USB untuk picker / auto-pick.
typedef PosUsbPickRow = ({
  int vid,
  int pid,
  String label,
  int? deviceClass,
  bool? hasPermission,
});

/// Logika murni pemilihan printer USB OTG (testable, tanpa platform I/O).
abstract final class PosUsbDevicePick {
  PosUsbDevicePick._();

  /// USB class 7 = Printer, 9 = Hub.
  static const usbClassPrinter = 7;
  static const usbClassHub = 9;

  static const knownPosPrinters = <({int vid, int pid})>[
    (vid: 1048, pid: 20497),
    (vid: 1046, pid: 20497),
    (vid: 1046, pid: 43707),
    (vid: 1155, pid: 22336),
    (vid: 1155, pid: 22337),
    (vid: 1171, pid: 34656),
    (vid: 1317, pid: 42752),
    (vid: 1317, pid: 42754),
  ];

  static bool isKnownPosPrinter(int vid, int pid) =>
      knownPosPrinters.any((d) => d.vid == vid && d.pid == pid);

  static bool isLikelyHub(int? deviceClass, String label) {
    if (deviceClass == usbClassHub) return true;
    final l = label.toLowerCase();
    return l.contains('hub') && !l.contains('printer');
  }

  static bool isLikelyPrinter({
    required int vid,
    required int pid,
    required String label,
    int? deviceClass,
  }) {
    if (deviceClass == usbClassPrinter) return true;
    if (isKnownPosPrinter(vid, pid)) return true;
    final l = label.toLowerCase();
    return l.contains('pos') ||
        l.contains('printer') ||
        l.contains('thermal') ||
        l.contains('esc/pos');
  }

  /// Kandidat cetak — bukan hub (hub tetap bisa muncul di picker manual).
  static List<T> printerCandidates<T>(
    List<T> devices,
    int Function(T) vidOf,
    int Function(T) pidOf,
    String Function(T) labelOf,
    int? Function(T) classOf,
  ) {
    return [
      for (final d in devices)
        if (!isLikelyHub(classOf(d), labelOf(d))) d,
    ];
  }

  static ({int vid, int pid})? pickPreferred({
    required List<PosUsbPickRow> devices,
    int? savedVid,
    int? savedPid,
  }) {
    if (devices.isEmpty) return null;

    final saved = devices.where(
      (d) => d.vid == savedVid && d.pid == savedPid && !isLikelyHub(d.deviceClass, d.label),
    );
    if (saved.isNotEmpty) {
      final d = saved.first;
      return (vid: d.vid, pid: d.pid);
    }

    final candidates = printerCandidates(
      devices,
      (d) => d.vid,
      (d) => d.pid,
      (d) => d.label,
      (d) => d.deviceClass,
    );

    final pool = candidates.isNotEmpty ? candidates : devices;

    for (final d in pool) {
      if (isLikelyPrinter(
        vid: d.vid,
        pid: d.pid,
        label: d.label,
        deviceClass: d.deviceClass,
      )) {
        return (vid: d.vid, pid: d.pid);
      }
    }

    final first = pool.first;
    // Hanya hub terlihat (printer di belakang hub belum enumerate) → null
    // agar printRaw coba fallback VID/PID POS-80 + dialog izin USB.
    if (isLikelyHub(first.deviceClass, first.label)) {
      return null;
    }
    return (vid: first.vid, pid: first.pid);
  }

  static bool needsManualPicker({
    required List<PosUsbPickRow> devices,
    int? savedVid,
    int? savedPid,
  }) {
    final printable = printerCandidates(
      devices,
      (d) => d.vid,
      (d) => d.pid,
      (d) => d.label,
      (d) => d.deviceClass,
    );
    final pool = printable.length >= 2 ? printable : devices;
    if (pool.length <= 1) return false;
    return !pool.any((d) => d.vid == savedVid && d.pid == savedPid);
  }
}
