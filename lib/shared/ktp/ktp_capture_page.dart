import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../widgets/app_loading_overlay.dart';
import 'ktp_ocr_service.dart';

/// Halaman capture KTP: grid + auto jepret saat semua field OCR jelas terbaca.
class KtpCapturePage extends StatefulWidget {
  const KtpCapturePage({super.key});

  @override
  State<KtpCapturePage> createState() => _KtpCapturePageState();
}

class _KtpCapturePageState extends State<KtpCapturePage> {
  CameraController? _camera;
  final _ocr = KtpOcrService();

  bool _busy = false;
  bool _capturing = false;
  bool _torchOn = false;
  String? _error;
  String _status =
      'Sejajarkan KTP di grid — tunggu semua data terbaca jelas';
  Color _statusColor = Colors.white70;
  int _clearHits = 0;
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);

  static const _ktpAspect = 85.6 / 53.98; // rasio KTP Indonesia

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Kamera tidak ditemukan.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      setState(() {});
      await controller.startImageStream(_onFrame);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Gagal buka kamera: $e');
      }
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _capturing || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastScan).inMilliseconds < 800) return;
    _lastScan = now;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final result = await _ocr.scanInputImage(input);
      if (!mounted || _capturing) return;

      if (result.siapAutoCapture) {
        _clearHits++;
        setState(() {
          _status = _clearHits >= 2
              ? 'Semua data jelas — auto jepret…'
              : 'Semua data terbaca — tahan diam…';
          _statusColor = Colors.greenAccent;
        });
        if (_clearHits >= 2) {
          await _autoCapture();
        }
      } else {
        _clearHits = 0;
        final miss = result.fieldBelumJelas;
        final hint = miss.isEmpty
            ? 'Sejajarkan KTP di grid'
            : 'Belum jelas: ${miss.take(3).join(', ')}'
                '${miss.length > 3 ? '…' : ''}';
        if (_status != hint || _statusColor != Colors.amber) {
          setState(() {
            _status = hint;
            _statusColor =
                result.hasNik ? Colors.amber : Colors.white70;
          });
        }
      }
    } catch (e) {
      debugPrint('KTP live OCR: $e');
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final cam = _camera;
    if (cam == null) return null;

    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    late final Uint8List bytes;
    late final InputImageFormat format;

    if (isIOS) {
      final all = WriteBuffer();
      for (final p in image.planes) {
        all.putUint8List(p.bytes);
      }
      bytes = all.done().buffer.asUint8List();
      format = InputImageFormat.bgra8888;
    } else {
      bytes = _yuv420ToNv21(image);
      format = InputImageFormat.nv21;
    }

    final rotation = switch (cam.description.sensorOrientation) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: isIOS ? image.planes.first.bytesPerRow : image.width,
      ),
    );
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;
    final numPixels = width * height;
    final nv21 = Uint8List(numPixels + (numPixels ~/ 2));

    var idY = 0;
    final yRowStride = yPlane.bytesPerRow;
    for (var y = 0; y < height; y++) {
      final start = y * yRowStride;
      if (start + width <= yBuffer.length) {
        nv21.setRange(idY, idY + width, yBuffer, start);
      }
      idY += width;
    }

    var idUV = numPixels;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (var y = 0; y < height ~/ 2; y++) {
      for (var x = 0; x < width ~/ 2; x++) {
        final uIndex = y * uvRowStride + x * uvPixelStride;
        final vIndex =
            y * vPlane.bytesPerRow + x * (vPlane.bytesPerPixel ?? 1);
        if (vIndex < vBuffer.length && uIndex < uBuffer.length) {
          nv21[idUV++] = vBuffer[vIndex];
          nv21[idUV++] = uBuffer[uIndex];
        }
      }
    }
    return nv21;
  }

  Future<void> _autoCapture() async {
    if (_capturing) return;
    _capturing = true;
    try {
      await _camera?.stopImageStream();
    } catch (_) {}
    try {
      if (_torchOn) {
        try {
          await _camera?.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      // Sedikit jeda biar fokus stabil sebelum shutter.
      await Future.delayed(const Duration(milliseconds: 180));
      final shot = await _camera!.takePicture();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, File(shot.path));
    } catch (e) {
      _capturing = false;
      _clearHits = 0;
      if (mounted) {
        setState(() {
          _status = 'Gagal ambil foto — coba lagi';
          _statusColor = Colors.redAccent;
        });
        try {
          await _camera?.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
  }

  Future<void> _manualCapture() async {
    if (_capturing || _camera == null || !_camera!.value.isInitialized) return;
    setState(() {
      _status = 'Mengambil foto…';
      _statusColor = Colors.greenAccent;
    });
    await _autoCapture();
  }

  Future<void> _toggleTorch() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      _torchOn = !_torchOn;
      await cam.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Flash tidak tersedia di perangkat ini.'),
        ));
      }
    }
  }

  @override
  void dispose() {
    final cam = _camera;
    _camera = null;
    cam?.dispose();
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Kembali'),
                      ),
                    ],
                  ),
                ),
              )
            : cam == null || !cam.value.isInitialized
                ? const AppLoadingOverlay(
                    visible: true,
                    message: 'Menyiapkan kamera…',
                    subtitle: 'Izinkan akses kamera jika diminta',
                    barrierColor: Colors.black,
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: cam.value.previewSize?.height ?? 1280,
                          height: cam.value.previewSize?.width ?? 720,
                          child: CameraPreview(cam),
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final frame = _frameRect(constraints.biggest);
                          return CustomPaint(
                            painter: _KtpOverlayPainter(
                              frame: frame,
                              locked: _clearHits > 0 || _capturing,
                            ),
                            size: constraints.biggest,
                          );
                        },
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _toggleTorch,
                              icon: Icon(
                                _torchOn
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                color: _torchOn
                                    ? Colors.amber
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 28,
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _status,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _statusColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'KTP fisik saja. Auto jepret hanya jika NIK, nama, '
                              'alamat lengkap, TTL, gender, gol. darah, agama, '
                              'dan status kawin terbaca jelas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11.5,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: _capturing ? null : _manualCapture,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 4),
                                      color: _capturing
                                          ? Colors.green.withOpacity(0.4)
                                          : Colors.white24,
                                    ),
                                    child: _capturing
                                        ? const Padding(
                                            padding: EdgeInsets.all(20),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.camera_alt_rounded,
                                            color: Colors.white, size: 30),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Atau tekan untuk ambil manual',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      AppLoadingOverlay(
                        visible: _capturing,
                        message: 'Mengambil foto…',
                        subtitle: 'KTP terdeteksi jelas — menyimpan gambar',
                        barrierColor: Colors.black.withOpacity(0.55),
                      ),
                    ],
                  ),
      ),
    );
  }

  Rect _frameRect(Size size) {
    final maxW = size.width * 0.92;
    final maxH = size.height * 0.42;
    var w = maxW;
    var h = w / _ktpAspect;
    if (h > maxH) {
      h = maxH;
      w = h * _ktpAspect;
    }
    final left = (size.width - w) / 2;
    final top = (size.height * 0.30 - h / 2).clamp(72.0, size.height - h - 220);
    return Rect.fromLTWH(left, top, w, h);
  }
}

