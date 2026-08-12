// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'hid_scan_intake.dart';
import 'qr_route.dart';
import '../theme.dart';
import '../widgets/admin/admin_premium.dart';

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
  final TextEditingController _manualQrCtrl = TextEditingController();
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  @override
  void dispose() {
    _manualQrCtrl.dispose();
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

    // unknown hanya lolos jika eksplisit diizinkan (mis. barcode NIK karyawan).
    final unknownOk = result.type == QrPayloadType.unknown &&
        widget.allowedTypes?.contains(QrPayloadType.unknown) == true;
    if ((!unknownOk && result.type == QrPayloadType.unknown) ||
        !_isAllowed(result.type)) {
      if (widget.returnRawOnly &&
          widget.allowedTypes?.contains(QrPayloadType.attendance) == true &&
          result.type != QrPayloadType.attendance) {
        _snack('universal_qr_need_attendance'.tr(), color: OptikAdminTokens.warning);
        return;
      }
      _snack('universal_qr_unknown'.tr(), color: OptikAdminTokens.warning);
      return;
    }

    // Kunci sync sebelum await agar rapid detect tidak double-pop.
    _done = true;
    try {
      await _controller.stop();
    } catch (_) {}
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
      child: PremiumScaffold(
        appBar: AppBar(
          title: Text(widget.titleKey.tr()),
          actions: [
            IconButton(
              tooltip: 'universal_qr_torch'.tr(),
              icon: const Icon(Icons.flashlight_on_rounded),
              onPressed: () async {
                try {
                  await _controller.toggleTorch();
                } catch (_) {}
              },
            ),
          ],
        ),
        // Column (not Stack overlay): on Flutter web, MobileScanner's HTML
        // platform view paints above canvas siblings and hid the paste field.
        body: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller,
                    // Package pauses/resumes camera with app lifecycle by default.
                    useAppLifecycleState: true,
                    errorBuilder: (context, error) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.videocam_off_rounded,
                                color: OptikAdminTokens.danger,
                                size: 48,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'universal_qr_camera_denied'.tr(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: OptikAdminTokens.slate,
                                  height: 1.4,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
                      border: Border.all(color: OptikAdminTokens.navy, width: 3),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.hintKey.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: OptikAdminTokens.slate,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Web/desktop often has no camera / HID — paste or type payload.
                    Material(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      child: TextField(
                        controller: _manualQrCtrl,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'Tempel / ketik kode QR lalu Enter',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'Proses',
                            icon: const Icon(Icons.arrow_forward_rounded),
                            onPressed: () {
                              final raw = _manualQrCtrl.text.trim();
                              if (raw.isNotEmpty) _onRaw(raw);
                            },
                          ),
                        ),
                        onSubmitted: (v) {
                          final raw = v.trim();
                          if (raw.isNotEmpty) _onRaw(raw);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
