// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/leave_page_guard.dart';
import 'hid_scan_intake.dart';
import 'qr_route.dart';
import 'universal_qr_host.dart';
import 'universal_qr_nav.dart';

/// USB / Bluetooth HID barcode scanners (keyboard wedge) without opening Scan QR.
///
/// Scanners type characters very fast then send Enter. Human typing is ignored
/// via inter-key timing. Keys are not stolen while an [EditableText] has focus
/// (forms / POS product search keep working).
///
/// With [global] `true` (MaterialApp.builder), listens on every route and runs
/// leave-confirm before navigable [UniversalQrNav] dispatch unless the top
/// [HidScanIntake] consumes the QR for the current page.
class HardwareBarcodeListener extends StatefulWidget {
  const HardwareBarcodeListener({
    super.key,
    required this.child,
    this.enabled = true,
    this.global = false,
    this.navigatorKey,
    this.callerRole = UniversalQrCallerRole.admin,
    this.profile,
    this.cabangKaryawan,
    this.karyawanId,
    this.karyawanNama,
    /// Unknown payload (not invoice / attendance / receive).
    /// Return `true` if handled (e.g. POS SKU lookup); otherwise snackbar.
    this.onUnknown,
    /// Known payload before [UniversalQrNav.dispatch].
    /// Return `false` to cancel (legacy per-page; prefer [HidScanIntake]).
    this.onBeforeKnownDispatch,
    this.maxInterKeyGap = const Duration(milliseconds: 50),
    this.idleFlush = const Duration(milliseconds: 120),
    this.minLength = 3,
  });

  final Widget child;
  final bool enabled;

  /// When true, ignore [ModalRoute.isCurrent] (shell above Navigator).
  final bool global;
  final GlobalKey<NavigatorState>? navigatorKey;

  final UniversalQrCallerRole callerRole;
  final Map<String, dynamic>? profile;
  final String? cabangKaryawan;
  final String? karyawanId;
  final String? karyawanNama;
  final Future<bool> Function(String raw)? onUnknown;
  final Future<bool> Function(QrRouteResult result)? onBeforeKnownDispatch;
  final Duration maxInterKeyGap;
  final Duration idleFlush;
  final int minLength;

  @override
  State<HardwareBarcodeListener> createState() =>
      _HardwareBarcodeListenerState();
}

