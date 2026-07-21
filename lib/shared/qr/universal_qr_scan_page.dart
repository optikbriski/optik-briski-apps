// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'hid_scan_intake.dart';
import 'qr_route.dart';

/// Satu halaman kamera QR. Hasil: [QrRouteResult] (mode navigate) atau [String] (returnRawOnly).
class UniversalQrScanPage extends StatefulWidget {
  const UniversalQrScanPage({
    super.key,
    this.allowedTypes,
    this.returnRawOnly = false,
    this.titleKey = 'scan_qr',
    this.hintKey = 'universal_qr_scan_hint',
  });

  /// Null = semua tipe dikenali. Mis. absensi: `{QrPayloadType.attendance}`.
  final Set<QrPayloadType>? allowedTypes;

  /// Jika true: pop dengan string mentah setelah tipe lolos filter.
  final bool returnRawOnly;

  final String titleKey;
  final String hintKey;

  /// Scan terbatas tipe tertentu → raw (null jika batal).
  static Future<String?> scanRaw(
    BuildContext context, {
    required Set<QrPayloadType> allowedTypes,
    String titleKey = 'scan_qr',
    String hintKey = 'attendance_qr_scan_hint',
  }) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => UniversalQrScanPage(
          allowedTypes: allowedTypes,
          returnRawOnly: true,
          titleKey: titleKey,
          hintKey: hintKey,
        ),
      ),
    );
  }

  /// Scan + klasifikasi → [QrRouteResult] (null jika batal / unknown diulang di halaman).
  static Future<QrRouteResult?> scanRouted(
    BuildContext context, {
    Set<QrPayloadType>? allowedTypes,
    String titleKey = 'scan_qr',
    String hintKey = 'universal_qr_scan_hint',
  }) {
    return Navigator.push<QrRouteResult>(
      context,
      MaterialPageRoute(
        builder: (_) => UniversalQrScanPage(
          allowedTypes: allowedTypes,
          returnRawOnly: false,
          titleKey: titleKey,
          hintKey: hintKey,
        ),
      ),
    );
  }

  @override
  State<UniversalQrScanPage> createState() => _UniversalQrScanPageState();
}

class _UniversalQrScanPageState extends State<UniversalQrScanPage> {
  bool _done = false;
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isAllowed(QrPayloadType type) {
    final allowed = widget.allowedTypes;
    if (allowed == null) return true;
    return allowed.contains(type);
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _onRaw(String raw) async {
    if (_done) return;
    final result = QrRouter.classify(raw);

    if (result.type == QrPayloadType.unknown || !_isAllowed(result.type)) {
      if (widget.returnRawOnly &&
          widget.allowedTypes?.contains(QrPayloadType.attendance) == true &&
          result.type != QrPayloadType.attendance) {
        _snack('universal_qr_need_attendance'.tr(), color: Colors.orange);
        return;
      }
      _snack('universal_qr_unknown'.tr(), color: Colors.orange);
      return;
    }

    _done = true;
    await _controller.stop();
    if (!mounted) return;

    if (widget.returnRawOnly) {
      Navigator.pop(context, result.raw);
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // HID on this page = same as camera detect (no leave-confirm).
    return HidScanIntake(
      tryHandleKnown: (result) async {
        await _onRaw(result.raw);
        return true;
      },
      onUnknown: (raw) async {
        await _onRaw(raw);
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.titleKey.tr()),
        ),
        body: Stack(
          alignment: Alignment.center,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_done) return;
                final barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;
                final raw = barcodes.first.rawValue;
                if (raw == null || raw.isEmpty) return;
                _onRaw(raw);
              },
            ),
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            Positioned(
              bottom: 48,
              left: 24,
              right: 24,
              child: Text(
                widget.hintKey.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