class _KtpOverlayPainter extends CustomPainter {
  _KtpOverlayPainter({required this.frame, required this.locked});

  final Rect frame;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withOpacity(0.58);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dim);

    final border = Paint()
      ..color = locked ? Colors.greenAccent : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = locked ? 3 : 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(12)),
      border,
    );

    // Grid 3x2 seperti area field KTP
    final grid = Paint()
      ..color = (locked ? Colors.greenAccent : Colors.white).withOpacity(0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), grid);
    }
    for (var i = 1; i < 2; i++) {
      final y = frame.top + frame.height * i / 2;
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), grid);
    }

    // Corner brackets
    final corner = Paint()
      ..color = locked ? Colors.greenAccent : const Color(0xFFF5C518)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 22.0;
    void bracket(Offset a, Offset b, Offset c) {
      canvas.drawLine(a, b, corner);
      canvas.drawLine(b, c, corner);
    }

    bracket(
      Offset(frame.left, frame.top + len),
      Offset(frame.left, frame.top),
      Offset(frame.left + len, frame.top),
    );
    bracket(
      Offset(frame.right - len, frame.top),
      Offset(frame.right, frame.top),
      Offset(frame.right, frame.top + len),
    );
    bracket(
      Offset(frame.left, frame.bottom - len),
      Offset(frame.left, frame.bottom),
      Offset(frame.left + len, frame.bottom),
    );
    bracket(
      Offset(frame.right - len, frame.bottom),
      Offset(frame.right, frame.bottom),
      Offset(frame.right, frame.bottom - len),
    );

    // Area foto KTP (kanan) hint
    final photoHint = Rect.fromLTWH(
      frame.left + frame.width * 0.68,
      frame.top + frame.height * 0.18,
      frame.width * 0.26,
      frame.height * 0.52,
    );
    final photoPaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(photoHint, const Radius.circular(4)),
      photoPaint,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: 'KTP',
        style: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        frame.center.dx - tp.width / 2,
        frame.top - 22,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _KtpOverlayPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.locked != locked;
}