class _HardwareBarcodeListenerState extends State<HardwareBarcodeListener> {
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyAt;
  Timer? _idleTimer;
  bool _burstActive = false;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _idleTimer?.cancel();
    super.dispose();
  }

  bool _isEditableFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Skip when covered by another route (e.g. Dashboard under POS).
  /// Global shell listener always stays active.
  bool _isRouteCurrent() {
    if (widget.global) return true;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  bool _isTerminator(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab;
  }

  void _resetBuffer() {
    _buffer.clear();
    _lastKeyAt = null;
    _burstActive = false;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _scheduleIdleFlush() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleFlush, () {
      if (!_burstActive || _buffer.isEmpty) {
        _resetBuffer();
        return;
      }
      _flush(fromIdle: true);
    });
  }

  BuildContext? _dispatchContext() {
    return widget.navigatorKey?.currentContext ??
        (mounted ? context : null);
  }

  NavigatorState? _navigator() {
    return widget.navigatorKey?.currentState ??
        (mounted ? Navigator.maybeOf(context) : null);
  }

  UniversalQrCallerRole get _role {
    return UniversalQrHost.current?.callerRole ?? widget.callerRole;
  }

  Map<String, dynamic>? get _profile {
    return UniversalQrHost.current?.profile ?? widget.profile;
  }

  String? get _cabang {
    return UniversalQrHost.current?.cabangKaryawan ?? widget.cabangKaryawan;
  }

  String? get _karyawanId {
    return UniversalQrHost.current?.karyawanId ?? widget.karyawanId;
  }

  String? get _karyawanNama {
    return UniversalQrHost.current?.karyawanNama ?? widget.karyawanNama;
  }

  Future<void> _dispatch(BuildContext ctx, QrRouteResult result) {
    return UniversalQrNav.dispatch(
      ctx,
      result,
      profile: _profile,
      callerRole: _role,
      cabangKaryawan: _cabang,
      karyawanId: _karyawanId,
      karyawanNama: _karyawanNama,
      fromAdminHidScanner: _role == UniversalQrCallerRole.admin,
    );
  }

  /// Confirm leave (unless page intake handles / POS dialog), then dispatch.
  Future<void> _handleKnown(BuildContext ctx, QrRouteResult result) async {
    final intake = HidScanIntake.current;

    if (intake?.widget.tryHandleKnown != null) {
      final handled = await intake!.widget.tryHandleKnown!(result);
      if (handled) return;
    }

    // Legacy per-page callback (kept for compatibility).
    if (widget.onBeforeKnownDispatch != null) {
      final proceed = await widget.onBeforeKnownDispatch!(result);
      if (!proceed) return;
      await _dispatch(ctx, result);
      return;
    }

    final wouldNav = UniversalQrNav.wouldNavigate(
      result,
      callerRole: _role,
      cabangKaryawan: _cabang,
    );

    if (!wouldNav) {
      await _dispatch(ctx, result);
      return;
    }

    // POS (or similar): custom dialog, stay on route, then dispatch on top.
    if (intake?.widget.onBeforeNavigate != null) {
      final proceed = await intake!.widget.onBeforeNavigate!(result);
      if (!proceed) return;
      final ctx2 = _dispatchContext();
      if (ctx2 == null || !ctx2.mounted) return;
      await _dispatch(ctx2, result);
      return;
    }

    final action = await LeavePageGuard.confirmLeaveToRunQr(
      ctx,
      offerSave: intake?.offerSave ?? false,
    );
    switch (action) {
      case null:
      case LeavePageAction.cancel:
        return;
      case LeavePageAction.leaveSave:
        await intake?.saveBeforeLeave();
        break;
      case LeavePageAction.leaveDiscard:
        break;
    }

    final nav = _navigator();
    if (nav != null && nav.canPop()) {
      nav.pop();
      await Future<void>.delayed(Duration.zero);
    }

    final ctx2 = _dispatchContext();
    if (ctx2 == null || !ctx2.mounted) return;
    await _dispatch(ctx2, result);
  }

  Future<void> _flush({bool fromIdle = false}) async {
    final raw = _buffer.toString().trim();
    final wasBurst = _burstActive;
    _resetBuffer();

    if (!wasBurst || raw.length < widget.minLength) return;
    if (!mounted || !widget.enabled || _handling) return;

    _handling = true;
    try {
      final ctx = _dispatchContext();
      if (ctx == null || !ctx.mounted) return;

      final result = QrRouter.classify(raw);
      if (result.isKnown) {
        await _handleKnown(ctx, result);
        return;
      }

      final intake = HidScanIntake.current;
      if (intake?.widget.onUnknown != null) {
        final handled = await intake!.widget.onUnknown!(raw);
        if (handled) return;
      }
      if (widget.onUnknown != null) {
        final handled = await widget.onUnknown!(raw);
        if (handled) return;
      }

      // Idle flush of unknown without Enter is noisy — only snack on terminator.
      if (fromIdle) return;

      await _dispatch(ctx, result);
    } finally {
      // Cooldown against double-scan / trailing Enter.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      _handling = false;
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!widget.enabled || _handling || !mounted) return false;
    if (!_isRouteCurrent()) {
      _resetBuffer();
      return false;
    }
    if (event is! KeyDownEvent) return false;

    // Never steal while the user (or a focused scan field) is editing text.
    if (_isEditableFocused()) {
      _resetBuffer();
      return false;
    }

    if (_isTerminator(event.logicalKey)) {
      if (_burstActive && _buffer.isNotEmpty) {
        _flush();
        return true;
      }
      _resetBuffer();
      return false;
    }

    final ch = event.character;
    if (ch == null || ch.isEmpty) return false;
    if (ch.codeUnitAt(0) < 32) return false;

    final now = DateTime.now();
    if (_lastKeyAt != null) {
      final gap = now.difference(_lastKeyAt!);
      if (gap > widget.maxInterKeyGap) {
        // Slow typing — discard and ignore this key for HID path.
        _resetBuffer();
        return false;
      }
    }

    _lastKeyAt = now;
    _burstActive = true;
    _buffer.write(ch);
    _scheduleIdleFlush();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wraps [MaterialApp] navigator child with global HID + leave-to-run-QR.
class GlobalHardwareBarcodeShell extends StatelessWidget {
  const GlobalHardwareBarcodeShell({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UniversalQrHost.listenable,
      builder: (context, _) {
        final host = UniversalQrHost.current;
        return HardwareBarcodeListener(
          global: true,
          navigatorKey: navigatorKey,
          enabled: host != null,
          callerRole: host?.callerRole ?? UniversalQrCallerRole.admin,
          profile: host?.profile,
          cabangKaryawan: host?.cabangKaryawan,
          karyawanId: host?.karyawanId,
          karyawanNama: host?.karyawanNama,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
