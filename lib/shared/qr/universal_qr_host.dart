import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'universal_qr_nav.dart';

/// Session data for the global HID → [UniversalQrNav] pipeline.
class UniversalQrHostData {
  const UniversalQrHostData({
    required this.callerRole,
    this.profile,
    this.cabangKaryawan,
    this.karyawanId,
    this.karyawanNama,
  });

  final UniversalQrCallerRole callerRole;
  final Map<String, dynamic>? profile;
  final String? cabangKaryawan;
  final String? karyawanId;
  final String? karyawanNama;
}

/// Bound by Admin dashboard / Karyawan shell while the user is logged in.
class UniversalQrHost {
  UniversalQrHost._();

  static final ValueNotifier<UniversalQrHostData?> _notifier =
      ValueNotifier<UniversalQrHostData?>(null);

  static ValueListenable<UniversalQrHostData?> get listenable => _notifier;

  static UniversalQrHostData? get current => _notifier.value;

  /// Safe from [State.initState] — defers notify so [ListenableBuilder] is not
  /// marked dirty during an active build (MaterialApp.builder shell).
  static void bind({
    required UniversalQrCallerRole callerRole,
    Map<String, dynamic>? profile,
    String? cabangKaryawan,
    String? karyawanId,
    String? karyawanNama,
  }) {
    _setLater(
      UniversalQrHostData(
        callerRole: callerRole,
        profile: profile,
        cabangKaryawan: cabangKaryawan,
        karyawanId: karyawanId,
        karyawanNama: karyawanNama,
      ),
    );
  }

  static void clear() {
    _setLater(null);
  }

  static void _setLater(UniversalQrHostData? next) {
    void apply() {
      _notifier.value = next;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    }
  }
}
