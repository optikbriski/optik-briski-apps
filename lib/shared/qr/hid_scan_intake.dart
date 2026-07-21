import 'package:flutter/material.dart';

import 'qr_route.dart';

/// Page-local HID intake. Topmost registered scope wins.
///
/// Use to process QR meant for the current page without leave-confirm /
/// navigation (POS SKU, absensi OBRATT, penerimaan JSON, Scan QR camera page).
class HidScanIntake extends StatefulWidget {
  const HidScanIntake({
    super.key,
    required this.child,
    this.tryHandleKnown,
    this.onUnknown,
    this.onBeforeNavigate,
    this.isDirty,
    this.onSaveBeforeLeave,
  });

  final Widget child;

  /// Return `true` if this page consumed the known QR (no leave dialog / dispatch).
  final Future<bool> Function(QrRouteResult result)? tryHandleKnown;

  /// Unknown barcode (e.g. POS SKU). Return `true` if handled.
  final Future<bool> Function(String raw)? onUnknown;

  /// Replaces the default leave-to-run-QR dialog (POS draft). Return `true` to
  /// dispatch on top of the current route (no auto-pop).
  final Future<bool> Function(QrRouteResult result)? onBeforeNavigate;

  /// When dirty + [onSaveBeforeLeave] set, leave-to-run-QR offers save option.
  final bool Function()? isDirty;
  final Future<void> Function()? onSaveBeforeLeave;

  /// Topmost active intake (current route's scope).
  static HidScanIntakeState? get current =>
      _HidScanIntakeRegistry.current;

  @override
  State<HidScanIntake> createState() => HidScanIntakeState();
}

class HidScanIntakeState extends State<HidScanIntake> {
  @override
  void initState() {
    super.initState();
    _HidScanIntakeRegistry.push(this);
  }

  @override
  void dispose() {
    _HidScanIntakeRegistry.pop(this);
    super.dispose();
  }

  bool get offerSave {
    final dirty = widget.isDirty?.call() ?? false;
    return dirty && widget.onSaveBeforeLeave != null;
  }

  Future<void> saveBeforeLeave() async {
    final save = widget.onSaveBeforeLeave;
    if (save != null) await save();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _HidScanIntakeRegistry {
  static final List<HidScanIntakeState> _stack = <HidScanIntakeState>[];

  /// Topmost intake whose route is still current (skip covered pages e.g. POS under InvoiceHub).
  static HidScanIntakeState? get current {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final state = _stack[i];
      if (!state.mounted) continue;
      final route = ModalRoute.of(state.context);
      if (route == null || route.isCurrent) return state;
    }
    return null;
  }

  static void push(HidScanIntakeState state) => _stack.add(state);

  static void pop(HidScanIntakeState state) => _stack.remove(state);
}
