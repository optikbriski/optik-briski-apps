import 'package:flutter/foundation.dart';

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

  static void bind({
    required UniversalQrCallerRole callerRole,
    Map<String, dynamic>? profile,
    String? cabangKaryawan,
    String? karyawanId,
    String? karyawanNama,
  }) {
    _notifier.value = UniversalQrHostData(
      callerRole: callerRole,
      profile: profile,
      cabangKaryawan: cabangKaryawan,
      karyawanId: karyawanId,
      karyawanNama: karyawanNama,
    );
  }

  static void clear() {
    _notifier.value = null;
  }
}
