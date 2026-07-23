import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'liveness_result.dart';
import 'web_face_signature.dart';

enum _WebLiveStep {
  position,
  turnLeft,
  turnRight,
  holdStill,
  capturing,
}

/// Liveness + capture untuk Admin web (browser camera).
/// Challenge sederhana (posisi → hadap kiri → kanan → diam) + cek gerak frame.
/// Jujur: lebih lemah dari AWS / biometrik enterprise.
class WebFaceLivenessPage extends StatefulWidget {
  const WebFaceLivenessPage({super.key});

  @override
  State<WebFaceLivenessPage> createState() => _WebFaceLivenessPageState();
}

class _WebFaceLivenessPageState extends State<WebFaceLivenessPage> {
  CameraController? _camera;
  bool _booting = true;
  bool _busy = false;
  String? _error;
  _WebLiveStep _step = _WebLiveStep.position;
  List<double>? _prevSig;
  DateTime? _stepEnteredAt;

  static const _minStepMs = 1200;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _booting = false;
          _error = 'web_liveness_no_camera'.tr();
        });
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _booting = false;
        _stepEnteredAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = 'web_liveness_camera_denied'.tr();
      });
    }
  }

  String get _statusText {
    switch (_step) {
      case _WebLiveStep.position:
        return 'web_liveness_step_position'.tr();
      case _WebLiveStep.turnLeft:
        return 'web_liveness_step_left'.tr();
      case _WebLiveStep.turnRight:
        return 'web_liveness_step_right'.tr();
      case _WebLiveStep.holdStill:
        return 'web_liveness_step_still'.tr();
      case _WebLiveStep.capturing:
        return 'web_liveness_capturing'.tr();
    }
  }

  Color get _statusColor {
    switch (_step) {
      case _WebLiveStep.position:
        return Colors.orangeAccent;
      case _WebLiveStep.turnLeft:
      case _WebLiveStep.turnRight:
        return Colors.lightBlueAccent;
      case _WebLiveStep.holdStill:
        return Colors.tealAccent;
      case _WebLiveStep.capturing:
        return Colors.greenAccent;
    }
  }

  Future<Uint8List?> _snap() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return null;
    final shot = await cam.takePicture();
    return shot.readAsBytes();
  }

  Future<void> _onContinue() async {
    if (_busy || _camera == null) return;
    final entered = _stepEnteredAt;
    if (entered != null &&
        DateTime.now().difference(entered).inMilliseconds < _minStepMs) {
      _toast('web_liveness_wait'.tr());
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await _snap();
      if (bytes == null || bytes.length < 800) {
        throw 'web_liveness_frame_bad'.tr();
      }
      final sig = await WebFaceSignature.fromJpeg(bytes);
      if (sig == null) {
        throw 'web_liveness_face_unclear'.tr();
      }

      switch (_step) {
        case _WebLiveStep.position:
          _prevSig = sig;
          _go(_WebLiveStep.turnLeft);
          break;
        case _WebLiveStep.turnLeft:
          final motion = WebFaceSignature.motionScore(_prevSig, sig);
          if (motion < 0.06) {
            throw 'web_liveness_need_turn'.tr();
          }
          _prevSig = sig;
          _go(_WebLiveStep.turnRight);
          break;
        case _WebLiveStep.turnRight:
          final motion = WebFaceSignature.motionScore(_prevSig, sig);
          if (motion < 0.06) {
            throw 'web_liveness_need_turn'.tr();
          }
          _prevSig = sig;
          _go(_WebLiveStep.holdStill);
          break;
        case _WebLiveStep.holdStill:
          final motion = WebFaceSignature.motionScore(_prevSig, sig);
          if (motion > 0.22) {
            throw 'web_liveness_need_still'.tr();
          }
          await _finish(bytes, sig);
          return;
        case _WebLiveStep.capturing:
          break;
      }
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted && _step != _WebLiveStep.capturing) {
        setState(() => _busy = false);
      }
    }
  }

  void _go(_WebLiveStep next) {
    setState(() {
      _step = next;
      _stepEnteredAt = DateTime.now();
      _busy = false;
    });
  }

  Future<void> _finish(Uint8List bytes, List<double> sig) async {
    setState(() {
      _step = _WebLiveStep.capturing;
      _busy = true;
    });
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.pop(
      context,
      LivenessCaptureResult(
        success: true,
        photoBytes: bytes,
        faceTemplate: sig,
        livenessProvider: 'web',
        livenessConfidence: 70,
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orangeAccent),
    );
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('web_liveness_title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _error != null
            ? _errorBody()
            : _booting || _camera == null || !_camera!.value.isInitialized
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent),
                  )
                : _content(),
      ),
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                color: Colors.redAccent, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('web_liveness_cancel'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final preview = _camera!.value.previewSize!;
    final viewW = preview.width;
    final viewH = preview.height;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _statusColor.withValues(alpha: 0.7)),
              ),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'web_liveness_disclaimer'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth - 48;
                final frameW = maxW.clamp(180.0, 320.0);
                final frameH = frameW * 4 / 3;
                return Center(
                  child: Container(
                    width: frameW,
                    height: frameH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(frameW / 2),
                      border: Border.all(color: _statusColor, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: _statusColor.withValues(alpha: 0.25),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(frameW / 2),
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: viewW,
                          height: viewH,
                          child: CameraPreview(_camera!),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy || _step == _WebLiveStep.capturing
                    ? null
                    : _onContinue,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _step == _WebLiveStep.holdStill
                            ? 'web_liveness_capture'.tr()
                            : 'web_liveness_next'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
