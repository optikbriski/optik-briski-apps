import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'liveness_result.dart';
import 'web_face_signature.dart';

enum _WebLiveStep {
  position,
  move,
  returnCenter,
  holdStill,
  capturing,
}

enum _MoveChallenge {
  turnLeft,
  turnRight,
  lookUp,
  lookDown,
}

enum _MoveVerdict { correct, wrong, noMotion, unclear }

/// Liveness gratis Admin web:
/// posisi → gerakan acak (benar/salah) sambil flash warna → diam → foto.
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
  DateTime? _stillStableSince;
  DateTime? _correctSince;
  Timer? _pollTimer;
  Timer? _colorTimer;

  late final List<_MoveChallenge> _moves;
  int _moveIndex = 0;
  double _neutralH = 0.5;
  double _neutralV = 0.5;
  double _baselineH = 0.5;
  double _baselineV = 0.5;

  /// true = sumbu dibalik (kamera mirror). Dikunci setelah kalibrasi 1x.
  bool _flipH = false;
  bool _flipV = false;
  bool _hCalibrated = false;
  bool _vCalibrated = false;
  int _wrongStreak = 0;

  _MoveVerdict? _lastVerdict;
  String? _feedback;

  static const _flashColors = <Color>[
    Color(0xFFFF3B30),
    Color(0xFF34C759),
    Color(0xFF007AFF),
    Color(0xFFFFFFFF),
  ];
  int _flashIndex = 0;
  final List<double> _flashLumas = [];
  bool _flashPassed = false;
  int _movesPassed = 0;
  bool _colorActive = false;

  static const _minStepMs = 700;
  static const _pollMs = 550;
  static const _holdStableMs = 800;
  static const _correctHoldMs = 450;
  static const _colorCycleMs = 900;
  static const _motionTurnMin = 0.05;
  static const _motionStillMax = 0.22;
  static const _minAxisShift = 0.032;
  static const _wrongAxisShift = 0.028;
  static const _centerSlack = 0.04;
  static const _minFlashLumaSpan = 0.018;
  static const _movesPerScan = 2;

  @override
  void initState() {
    super.initState();
    _moves = _pickRandomMoves();
    _boot();
  }

  static List<_MoveChallenge> _pickRandomMoves() {
    final pool = List<_MoveChallenge>.from(_MoveChallenge.values);
    pool.shuffle(math.Random());
    return pool.take(_movesPerScan).toList(growable: false);
  }

  _MoveChallenge get _currentMove =>
      _moves[_moveIndex.clamp(0, _moves.length - 1)];

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
      _startAutoPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = 'web_liveness_camera_denied'.tr();
      });
    }
  }

  void _startAutoPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: _pollMs),
      (_) => _autoTick(),
    );
  }

  void _startColorCycle() {
    if (_colorActive) return;
    _colorActive = true;
    _flashIndex = 0;
    _flashLumas.clear();
    _flashPassed = false;
    _colorTimer?.cancel();
    _colorTimer = Timer.periodic(
      const Duration(milliseconds: _colorCycleMs),
      (_) {
        if (!mounted || !_colorActive) return;
        setState(() {
          _flashIndex = (_flashIndex + 1) % _flashColors.length;
        });
      },
    );
  }

  void _stopColorCycle() {
    _colorActive = false;
    _colorTimer?.cancel();
    _colorTimer = null;
    if (_flashLumas.length >= 2) {
      final minL = _flashLumas.reduce((a, b) => a < b ? a : b);
      final maxL = _flashLumas.reduce((a, b) => a > b ? a : b);
      _flashPassed = (maxL - minL) >= _minFlashLumaSpan;
    } else {
      _flashPassed = true;
    }
  }

  void _noteLuma(double luma) {
    if (!_colorActive) return;
    _flashLumas.add(luma);
    // Batasi agar tidak membengkak.
    if (_flashLumas.length > 24) {
      _flashLumas.removeRange(0, _flashLumas.length - 24);
    }
  }

  Future<void> _autoTick() async {
    if (!mounted || _busy || _camera == null) return;
    if (_step == _WebLiveStep.capturing) return;
    final entered = _stepEnteredAt;
    if (entered != null &&
        DateTime.now().difference(entered).inMilliseconds < _minStepMs) {
      return;
    }
    await _evaluateStep(showErrors: false);
  }

  String _moveLabel(_MoveChallenge m) {
    switch (m) {
      case _MoveChallenge.turnLeft:
        return 'web_liveness_step_left'.tr();
      case _MoveChallenge.turnRight:
        return 'web_liveness_step_right'.tr();
      case _MoveChallenge.lookUp:
        return 'web_liveness_step_up'.tr();
      case _MoveChallenge.lookDown:
        return 'web_liveness_step_down'.tr();
    }
  }

  String get _moveProgressLabel => 'web_liveness_move_n'.tr(
        namedArgs: {
          'n': '${_moveIndex + 1}',
          'total': '${_moves.length}',
        },
      );

  String get _statusText {
    switch (_step) {
      case _WebLiveStep.position:
        return 'web_liveness_step_position'.tr();
      case _WebLiveStep.move:
        // Gerakan 2 tidak muncul sebelum gerakan 1 lolos.
        return '$_moveProgressLabel — ${_moveLabel(_currentMove)}';
      case _WebLiveStep.returnCenter:
        return 'web_liveness_step_return'.tr(
          namedArgs: {
            'n': '${_moveIndex + 1}',
            'next': '${_moveIndex + 2}',
          },
        );
      case _WebLiveStep.holdStill:
        return 'web_liveness_step_still'.tr();
      case _WebLiveStep.capturing:
        return 'web_liveness_capturing'.tr();
    }
  }

  Color get _statusColor {
    if (_feedback != null && _lastVerdict == _MoveVerdict.wrong) {
      return Colors.redAccent;
    }
    if (_feedback != null && _lastVerdict == _MoveVerdict.correct) {
      return Colors.greenAccent;
    }
    if (_colorActive) {
      return _flashColors[_flashIndex.clamp(0, _flashColors.length - 1)];
    }
    switch (_step) {
      case _WebLiveStep.position:
        return Colors.orangeAccent;
      case _WebLiveStep.move:
        return Colors.lightBlueAccent;
      case _WebLiveStep.returnCenter:
        return Colors.amberAccent;
      case _WebLiveStep.holdStill:
        return Colors.tealAccent;
      case _WebLiveStep.capturing:
        return Colors.greenAccent;
    }
  }

  Future<Uint8List?> _snap() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return null;
    if (cam.value.isTakingPicture) return null;
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
    await _evaluateStep(showErrors: true);
  }

  void _enterMoveStep() {
    _wrongStreak = 0;
    _correctSince = null;
    _baselineH = _neutralH;
    _baselineV = _neutralV;
    _startColorCycle(); // Flash warna jalan bersamaan dengan gerakan.
    setState(() {
      _step = _WebLiveStep.move;
      _stepEnteredAt = DateTime.now();
      _stillStableSince = null;
      _lastVerdict = null;
      _feedback = null;
      _busy = false;
    });
  }

  void _enterHoldStill() {
    // Warna tetap jalan sebentar sampai foto; penilaian luma di _stopColorCycle.
    setState(() {
      _step = _WebLiveStep.holdStill;
      _stepEnteredAt = DateTime.now();
      _stillStableSince = null;
      _correctSince = null;
      _lastVerdict = _MoveVerdict.correct;
      _feedback = 'web_liveness_correct'.tr();
      _busy = false;
    });
  }

  /// Putar sumbu H/V ke ruang "instruksi user" (kiri = kiri user).
  double _dH(double h) {
    final d = h - _baselineH;
    return _flipH ? -d : d;
  }

  double _dV(double v) {
    final d = v - _baselineV;
    return _flipV ? -d : d;
  }

  /// Konvensi non-mirror: hadap kiri user → pusat wajah geser ke kiri frame (dH < 0).
  _MoveVerdict _judgeMove(WebFacePose pose) {
    final motion =
        WebFaceSignature.motionScore(_prevSig, pose.signature);
    if (motion < _motionTurnMin * 0.35 &&
        (_dH(pose.horizontal).abs() < _minAxisShift * 0.5) &&
        (_dV(pose.vertical).abs() < _minAxisShift * 0.5)) {
      return _MoveVerdict.noMotion;
    }

    final dH = _dH(pose.horizontal);
    final dV = _dV(pose.vertical);

    switch (_currentMove) {
      case _MoveChallenge.turnLeft:
        if (dH <= -_minAxisShift) return _MoveVerdict.correct;
        if (dH >= _wrongAxisShift) return _MoveVerdict.wrong;
        return motion >= _motionTurnMin
            ? _MoveVerdict.unclear
            : _MoveVerdict.noMotion;
      case _MoveChallenge.turnRight:
        if (dH >= _minAxisShift) return _MoveVerdict.correct;
        if (dH <= -_wrongAxisShift) return _MoveVerdict.wrong;
        return motion >= _motionTurnMin
            ? _MoveVerdict.unclear
            : _MoveVerdict.noMotion;
      case _MoveChallenge.lookUp:
        if (dV <= -_minAxisShift) return _MoveVerdict.correct;
        if (dV >= _wrongAxisShift) return _MoveVerdict.wrong;
        return motion >= _motionTurnMin
            ? _MoveVerdict.unclear
            : _MoveVerdict.noMotion;
      case _MoveChallenge.lookDown:
        if (dV >= _minAxisShift) return _MoveVerdict.correct;
        if (dV <= -_wrongAxisShift) return _MoveVerdict.wrong;
        return motion >= _motionTurnMin
            ? _MoveVerdict.unclear
            : _MoveVerdict.noMotion;
    }
  }

  String _wrongMessage() {
    switch (_currentMove) {
      case _MoveChallenge.turnLeft:
        return 'web_liveness_wrong_left'.tr();
      case _MoveChallenge.turnRight:
        return 'web_liveness_wrong_right'.tr();
      case _MoveChallenge.lookUp:
        return 'web_liveness_wrong_up'.tr();
      case _MoveChallenge.lookDown:
        return 'web_liveness_wrong_down'.tr();
    }
  }

  /// Satu kali: kalau 3× salah arah kuat, balik asumsi mirror lalu minta ulangi.
  bool _tryCalibrateFromWrong(WebFacePose pose) {
    final isH = _currentMove == _MoveChallenge.turnLeft ||
        _currentMove == _MoveChallenge.turnRight;
    final isV = _currentMove == _MoveChallenge.lookUp ||
        _currentMove == _MoveChallenge.lookDown;
    if (isH && _hCalibrated) return false;
    if (isV && _vCalibrated) return false;
    if (_wrongStreak < 3) return false;

    if (isH) {
      _flipH = !_flipH;
      _hCalibrated = true;
    }
    if (isV) {
      _flipV = !_flipV;
      _vCalibrated = true;
    }
    _wrongStreak = 0;
    _correctSince = null;
    // Pakai posisi netral awal; arah dibaca ulang dengan sumbu yang sudah dibalik.
    _baselineH = _neutralH;
    _baselineV = _neutralV;
    return true;
  }

  Future<void> _evaluateStep({required bool showErrors}) async {
    if (_busy || _camera == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _snap();
      if (bytes == null || bytes.length < 800) {
        if (showErrors) throw 'web_liveness_frame_bad'.tr();
        return;
      }
      final pose = await WebFaceSignature.poseFromJpeg(bytes);
      if (pose == null) {
        _stillStableSince = null;
        _correctSince = null;
        if (showErrors) throw 'web_liveness_face_unclear'.tr();
        setState(() {
          _lastVerdict = _MoveVerdict.unclear;
          _feedback = 'web_liveness_face_unclear'.tr();
        });
        return;
      }
      _noteLuma(pose.meanLuma);

      switch (_step) {
        case _WebLiveStep.position:
          _prevSig = pose.signature;
          _neutralH = pose.horizontal;
          _neutralV = pose.vertical;
          _baselineH = _neutralH;
          _baselineV = _neutralV;
          _moveIndex = 0;
          _movesPassed = 0;
          _enterMoveStep();
          break;

        case _WebLiveStep.move:
          // Hanya gerakan ke-_moveIndex yang aktif; index naik setelah benar.
          final verdict = _judgeMove(pose);
          if (verdict == _MoveVerdict.correct) {
            _wrongStreak = 0;
            final now = DateTime.now();
            _correctSince ??= now;
            setState(() {
              _lastVerdict = _MoveVerdict.correct;
              _feedback = 'web_liveness_correct'.tr();
            });
            // Harus tahan arah benar sebentar — hindari flicker salah→benar.
            if (now.difference(_correctSince!).inMilliseconds <
                _correctHoldMs) {
              _prevSig = pose.signature;
              return;
            }
            _prevSig = pose.signature;
            _movesPassed = _moveIndex + 1;
            if (_moveIndex < _moves.length - 1) {
              // Belum naik index: gerakan 2 menunggu sampai kembali lurus.
              setState(() {
                _step = _WebLiveStep.returnCenter;
                _stepEnteredAt = DateTime.now();
                _correctSince = null;
                _feedback = 'web_liveness_correct'.tr();
                _lastVerdict = _MoveVerdict.correct;
              });
            } else {
              _enterHoldStill();
            }
            return;
          }

          _correctSince = null;

          if (verdict == _MoveVerdict.wrong) {
            _wrongStreak++;
            if (_tryCalibrateFromWrong(pose)) {
              setState(() {
                _lastVerdict = _MoveVerdict.unclear;
                _feedback = 'web_liveness_recalibrated'.tr();
              });
              if (showErrors) _toast('web_liveness_recalibrated'.tr());
              return;
            }
            setState(() {
              _lastVerdict = _MoveVerdict.wrong;
              _feedback = _wrongMessage();
            });
            if (showErrors) _toast(_wrongMessage());
            return;
          }

          // Belum gerak / belum jelas: update baseline pelan jika hampir diam.
          final motion =
              WebFaceSignature.motionScore(_prevSig, pose.signature);
          if (motion < _motionTurnMin * 0.45) {
            _baselineH = pose.horizontal;
            _baselineV = pose.vertical;
            _prevSig = pose.signature;
          }
          setState(() {
            _lastVerdict = verdict;
            _feedback = verdict == _MoveVerdict.noMotion
                ? 'web_liveness_need_turn'.tr()
                : 'web_liveness_need_clearer'.tr();
          });
          if (showErrors) {
            throw verdict == _MoveVerdict.noMotion
                ? 'web_liveness_need_turn'.tr()
                : 'web_liveness_need_clearer'.tr();
          }
          break;

        case _WebLiveStep.returnCenter:
          // Gerakan berikutnya baru dibuka setelah gerakan sebelumnya benar
          // dan wajah kembali ke tengah.
          final dH = (pose.horizontal - _neutralH).abs();
          final dV = (pose.vertical - _neutralV).abs();
          final motion =
              WebFaceSignature.motionScore(_prevSig, pose.signature);
          final centered = dH <= _centerSlack && dV <= _centerSlack;
          if (centered && motion <= _motionStillMax) {
            _prevSig = pose.signature;
            if (_moveIndex < _moves.length - 1) {
              _moveIndex++;
              _enterMoveStep();
            }
            return;
          }
          _prevSig = pose.signature;
          setState(() {
            _lastVerdict = null;
            _feedback = 'web_liveness_step_return'.tr(
              namedArgs: {
                'n': '${_moveIndex + 1}',
                'next': '${_moveIndex + 2}',
              },
            );
          });
          if (showErrors && !centered) {
            throw 'web_liveness_step_return'.tr(
              namedArgs: {
                'n': '${_moveIndex + 1}',
                'next': '${_moveIndex + 2}',
              },
            );
          }
          break;

        case _WebLiveStep.holdStill:
          final motion =
              WebFaceSignature.motionScore(_prevSig, pose.signature);
          if (motion > _motionStillMax) {
            _stillStableSince = null;
            _prevSig = pose.signature;
            if (showErrors) throw 'web_liveness_need_still'.tr();
            return;
          }
          if (showErrors) {
            await _finish(bytes, pose.signature);
            return;
          }
          final now = DateTime.now();
          _stillStableSince ??= now;
          if (now.difference(_stillStableSince!).inMilliseconds >=
              _holdStableMs) {
            await _finish(bytes, pose.signature);
            return;
          }
          _prevSig = pose.signature;
          break;

        case _WebLiveStep.capturing:
          break;
      }
    } catch (e) {
      if (showErrors) _toast(e.toString());
    } finally {
      if (mounted && _step != _WebLiveStep.capturing) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _finish(Uint8List bytes, List<double> sig) async {
    _pollTimer?.cancel();
    _stopColorCycle();
    setState(() {
      _step = _WebLiveStep.capturing;
      _busy = true;
    });
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final conf = 60 + (_movesPassed * 8) + (_flashPassed ? 10 : 0);
    Navigator.pop(
      context,
      LivenessCaptureResult(
        success: true,
        photoBytes: bytes,
        faceTemplate: sig,
        livenessProvider: 'web',
        livenessConfidence: conf.clamp(60, 90).toDouble(),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _lastVerdict == _MoveVerdict.wrong
            ? Colors.redAccent
            : Colors.orangeAccent,
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _colorTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flashBg = _colorActive
        ? _flashColors[_flashIndex].withValues(alpha: 0.88)
        : const Color(0xFF0F172A);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        color: flashBg,
        child: Scaffold(
          backgroundColor: Colors.transparent,
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
                      child:
                          CircularProgressIndicator(color: Colors.blueAccent),
                    )
                  : _content(),
        ),
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

  Widget _verdictChip() {
    if (_feedback == null ||
        (_step != _WebLiveStep.move &&
            _step != _WebLiveStep.returnCenter)) {
      return const SizedBox.shrink();
    }
    final ok = _lastVerdict == _MoveVerdict.correct;
    final bad = _lastVerdict == _MoveVerdict.wrong;
    final color = ok
        ? Colors.greenAccent
        : bad
            ? Colors.redAccent
            : Colors.amberAccent;
    final icon = ok
        ? Icons.check_circle_rounded
        : bad
            ? Icons.cancel_rounded
            : Icons.info_outline_rounded;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _feedback!,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moveProgressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _moves.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _moveIndex ||
                      (i == _moveIndex &&
                          _step != _WebLiveStep.move &&
                          _step != _WebLiveStep.returnCenter &&
                          i < _movesPassed)
                  ? Colors.tealAccent
                  : i < _movesPassed
                      ? Colors.tealAccent
                      : i == _moveIndex &&
                              (_step == _WebLiveStep.move ||
                                  _step == _WebLiveStep.returnCenter)
                          ? Colors.lightBlueAccent
                          : Colors.white24,
            ),
          ),
        ],
      ],
    );
  }

  Widget _content() {
    final preview = _camera!.value.previewSize!;
    final viewW = preview.width;
    final viewH = preview.height;
    final inFlash = _colorActive;
    final accent = _statusColor;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: inFlash ? 0.35 : 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.85)),
              ),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: inFlash ? Colors.white : accent,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ),
          _verdictChip(),
          const SizedBox(height: 10),
          _moveProgressDots(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _step == _WebLiveStep.move || _step == _WebLiveStep.returnCenter
                  ? 'web_liveness_random_hint'.tr()
                  : 'web_liveness_disclaimer'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: inFlash ? Colors.white70 : Colors.white38,
                fontSize: 12,
              ),
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
                      border: Border.all(color: accent, width: inFlash ? 8 : 4),
                      boxShadow: [
                        BoxShadow(
                          color:
                              accent.withValues(alpha: inFlash ? 0.55 : 0.25),
                          blurRadius: inFlash ? 36 : 18,
                          spreadRadius: inFlash ? 6 : 2,
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
            child: Column(
              children: [
                Text(
                  inFlash
                      ? 'web_liveness_colors_with_move_hint'.tr()
                      : 'Ikuti petunjuk — benar = lanjut, salah = ulangi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: inFlash ? Colors.white70 : Colors.white38,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
